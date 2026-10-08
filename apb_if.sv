// apb_if.sv
//
// AMBA APB4 interface, master/slave modports. The bridge is an APB SLAVE
// (it's the target an APB master writes/reads through) and an AXI4-Lite
// MASTER (it issues the corresponding transaction on the AXI side).

interface apb_if #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rstn
);

    logic [ADDR_WIDTH-1:0]   paddr;
    logic                    pselx;
    logic                    penable;
    logic                    pwrite;
    logic [DATA_WIDTH-1:0]   pwdata;
    logic [DATA_WIDTH/8-1:0] pstrb;
    logic                    pready;
    logic [DATA_WIDTH-1:0]   prdata;
    logic                    pslverr;

    modport master ( // the APB master driving into the bridge (the TB's APB agent)
        output paddr, pselx, penable, pwrite, pwdata, pstrb,
        input  pready, prdata, pslverr
    );

    modport slave ( // the bridge's APB-facing port
        input  paddr, pselx, penable, pwrite, pwdata, pstrb,
        output pready, prdata, pslverr
    );

endinterface : apb_if
