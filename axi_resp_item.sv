// axi_resp_item.sv
//
// A *response policy* for the reactive AXI slave driver: the bridge is
// the AXI master, so it (not the testbench) originates addresses and
// data. What the testbench controls is HOW the slave responds -- how long
// it delays each handshake, what response code it returns, and what data
// it hands back on a read. One item is consumed per AXI transaction the
// bridge issues.

typedef enum {
    RESP_OKAY_ONLY,   // always OKAY, zero delay (fast, clean slave)
    RESP_ERROR_ONLY,  // always SLVERR/DECERR
    RESP_MIXED,       // weighted mix of OKAY / SLVERR / DECERR, random delays
    RESP_SLOW         // always OKAY but with long delays (APB wait-state stress)
} axi_resp_mode_e;

class axi_resp_item extends uvm_sequence_item;
    `uvm_object_utils(axi_resp_item)

    rand int unsigned aw_delay;    // cycles before asserting AWREADY
    rand int unsigned w_delay;     // cycles before asserting WREADY
    rand int unsigned ar_delay;    // cycles before asserting ARREADY
    rand int unsigned resp_delay;  // cycles before BVALID / RVALID
    rand bit [1:0]    resp;        // 00 OKAY, 10 SLVERR, 11 DECERR
    rand bit [31:0]   rdata;       // data returned on a read

    constraint c_resp { resp dist { 2'b00 := 80, 2'b10 := 10, 2'b11 := 10 }; }
    constraint c_delays {
        aw_delay   dist { 0 := 5, [1:3] :/ 3, [4:12] :/ 1 };
        w_delay    dist { 0 := 5, [1:3] :/ 3, [4:12] :/ 1 };
        ar_delay   dist { 0 := 5, [1:3] :/ 3, [4:12] :/ 1 };
        resp_delay dist { 0 := 5, [1:3] :/ 3, [4:12] :/ 1 };
    }

    function new(string name = "axi_resp_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("AXI_RESP resp=%0d aw_d=%0d w_d=%0d ar_d=%0d resp_d=%0d rdata=0x%08x",
                         resp, aw_delay, w_delay, ar_delay, resp_delay, rdata);
    endfunction

endclass : axi_resp_item
