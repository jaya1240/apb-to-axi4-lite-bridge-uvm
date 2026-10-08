#!/usr/bin/env bash
# Compile and run the UVM testbench using Vivado's non-project xsim flow.
# Requires Vivado's bin directory on PATH (xvlog, xelab, xsim).
#
# Usage:
#   ./sim/run_sim.sh                        # bridge_directed_test (default)
#   ./sim/run_sim.sh bridge_random_test
#   ./sim/run_sim.sh bridge_error_test
#   ./sim/run_sim.sh bridge_slow_test
#
# Produces waves.vcd for waveform-based debugging. If xelab can't find
# uvm_pkg on your Vivado version, adjust the `-L uvm` flags below (the
# exact UVM-library flag has varied across Vivado releases).

set -euo pipefail
cd "$(dirname "$0")/.."

TESTNAME="${1:-bridge_directed_test}"

RTL_FILES=(
    rtl/apb_if.sv
    rtl/axi4_lite_if.sv
    rtl/apb_to_axi_bridge.sv
    rtl/apb_to_axi_sva.sv
)

TB_FILES=(
    tb/uvm/apb_axi_tb_pkg.sv
    tb/uvm/tb_top.sv
)

xvlog --sv -L uvm -i tb/uvm "${RTL_FILES[@]}" "${TB_FILES[@]}"
xelab -debug typical tb_top -s tb_sim -L uvm
xsim tb_sim -runall -testplusarg "UVM_TESTNAME=${TESTNAME}"

echo ""
echo "Waveform written to waves.vcd -- open with GTKWave or your viewer of choice."
