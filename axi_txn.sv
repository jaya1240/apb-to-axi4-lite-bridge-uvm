// axi_txn.sv
//
// One observed AXI4-Lite transaction (write: AW+W+B, or read: AR+R),
// published by the AXI monitor once its response handshake completes.

class axi_txn extends uvm_sequence_item;
    `uvm_object_utils(axi_txn)

    bit          write;
    bit [31:0]   addr;
    bit [31:0]   wdata;
    bit [3:0]    wstrb;
    bit [31:0]   rdata;
    bit [1:0]    resp;   // BRESP (write) or RRESP (read)

    function new(string name = "axi_txn");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("AXI %s addr=0x%08x wdata=0x%08x wstrb=0x%0x rdata=0x%08x resp=%0d",
                         write ? "WR" : "RD", addr, wdata, wstrb, rdata, resp);
    endfunction

endclass : axi_txn
