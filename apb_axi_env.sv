// apb_axi_env.sv
//
// Environment: APB master agent + AXI slave (reactive) agent, the
// scoreboard (with its reference model), the functional coverage
// collector, and a virtual sequencer for coordinated stimulus.

class apb_axi_env extends uvm_env;
    `uvm_component_utils(apb_axi_env)

    apb_agent                apb_ag;
    axi_agent                axi_ag;
    apb_axi_scoreboard       scoreboard;
    apb_axi_coverage         coverage;
    bridge_virtual_sequencer vseqr;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        apb_ag     = apb_agent::type_id::create("apb_ag", this);
        axi_ag     = axi_agent::type_id::create("axi_ag", this);
        scoreboard = apb_axi_scoreboard::type_id::create("scoreboard", this);
        coverage   = apb_axi_coverage::type_id::create("coverage", this);
        vseqr      = bridge_virtual_sequencer::type_id::create("vseqr", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);

        apb_ag.monitor.ap.connect(scoreboard.apb_export);
        axi_ag.monitor.ap.connect(scoreboard.axi_export);
        apb_ag.monitor.ap.connect(coverage.apb_export);
        axi_ag.monitor.ap.connect(coverage.axi_export);

        vseqr.apb_seqr = apb_ag.sequencer;
        vseqr.axi_seqr = axi_ag.sequencer;
    endfunction

endclass : apb_axi_env
