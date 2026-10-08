// apb_axi_seq_lib.sv
//
// Sequences:
//   APB side  : apb_base_seq (helper), apb_directed_seq, apb_random_seq
//   AXI side  : axi_resp_seq  (response-policy generator, mode-driven)
//   Virtual   : bridge_virtual_sequencer + bridge_*_vseq, which run an AXI
//               responder policy concurrently with an APB stimulus
//               sequence -- the AXI driver is reactive, so it needs
//               policy items available whenever the bridge issues a
//               request.

// ---------------------------------------------------------------------
class apb_base_seq extends uvm_sequence #(apb_seq_item);
    `uvm_object_utils(apb_base_seq)

    function new(string name = "apb_base_seq");
        super.new(name);
    endfunction

    // Send one fully-specified transfer.
    task do_xfer(bit [31:0] t_addr, bit t_write, bit [31:0] t_wdata,
                 bit [3:0] t_strb, int unsigned t_idle = 0);
        apb_seq_item item = apb_seq_item::type_id::create("item");
        start_item(item);
        if (!item.randomize() with {
                addr        == t_addr;
                write       == t_write;
                wdata       == t_wdata;
                strb        == t_strb;
                idle_cycles == t_idle;
            })
            `uvm_fatal("RANDFAIL", "apb_base_seq::do_xfer randomization failed")
        finish_item(item);
    endtask

endclass : apb_base_seq

// ---------------------------------------------------------------------
class apb_directed_seq extends apb_base_seq;
    `uvm_object_utils(apb_directed_seq)

    function new(string name = "apb_directed_seq");
        super.new(name);
    endfunction

    task body();
        // Basic write then read-back address
        do_xfer(32'h0000_0100, 1, 32'hDEAD_BEEF, 4'hF, 2);
        do_xfer(32'h0000_0100, 0, 32'h0,          4'h0, 2);

        // Partial write strobes
        do_xfer(32'h0000_0104, 1, 32'hA5A5_5A5A, 4'h3, 1);
        do_xfer(32'h0000_0108, 1, 32'h1234_5678, 4'hC, 1);
        do_xfer(32'h0000_010C, 1, 32'hFFFF_FFFF, 4'h0, 1); // legal all-zero strobe

        // Back-to-back writes then back-to-back reads (no idle gap)
        for (int i = 0; i < 4; i++)
            do_xfer(32'h0000_0200 + i*4, 1, 32'h1000_0000 + i, 4'hF, 0);
        for (int i = 0; i < 4; i++)
            do_xfer(32'h0000_0200 + i*4, 0, 32'h0, 4'h0, 0);

        // Alternating write/read, no gap
        for (int i = 0; i < 4; i++) begin
            do_xfer(32'h0000_0300, 1, 32'hC0DE_0000 + i, 4'hF, 0);
            do_xfer(32'h0000_0300, 0, 32'h0,             4'h0, 0);
        end

        // Address-range extremes
        do_xfer(32'h0000_0000, 1, 32'h0000_0001, 4'hF, 3);
        do_xfer(32'h0000_0000, 0, 32'h0,         4'h0, 0);
        do_xfer(32'hFFFF_FFFC, 1, 32'hFFFF_FFFF, 4'hF, 3);
        do_xfer(32'hFFFF_FFFC, 0, 32'h0,         4'h0, 0);

        // Long idle gap before a transfer
        do_xfer(32'h0000_0400, 0, 32'h0, 4'h0, 20);
    endtask

endclass : apb_directed_seq

// ---------------------------------------------------------------------
class apb_random_seq extends apb_base_seq;
    `uvm_object_utils(apb_random_seq)

    int unsigned num_items = 100;

    function new(string name = "apb_random_seq");
        super.new(name);
    endfunction

    task body();
        repeat (num_items) begin
            apb_seq_item item = apb_seq_item::type_id::create("item");
            start_item(item);
            if (!item.randomize())
                `uvm_fatal("RANDFAIL", "apb_random_seq randomization failed")
            finish_item(item);
        end
    endtask

endclass : apb_random_seq

// ---------------------------------------------------------------------
// AXI response-policy generator. Runs concurrently with the APB
// stimulus; consumed one item per AXI transaction the bridge issues.
class axi_resp_seq extends uvm_sequence #(axi_resp_item);
    `uvm_object_utils(axi_resp_seq)

    axi_resp_mode_e mode      = RESP_MIXED;
    int unsigned    num_items = 1000; // upper bound; extra items simply go unused

    function new(string name = "axi_resp_seq");
        super.new(name);
    endfunction

    task body();
        repeat (num_items) begin
            axi_resp_item item = axi_resp_item::type_id::create("item");
            start_item(item);
            case (mode)
                RESP_OKAY_ONLY: begin
                    if (!item.randomize() with {
                            resp == 2'b00; aw_delay == 0; w_delay == 0;
                            ar_delay == 0; resp_delay == 0; })
                        `uvm_fatal("RANDFAIL", "axi_resp_seq (OKAY_ONLY) randomization failed")
                end
                RESP_ERROR_ONLY: begin
                    if (!item.randomize() with { resp inside {2'b10, 2'b11}; })
                        `uvm_fatal("RANDFAIL", "axi_resp_seq (ERROR_ONLY) randomization failed")
                end
                RESP_SLOW: begin
                    if (!item.randomize() with {
                            resp == 2'b00;
                            aw_delay   inside {[5:15]};
                            w_delay    inside {[5:15]};
                            ar_delay   inside {[5:15]};
                            resp_delay inside {[5:15]}; })
                        `uvm_fatal("RANDFAIL", "axi_resp_seq (SLOW) randomization failed")
                end
                default: begin // RESP_MIXED: item's own weighted constraints
                    if (!item.randomize())
                        `uvm_fatal("RANDFAIL", "axi_resp_seq (MIXED) randomization failed")
                end
            endcase
            finish_item(item);
        end
    endtask

endclass : axi_resp_seq

// ---------------------------------------------------------------------
class bridge_virtual_sequencer extends uvm_sequencer;
    `uvm_component_utils(bridge_virtual_sequencer)

    apb_sequencer apb_seqr;
    axi_sequencer axi_seqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

endclass : bridge_virtual_sequencer

// ---------------------------------------------------------------------
// Base virtual sequence: starts the AXI responder policy in the
// background, runs the APB stimulus to completion in the foreground.
class bridge_base_vseq extends uvm_sequence;
    `uvm_object_utils(bridge_base_vseq)
    `uvm_declare_p_sequencer(bridge_virtual_sequencer)

    axi_resp_mode_e resp_mode = RESP_MIXED;

    function new(string name = "bridge_base_vseq");
        super.new(name);
    endfunction

    // Subclasses provide the APB stimulus.
    virtual function apb_base_seq create_apb_seq();
        apb_directed_seq s = apb_directed_seq::type_id::create("apb_seq");
        return s;
    endfunction

    task body();
        axi_resp_seq axi_seq = axi_resp_seq::type_id::create("axi_seq");
        apb_base_seq apb_seq = create_apb_seq();

        axi_seq.mode = resp_mode;

        fork
            axi_seq.start(p_sequencer.axi_seqr);
        join_none

        apb_seq.start(p_sequencer.apb_seqr);
    endtask

endclass : bridge_base_vseq

class bridge_directed_vseq extends bridge_base_vseq;
    `uvm_object_utils(bridge_directed_vseq)

    function new(string name = "bridge_directed_vseq");
        super.new(name);
        resp_mode = RESP_OKAY_ONLY;
    endfunction

    virtual function apb_base_seq create_apb_seq();
        apb_directed_seq s = apb_directed_seq::type_id::create("apb_seq");
        return s;
    endfunction
endclass : bridge_directed_vseq

class bridge_random_vseq extends bridge_base_vseq;
    `uvm_object_utils(bridge_random_vseq)

    function new(string name = "bridge_random_vseq");
        super.new(name);
        resp_mode = RESP_MIXED;
    endfunction

    virtual function apb_base_seq create_apb_seq();
        apb_random_seq s = apb_random_seq::type_id::create("apb_seq");
        s.num_items = 300;
        return s;
    endfunction
endclass : bridge_random_vseq

class bridge_error_vseq extends bridge_base_vseq;
    `uvm_object_utils(bridge_error_vseq)

    function new(string name = "bridge_error_vseq");
        super.new(name);
        resp_mode = RESP_ERROR_ONLY;
    endfunction

    virtual function apb_base_seq create_apb_seq();
        apb_random_seq s = apb_random_seq::type_id::create("apb_seq");
        s.num_items = 100;
        return s;
    endfunction
endclass : bridge_error_vseq

class bridge_slow_vseq extends bridge_base_vseq;
    `uvm_object_utils(bridge_slow_vseq)

    function new(string name = "bridge_slow_vseq");
        super.new(name);
        resp_mode = RESP_SLOW;
    endfunction

    virtual function apb_base_seq create_apb_seq();
        apb_random_seq s = apb_random_seq::type_id::create("apb_seq");
        s.num_items = 60;
        return s;
    endfunction
endclass : bridge_slow_vseq
