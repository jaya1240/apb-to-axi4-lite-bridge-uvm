// tb_top.sv
//
// Top-level testbench: clock/reset, the two protocol interfaces, the DUT,
// and config_db publication of the virtual interfaces.

`timescale 1ns/1ps

import uvm_pkg::*;
`include "uvm_macros.svh"
import apb_axi_tb_pkg::*;

module tb_top;

    localparam time CLK_PERIOD = 10ns; // 100 MHz

    logic clk = 0;
    logic rstn;

    always #(CLK_PERIOD/2) clk = ~clk;

    initial begin
        rstn = 1'b0;
        repeat (5) @(posedge clk);
        rstn = 1'b1;
    end

    apb_if       apb_bus (.clk(clk), .rstn(rstn));
    axi4_lite_if axi_bus (.clk(clk), .rstn(rstn));

    apb_to_axi_bridge dut (
        .clk  (clk),
        .rstn (rstn),
        .apb  (apb_bus),
        .axi  (axi_bus)
    );

    // Waveform dump for debugging in any VCD viewer.
    initial begin
        $dumpfile("waves.vcd");
        $dumpvars(0, tb_top);
    end

    initial begin
        uvm_config_db#(virtual apb_if)::set(null, "*", "apb_vif", apb_bus);
        uvm_config_db#(virtual axi4_lite_if)::set(null, "*", "axi_vif", axi_bus);
        run_test();
    end

    // Safety timeout in case a test hangs (e.g. AXI policy sequence starved).
    initial begin
        #5_000_000;
        `uvm_fatal("TB_TIMEOUT", "Testbench timed out")
    end

endmodule : tb_top
