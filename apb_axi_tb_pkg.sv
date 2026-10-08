// apb_axi_tb_pkg.sv
//
// UVM testbench package. Include order matters: each file only depends on
// classes/macros declared above it.

package apb_axi_tb_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // Declared once here (each invocation defines a class).
    `uvm_analysis_imp_decl(_apb)
    `uvm_analysis_imp_decl(_axi)

    `include "apb_seq_item.sv"
    `include "axi_txn.sv"
    `include "axi_resp_item.sv"
    `include "apb_agent.sv"
    `include "axi_agent.sv"
    `include "apb_axi_ref_model.sv"
    `include "apb_axi_scoreboard.sv"
    `include "apb_axi_coverage.sv"
    `include "apb_axi_seq_lib.sv"
    `include "apb_axi_env.sv"
    `include "apb_axi_tests.sv"

endpackage : apb_axi_tb_pkg
