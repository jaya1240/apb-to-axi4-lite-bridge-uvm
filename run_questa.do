# ModelSim/Questa batch simulation script.
# Usage: vsim -c -do sim/run_questa.do
#        (edit +UVM_TESTNAME below, or pass a different test name)
#
# Produces waves.vcd from the testbench's $dumpfile/$dumpvars.

vlib work

vlog -sv rtl/apb_if.sv
vlog -sv rtl/axi4_lite_if.sv
vlog -sv rtl/apb_to_axi_bridge.sv
vlog -sv rtl/apb_to_axi_sva.sv

vlog -sv +incdir+tb/uvm tb/uvm/apb_axi_tb_pkg.sv
vlog -sv tb/uvm/tb_top.sv

vsim -c -uvm work.tb_top +UVM_TESTNAME=bridge_directed_test -do "run -all; quit -f"
