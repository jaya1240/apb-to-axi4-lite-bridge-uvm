# Vivado non-project-mode synthesis + timing analysis for the bridge
# (RTL only -- the UVM testbench and SVA/bind file are excluded).
#
# Usage:
#   vivado -mode batch -source scripts/synth.tcl
#
# Produces, under reports/: utilization.rpt, timing_summary.rpt,
# timing_worst_paths.rpt, synth.dcp

set part xc7a35ticsg324-1L  ;# Arty A7-35T; change to your target part

read_verilog -sv {
    rtl/apb_if.sv
    rtl/axi4_lite_if.sv
    rtl/apb_to_axi_bridge.sv
}

read_xdc constraints/apb_to_axi_bridge.xdc

synth_design -top apb_to_axi_bridge -part $part

file mkdir reports

report_utilization -file reports/utilization.rpt
report_timing_summary -file reports/timing_summary.rpt
report_timing -delay_type max -max_paths 10 -file reports/timing_worst_paths.rpt

write_checkpoint -force reports/synth.dcp

puts "Synthesis + timing analysis complete. See reports/."
