// axi_agent.sv
//
// AXI4-Lite *slave* agent. The bridge is the AXI master, so this agent's
// driver is reactive: it waits for the bridge to present an AW/W or AR
// request, pulls one response-policy item from its sequencer (delays,
// response code, read data), and answers accordingly. The monitor
// passively reconstructs each complete transaction from the bus.

typedef uvm_sequencer #(axi_resp_item) axi_sequencer;

// ---------------------------------------------------------------------
class axi_driver extends uvm_driver #(axi_resp_item);
    `uvm_component_utils(axi_driver)

    virtual axi4_lite_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "axi_vif", vif))
            `uvm_fatal("NOVIF", "axi_driver: no axi_vif set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        vif.awready <= 1'b0;
        vif.wready  <= 1'b0;
        vif.bvalid  <= 1'b0;
        vif.bresp   <= 2'b00;
        vif.arready <= 1'b0;
        vif.rvalid  <= 1'b0;
        vif.rdata   <= '0;
        vif.rresp   <= 2'b00;

        forever begin
            axi_resp_item item;
            bit           is_write;

            // Wait for the bridge to present a request.
            do @(posedge vif.clk);
            while (!vif.rstn || !(vif.awvalid || vif.arvalid));

            // Latch the request type at the detecting edge, before any
            // sequencer handshake delta cycles.
            is_write = vif.awvalid;

            seq_item_port.get_next_item(item);
            if (is_write) handle_write(item);
            else          handle_read(item);
            seq_item_port.item_done();
        end
    endtask

    // Assert a ready signal after `delay` extra cycles, hold it until the
    // handshake completes (valid observed high at an edge while ready is
    // high), then drop it.
    task automatic accept_aw(int unsigned delay);
        repeat (delay) @(posedge vif.clk);
        vif.awready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.awvalid) @(posedge vif.clk);
        vif.awready <= 1'b0;
    endtask

    task automatic accept_w(int unsigned delay);
        repeat (delay) @(posedge vif.clk);
        vif.wready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.wvalid) @(posedge vif.clk);
        vif.wready <= 1'b0;
    endtask

    task automatic accept_ar(int unsigned delay);
        repeat (delay) @(posedge vif.clk);
        vif.arready <= 1'b1;
        @(posedge vif.clk);
        while (!vif.arvalid) @(posedge vif.clk);
        vif.arready <= 1'b0;
    endtask

    task handle_write(axi_resp_item item);
        // AW and W handshake independently (either may complete first).
        fork
            accept_aw(item.aw_delay);
            accept_w(item.w_delay);
        join

        repeat (item.resp_delay) @(posedge vif.clk);
        vif.bvalid <= 1'b1;
        vif.bresp  <= item.resp;
        @(posedge vif.clk);
        while (!vif.bready) @(posedge vif.clk);
        vif.bvalid <= 1'b0;
    endtask

    task handle_read(axi_resp_item item);
        accept_ar(item.ar_delay);

        repeat (item.resp_delay) @(posedge vif.clk);
        vif.rvalid <= 1'b1;
        vif.rdata  <= item.rdata;
        vif.rresp  <= item.resp;
        @(posedge vif.clk);
        while (!vif.rready) @(posedge vif.clk);
        vif.rvalid <= 1'b0;
    endtask

endclass : axi_driver

// ---------------------------------------------------------------------
class axi_monitor extends uvm_monitor;
    `uvm_component_utils(axi_monitor)

    virtual axi4_lite_if vif;
    uvm_analysis_port #(axi_txn) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual axi4_lite_if)::get(this, "", "axi_vif", vif))
            `uvm_fatal("NOVIF", "axi_monitor: no axi_vif set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        bit          have_aw = 0, have_w = 0;
        bit [31:0]   w_addr = '0, w_data = '0, r_addr = '0;
        bit [3:0]    w_strb = '0;

        wait (vif.rstn === 1'b1);
        forever begin
            @(posedge vif.clk);
            if (!vif.rstn) begin
                have_aw = 0; have_w = 0;
                continue;
            end

            if (vif.awvalid && vif.awready) begin
                w_addr  = vif.awaddr;
                have_aw = 1;
            end
            if (vif.wvalid && vif.wready) begin
                w_data = vif.wdata;
                w_strb = vif.wstrb;
                have_w = 1;
            end
            if (vif.bvalid && vif.bready) begin
                axi_txn txn = axi_txn::type_id::create("axi_wr_txn");
                if (!(have_aw && have_w))
                    `uvm_error("AXI_MON", "B handshake observed before both AW and W handshakes completed")
                txn.write = 1;
                txn.addr  = w_addr;
                txn.wdata = w_data;
                txn.wstrb = w_strb;
                txn.resp  = vif.bresp;
                ap.write(txn);
                have_aw = 0;
                have_w  = 0;
            end

            if (vif.arvalid && vif.arready) begin
                r_addr = vif.araddr;
            end
            if (vif.rvalid && vif.rready) begin
                axi_txn txn = axi_txn::type_id::create("axi_rd_txn");
                txn.write = 0;
                txn.addr  = r_addr;
                txn.rdata = vif.rdata;
                txn.resp  = vif.rresp;
                ap.write(txn);
            end
        end
    endtask

endclass : axi_monitor

// ---------------------------------------------------------------------
class axi_agent extends uvm_agent;
    `uvm_component_utils(axi_agent)

    axi_sequencer sequencer;
    axi_driver    driver;
    axi_monitor   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = axi_sequencer::type_id::create("sequencer", this);
        driver    = axi_driver::type_id::create("driver", this);
        monitor   = axi_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass : axi_agent
