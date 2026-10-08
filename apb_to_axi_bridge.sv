// apb_to_axi_bridge.sv
//
// Translates APB4 transactions (received on the bridge's APB slave port)
// into AXI4-Lite transactions (issued on the bridge's AXI4-Lite master
// port). One APB transfer maps to exactly one AXI4-Lite transaction --
// APB has no bursts, so there's no splitting/merging to do, just protocol
// sequencing and signal-width/meaning translation:
//   - PADDR         -> AWADDR (write) / ARADDR (read)
//   - PWDATA/PSTRB  -> WDATA/WSTRB
//   - PWRITE        -> selects the write or read AXI channel pair
//   - AXI BRESP/RRESP -> PSLVERR (non-OKAY response -> PSLVERR asserted)
//   - AXI RDATA     -> PRDATA
//
// Single-outstanding by construction: APB itself never has more than one
// transfer in flight, so there's no need for the bridge to pipeline
// multiple AXI transactions.

module apb_to_axi_bridge #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rstn,

    apb_if.slave        apb,
    axi4_lite_if.master axi
);

    typedef enum logic [2:0] {
        S_IDLE,
        S_AXI_WRITE,   // AWVALID/WVALID outstanding (independently, per-channel)
        S_AXI_BRESP,   // waiting for BVALID
        S_AXI_READ,    // ARVALID outstanding
        S_AXI_RRESP    // waiting for RVALID
    } state_t;

    state_t state;

    logic [ADDR_WIDTH-1:0]   addr_q;
    logic [DATA_WIDTH-1:0]   wdata_q;
    logic [DATA_WIDTH/8-1:0] wstrb_q;
    logic                     write_q;

    logic aw_done_q, w_done_q;

    // ---------------- APB outputs ----------------
    logic                   pready_r;
    logic [DATA_WIDTH-1:0] prdata_r;
    logic                   pslverr_r;

    assign apb.pready  = pready_r;
    assign apb.prdata  = prdata_r;
    assign apb.pslverr = pslverr_r;

    // ---------------- AXI outputs ----------------
    assign axi.awaddr  = addr_q;
    assign axi.awvalid = (state == S_AXI_WRITE) && !aw_done_q;
    assign axi.wdata   = wdata_q;
    assign axi.wstrb   = wstrb_q;
    assign axi.wvalid  = (state == S_AXI_WRITE) && !w_done_q;
    assign axi.bready  = (state == S_AXI_BRESP);
    assign axi.araddr  = addr_q;
    assign axi.arvalid = (state == S_AXI_READ);
    assign axi.rready  = (state == S_AXI_RRESP);

    // Mealy PREADY: assert the same cycle the AXI response arrives, so a
    // zero-extra-latency APB completion is possible once the AXI side
    // responds -- no need for an extra "complete" state.
    always_comb begin
        pready_r  = 1'b0;
        prdata_r  = '0;
        pslverr_r = 1'b0;

        if (state == S_AXI_BRESP && axi.bvalid) begin
            pready_r  = 1'b1;
            pslverr_r = (axi.bresp != 2'b00);
        end else if (state == S_AXI_RRESP && axi.rvalid) begin
            pready_r  = 1'b1;
            prdata_r  = axi.rdata;
            pslverr_r = (axi.rresp != 2'b00);
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state     <= S_IDLE;
            addr_q    <= '0;
            wdata_q   <= '0;
            wstrb_q   <= '0;
            write_q   <= 1'b0;
            aw_done_q <= 1'b0;
            w_done_q  <= 1'b0;
        end else begin
            unique case (state)
                S_IDLE: begin
                    // Latch at SETUP-phase entry (PSEL asserted, PENABLE
                    // still low) -- address/data are already stable here
                    // per the APB spec, giving the bridge a head start on
                    // issuing the AXI transaction before PREADY is even
                    // sampled (which only happens once PENABLE goes high).
                    if (apb.pselx && !apb.penable) begin
                        addr_q    <= apb.paddr;
                        wdata_q   <= apb.pwdata;
                        wstrb_q   <= apb.pstrb;
                        write_q   <= apb.pwrite;
                        aw_done_q <= 1'b0;
                        w_done_q  <= 1'b0;
                        state     <= apb.pwrite ? S_AXI_WRITE : S_AXI_READ;
                    end
                end

                S_AXI_WRITE: begin
                    if (axi.awvalid && axi.awready) aw_done_q <= 1'b1;
                    if (axi.wvalid  && axi.wready)  w_done_q  <= 1'b1;

                    if ((axi.awvalid && axi.awready || aw_done_q) &&
                        (axi.wvalid  && axi.wready  || w_done_q)) begin
                        state <= S_AXI_BRESP;
                    end
                end

                S_AXI_BRESP: begin
                    if (axi.bvalid && axi.bready) begin
                        state <= S_IDLE;
                    end
                end

                S_AXI_READ: begin
                    if (axi.arvalid && axi.arready) begin
                        state <= S_AXI_RRESP;
                    end
                end

                S_AXI_RRESP: begin
                    if (axi.rvalid && axi.rready) begin
                        state <= S_IDLE;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule : apb_to_axi_bridge
