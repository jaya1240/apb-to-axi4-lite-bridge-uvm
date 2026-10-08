# Timing constraints for apb_to_axi_bridge.
# Adjust the clock period for your actual system clock. The bridge's
# interface signals connect to on-chip APB/AXI4-Lite logic in a real SoC,
# so no board-level I/O constraints are given here.

create_clock -name clk -period 10.000 [get_ports clk]

# Reset is asynchronous to the design's timing paths.
set_false_path -from [get_ports rstn]
