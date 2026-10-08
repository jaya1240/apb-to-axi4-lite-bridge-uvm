// apb_axi_ref_model.sv
//
// Behavioral reference model of the APB-to-AXI4-Lite translation
// contract, written directly from the protocol mapping (not from the
// RTL):
//
//   forward direction (APB request -> expected AXI request):
//     - direction, address pass straight through
//     - writes: PWDATA -> WDATA, PSTRB -> WSTRB
//
//   return direction (AXI response -> expected APB response):
//     - PSLVERR asserted  <=>  BRESP/RRESP != OKAY
//     - reads: PRDATA == RDATA. (Per the APB spec PRDATA is undefined
//       when PSLVERR is asserted, so callers only compare read data on
//       OKAY responses.)

class apb_axi_ref_model extends uvm_object;
    `uvm_object_utils(apb_axi_ref_model)

    function new(string name = "apb_axi_ref_model");
        super.new(name);
    endfunction

    // Expected AXI transaction for an observed APB transfer.
    function axi_txn predict_axi(apb_seq_item apb);
        axi_txn exp = axi_txn::type_id::create("exp_axi");
        exp.write = apb.write;
        exp.addr  = apb.addr;
        if (apb.write) begin
            exp.wdata = apb.wdata;
            exp.wstrb = apb.strb;
        end
        return exp;
    endfunction

    // Expected APB response given the AXI response the slave returned.
    function void predict_apb_response(axi_txn axi, output bit exp_slverr, output bit [31:0] exp_rdata);
        exp_slverr = (axi.resp != 2'b00);
        exp_rdata  = axi.write ? 32'b0 : axi.rdata;
    endfunction

endclass : apb_axi_ref_model
