// apb_axi_tests.sv
//
// Base test runs a virtual sequence to completion, then lets the pipeline
// drain before ending. Subclasses only choose which virtual sequence.
//
//   bridge_directed_test : hand-written transfers, clean OKAY slave
//   bridge_random_test   : constrained-random traffic, mixed responses
//                          (OKAY / SLVERR / DECERR) and random delays
//   bridge_error_test    : every AXI response is an error
//   bridge_slow_test     : long slave delays -> many APB wait states

class bridge_base_test extends uvm_test;
    `uvm_component_utils(bridge_base_test)

    apb_axi_env      env;
    virtual apb_if   apb_vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = apb_axi_env::type_id::create("env", this);
        if (!uvm_config_db#(virtual apb_if)::get(this, "", "apb_vif", apb_vif))
            `uvm_fatal("NOVIF", "bridge_base_test: no apb_vif set in config_db")
    endfunction

    virtual function bridge_base_vseq create_vseq();
        bridge_directed_vseq v = bridge_directed_vseq::type_id::create("vseq");
        return v;
    endfunction

    task run_phase(uvm_phase phase);
        bridge_base_vseq vseq;
        phase.raise_objection(this);

        vseq = create_vseq();
        vseq.start(env.vseqr);

        // Let the last transfer's monitors/scoreboard settle.
        repeat (20) @(posedge apb_vif.clk);

        phase.drop_objection(this);
    endtask

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (env.scoreboard.num_compared == 0)
            `uvm_error("TEST_RESULT", "No transactions were compared -- the test did not exercise the bridge")
        else if (env.scoreboard.num_errors == 0)
            `uvm_info("TEST_RESULT", "=== ALL CHECKS PASSED ===", UVM_LOW)
        else
            `uvm_error("TEST_RESULT", $sformatf("=== %0d CHECK(S) FAILED ===", env.scoreboard.num_errors))
    endfunction

endclass : bridge_base_test

class bridge_directed_test extends bridge_base_test;
    `uvm_component_utils(bridge_directed_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function bridge_base_vseq create_vseq();
        bridge_directed_vseq v = bridge_directed_vseq::type_id::create("vseq");
        return v;
    endfunction
endclass : bridge_directed_test

class bridge_random_test extends bridge_base_test;
    `uvm_component_utils(bridge_random_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function bridge_base_vseq create_vseq();
        bridge_random_vseq v = bridge_random_vseq::type_id::create("vseq");
        return v;
    endfunction
endclass : bridge_random_test

class bridge_error_test extends bridge_base_test;
    `uvm_component_utils(bridge_error_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function bridge_base_vseq create_vseq();
        bridge_error_vseq v = bridge_error_vseq::type_id::create("vseq");
        return v;
    endfunction
endclass : bridge_error_test

class bridge_slow_test extends bridge_base_test;
    `uvm_component_utils(bridge_slow_test)
    function new(string name, uvm_component parent); super.new(name, parent); endfunction
    virtual function bridge_base_vseq create_vseq();
        bridge_slow_vseq v = bridge_slow_vseq::type_id::create("vseq");
        return v;
    endfunction
endclass : bridge_slow_test
