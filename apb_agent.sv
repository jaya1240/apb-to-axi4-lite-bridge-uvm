// apb_agent.sv
//
// APB master agent: drives APB4 transfers into the bridge's APB slave
// port and independently monitors the bus.
//
// Sampling convention used throughout the TB: signals are sampled right
// after `@(posedge clk)` in the active region (i.e. they hold their
// PRE-edge values, exactly what a synchronous receiver would capture at
// that edge) and driven with non-blocking assignments (visible after the
// edge). This matches how the DUT's always_ff blocks see the bus.

typedef uvm_sequencer #(apb_seq_item) apb_sequencer;

// ---------------------------------------------------------------------
class apb_driver extends uvm_driver #(apb_seq_item);
    `uvm_component_utils(apb_driver)

    virtual apb_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
            `uvm_fatal("NOVIF", "apb_driver: no apb_vif set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        vif.pselx   <= 1'b0;
        vif.penable <= 1'b0;
        vif.pwrite  <= 1'b0;
        vif.paddr   <= '0;
        vif.pwdata  <= '0;
        vif.pstrb   <= '0;

        wait (vif.rstn === 1'b1);
        @(posedge vif.clk);

        forever begin
            apb_seq_item item;
            seq_item_port.get_next_item(item);
            drive_transfer(item);
            seq_item_port.item_done();
        end
    endtask

    task drive_transfer(apb_seq_item item);
        // Idle gap (bus idle: PSEL low)
        if (item.idle_cycles > 0) begin
            vif.pselx   <= 1'b0;
            vif.penable <= 1'b0;
            repeat (item.idle_cycles) @(posedge vif.clk);
        end

        // SETUP phase: PSEL=1, PENABLE=0
        vif.paddr   <= item.addr;
        vif.pwrite  <= item.write;
        vif.pwdata  <= item.wdata;
        vif.pstrb   <= item.strb;
        vif.pselx   <= 1'b1;
        vif.penable <= 1'b0;
        @(posedge vif.clk);

        // ACCESS phase: PENABLE=1, hold until PREADY
        vif.penable <= 1'b1;
        @(posedge vif.clk);
        while (!vif.pready) @(posedge vif.clk);

        // Transfer completes at this edge (pre-edge PREADY was high).
        item.rdata  = vif.prdata;
        item.slverr = vif.pslverr;

        // Return to idle (a following back-to-back transfer overrides this
        // in the same timestep with its own SETUP-phase drive).
        vif.pselx   <= 1'b0;
        vif.penable <= 1'b0;
    endtask

endclass : apb_driver

// ---------------------------------------------------------------------
class apb_monitor extends uvm_monitor;
    `uvm_component_utils(apb_monitor)

    virtual apb_if vif;
    uvm_analysis_port #(apb_seq_item) ap;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", vif))
            `uvm_fatal("NOVIF", "apb_monitor: no apb_vif set in config_db")
    endfunction

    task run_phase(uvm_phase phase);
        int unsigned idle_cnt   = 0;
        int unsigned cur_idle   = 0;
        int unsigned wait_cnt   = 0;

        wait (vif.rstn === 1'b1);
        forever begin
            @(posedge vif.clk);
            if (!vif.rstn) begin
                idle_cnt = 0; wait_cnt = 0;
                continue;
            end

            if (!vif.pselx) begin
                idle_cnt++;
            end else if (!vif.penable) begin
                // SETUP phase: note how long the bus was idle before it.
                cur_idle = idle_cnt;
                idle_cnt = 0;
                wait_cnt = 0;
            end else begin
                // ACCESS phase
                if (vif.pready) begin
                    apb_seq_item txn = apb_seq_item::type_id::create("apb_txn");
                    txn.addr         = vif.paddr;
                    txn.write        = vif.pwrite;
                    txn.wdata        = vif.pwdata;
                    txn.strb         = vif.pstrb;
                    txn.rdata        = vif.prdata;
                    txn.slverr       = vif.pslverr;
                    txn.wait_states  = wait_cnt;
                    txn.idle_cycles  = cur_idle;
                    ap.write(txn);
                    wait_cnt = 0;
                end else begin
                    wait_cnt++;
                end
            end
        end
    endtask

endclass : apb_monitor

// ---------------------------------------------------------------------
class apb_agent extends uvm_agent;
    `uvm_component_utils(apb_agent)

    apb_sequencer sequencer;
    apb_driver    driver;
    apb_monitor   monitor;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        sequencer = apb_sequencer::type_id::create("sequencer", this);
        driver    = apb_driver::type_id::create("driver", this);
        monitor   = apb_monitor::type_id::create("monitor", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        driver.seq_item_port.connect(sequencer.seq_item_export);
    endfunction

endclass : apb_agent
