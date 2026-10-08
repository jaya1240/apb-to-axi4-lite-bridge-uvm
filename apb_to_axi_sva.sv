// apb_to_axi_sva.sv
//
// Protocol and FSM-invariant assertions for the bridge, bound
// automatically into every apb_to_axi_bridge instance.

module apb_to_axi_sva #(
    parameter int ADDR_WIDTH = 32,
    parameter int DATA_WIDTH = 32
) (
    input logic clk,
    input logic rstn,

    // APB side
    input logic pselx,
    input logic penable,
    input logic pready,
    input logic pwrite,
    input logic [ADDR_WIDTH-1:0] paddr,

    // AXI side
    input logic awvalid, awready,
    input logic wvalid,  wready,
    input logic bvalid,  bready,
    input logic arvalid, arready,
    input logic rvalid,  rready
);

    // ---------------- APB protocol ----------------

    // PSEL must be asserted before PENABLE (APB never jumps straight to
    // the access phase).
    property p_penable_needs_psel;
        @(posedge clk) disable iff (!rstn)
        $rose(penable) |-> pselx;
    endproperty
    a_penable_needs_psel: assert property (p_penable_needs_psel)
        else $error("[SVA] PENABLE asserted without PSEL");

    // Once in the access phase (PSEL && PENABLE) waiting on PREADY,
    // PSEL/PENABLE/PWRITE/PADDR must stay stable until PREADY completes
    // the transfer (APB spec requirement on the master, checked here to
    // catch a broken APB driver in the testbench too).
    property p_access_phase_stable;
        @(posedge clk) disable iff (!rstn)
        (pselx && penable && !pready) |=> (pselx && penable &&
            $stable(pwrite) && $stable(paddr));
    endproperty
    a_access_phase_stable: assert property (p_access_phase_stable)
        else $error("[SVA] APB address/control changed mid-access-phase before PREADY");

    // PENABLE is exactly one cycle in the setup phase before going high
    // (i.e. it can't stay low forever once PSEL is asserted -- every
    // asserted PSEL must be followed by exactly one setup cycle then
    // PENABLE high the next cycle).
    property p_setup_is_one_cycle;
        @(posedge clk) disable iff (!rstn)
        (pselx && !penable) |=> penable;
    endproperty
    a_setup_is_one_cycle: assert property (p_setup_is_one_cycle)
        else $error("[SVA] APB setup phase lasted more than one cycle");

    // ---------------- AXI4-Lite protocol (master-side obligations) ----------------

    // VALID must stay asserted until READY (checked on all five channels
    // the bridge drives/receives as VALID).
    property p_valid_stable(logic valid, logic ready);
        @(posedge clk) disable iff (!rstn)
        (valid && !ready) |=> valid;
    endproperty
    a_awvalid_stable: assert property (p_valid_stable(awvalid, awready));
    a_wvalid_stable:  assert property (p_valid_stable(wvalid,  wready));
    a_arvalid_stable: assert property (p_valid_stable(arvalid, arready));

    // ---------------- Bridge-level invariant ----------------

    // The bridge is single-outstanding: it must never have both a write
    // and a read address phase active at once.
    property p_no_concurrent_write_read;
        @(posedge clk) disable iff (!rstn)
        !((awvalid || wvalid || bvalid) && (arvalid || rvalid));
    endproperty
    a_no_concurrent_write_read: assert property (p_no_concurrent_write_read)
        else $error("[SVA] Bridge issued a read and a write AXI transaction concurrently");

endmodule : apb_to_axi_sva

bind apb_to_axi_bridge apb_to_axi_sva #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
) u_apb_to_axi_sva (
    .clk     (clk),
    .rstn    (rstn),
    .pselx   (apb.pselx),
    .penable (apb.penable),
    .pready  (apb.pready),
    .pwrite  (apb.pwrite),
    .paddr   (apb.paddr),
    .awvalid (axi.awvalid),
    .awready (axi.awready),
    .wvalid  (axi.wvalid),
    .wready  (axi.wready),
    .bvalid  (axi.bvalid),
    .bready  (axi.bready),
    .arvalid (axi.arvalid),
    .arready (axi.arready),
    .rvalid  (axi.rvalid),
    .rready  (axi.rready)
);
