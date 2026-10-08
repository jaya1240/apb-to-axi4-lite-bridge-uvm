// axi4_lite_if.sv
//
// AMBA AXI4-Lite interface, master/slave modports. The bridge is the
// AXI4-Lite MASTER here (it issues transactions); the TB's AXI agent acts
// as a reactive AXI4-Lite SLAVE responder.

interface axi4_lite_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rstn
);

    // Write address channel
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic                    awvalid;
    logic                    awready;

    // Write data channel
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wvalid;
    logic                    wready;

    // Write response channel
    logic [1:0]              bresp;
    logic                    bvalid;
    logic                    bready;

    // Read address channel
    logic [ADDR_WIDTH-1:0]   araddr;
    logic                    arvalid;
    logic                    arready;

    // Read data channel
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rvalid;
    logic                    rready;

    modport master (
        output awaddr, awvalid, input awready,
        output wdata, wstrb, wvalid, input wready,
        input  bresp, bvalid, output bready,
        output araddr, arvalid, input arready,
        input  rdata, rresp, rvalid, output rready
    );

    modport slave (
        input  awaddr, awvalid, output awready,
        input  wdata, wstrb, wvalid, output wready,
        output bresp, bvalid, input bready,
        input  araddr, arvalid, output arready,
        output rdata, rresp, rvalid, input rready
    );

endinterface : axi4_lite_if
