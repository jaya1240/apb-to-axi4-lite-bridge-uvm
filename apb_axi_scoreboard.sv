// apb_axi_scoreboard.sv
//
// Correlates each completed APB transfer with the AXI transaction it
// caused and checks both directions against the reference model:
//   1. the AXI request matches what the APB request should translate to
//      (direction, address, write data, write strobes), and
//   2. the APB response (PSLVERR, and PRDATA on OKAY reads) matches what
//      the AXI response should translate to.
//
// The bridge is single-outstanding, so APB transfers and AXI transactions
// occur strictly 1:1 and in order. The two monitors publish on the same
// clock edge (PREADY completes with the AXI response handshake), so the
// scoreboard queues each stream and compares whenever both have an entry
// -- independent of which analysis write() happens to be called first.

class apb_axi_scoreboard extends uvm_component;
    `uvm_component_utils(apb_axi_scoreboard)

    uvm_analysis_imp_apb #(apb_seq_item, apb_axi_scoreboard) apb_export;
    uvm_analysis_imp_axi #(axi_txn,      apb_axi_scoreboard) axi_export;

    apb_axi_ref_model ref_model;

    apb_seq_item apb_q[$];
    axi_txn      axi_q[$];

    int num_compared;
    int num_errors;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        apb_export = new("apb_export", this);
        axi_export = new("axi_export", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ref_model = apb_axi_ref_model::type_id::create("ref_model");
    endfunction

    function void write_apb(apb_seq_item t);
        apb_q.push_back(t);
        try_compare();
    endfunction

    function void write_axi(axi_txn t);
        axi_q.push_back(t);
        try_compare();
    endfunction

    function void try_compare();
        while (apb_q.size() > 0 && axi_q.size() > 0) begin
            apb_seq_item apb = apb_q.pop_front();
            axi_txn      axi = axi_q.pop_front();
            compare(apb, axi);
        end
    endfunction

    function void compare(apb_seq_item apb, axi_txn axi);
        axi_txn exp_axi = ref_model.predict_axi(apb);
        bit          exp_slverr;
        bit [31:0]   exp_rdata;
        string       ctx = $sformatf("#%0d", num_compared);

        num_compared++;

        // ---- 1. APB request -> AXI request ----
        if (axi.write !== exp_axi.write) begin
            `uvm_error("SB_DIR", $sformatf("%s direction mismatch: APB %s but AXI %s",
                       ctx, apb.write ? "WR" : "RD", axi.write ? "WR" : "RD"))
            num_errors++;
        end
        if (axi.addr !== exp_axi.addr) begin
            `uvm_error("SB_ADDR", $sformatf("%s address mismatch: expected 0x%08x got 0x%08x",
                       ctx, exp_axi.addr, axi.addr))
            num_errors++;
        end
        if (apb.write) begin
            if (axi.wdata !== exp_axi.wdata) begin
                `uvm_error("SB_WDATA", $sformatf("%s write-data mismatch: expected 0x%08x got 0x%08x",
                           ctx, exp_axi.wdata, axi.wdata))
                num_errors++;
            end
            if (axi.wstrb !== exp_axi.wstrb) begin
                `uvm_error("SB_WSTRB", $sformatf("%s write-strobe mismatch: expected 0x%0x got 0x%0x",
                           ctx, exp_axi.wstrb, axi.wstrb))
                num_errors++;
            end
        end

        // ---- 2. AXI response -> APB response ----
        ref_model.predict_apb_response(axi, exp_slverr, exp_rdata);

        if (apb.slverr !== exp_slverr) begin
            `uvm_error("SB_SLVERR", $sformatf("%s PSLVERR mismatch: AXI resp=%0d -> expected PSLVERR=%0b, got %0b",
                       ctx, axi.resp, exp_slverr, apb.slverr))
            num_errors++;
        end
        if (!apb.write && !exp_slverr && (apb.rdata !== exp_rdata)) begin
            `uvm_error("SB_RDATA", $sformatf("%s read-data mismatch: expected 0x%08x got 0x%08x",
                       ctx, exp_rdata, apb.rdata))
            num_errors++;
        end
    endfunction

    // Anything left unmatched at the end means the two sides disagreed
    // on how many transactions occurred.
    function void check_phase(uvm_phase phase);
        super.check_phase(phase);
        if (apb_q.size() != 0 || axi_q.size() != 0) begin
            `uvm_error("SB_UNMATCHED",
                $sformatf("Unmatched transactions at end of test: %0d APB, %0d AXI",
                          apb_q.size(), axi_q.size()))
            num_errors++;
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        `uvm_info("SB_SUMMARY",
            $sformatf("Compared %0d APB/AXI transaction pairs, %0d mismatch(es)", num_compared, num_errors),
            UVM_LOW)
    endfunction

endclass : apb_axi_scoreboard
