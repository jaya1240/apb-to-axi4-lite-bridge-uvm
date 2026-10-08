// apb_seq_item.sv
//
// One APB transfer. Used both as the sequence item the APB driver
// consumes (rand fields) and as the observed transaction the APB monitor
// publishes (response/observed fields filled in).

class apb_seq_item extends uvm_sequence_item;
    `uvm_object_utils(apb_seq_item)

    // ---- stimulus ----
    rand bit [31:0]   addr;
    rand bit          write;
    rand bit [31:0]   wdata;
    rand bit [3:0]    strb;
    rand int unsigned idle_cycles; // idle gap before this transfer's SETUP phase

    // ---- observed / response ----
    bit [31:0]   rdata;
    bit          slverr;
    int unsigned wait_states; // access-phase cycles with PREADY low

    constraint c_align { addr[1:0] == 2'b00; }

    constraint c_addr_dist {
        addr dist {
            [32'h0000_0000 : 32'h0000_0FFF] :/ 6,
            [32'h0000_1000 : 32'h0000_FFFF] :/ 3,
            [32'h0001_0000 : 32'hFFFF_FFFF] :/ 1
        };
    }

    // APB4: PSTRB must be low for reads.
    constraint c_strb {
        if (write) {
            strb dist { 4'hF := 6, [4'h1 : 4'hE] :/ 3, 4'h0 := 1 };
        } else {
            strb == 4'h0;
        }
    }

    constraint c_idle { idle_cycles dist { 0 := 5, [1:3] :/ 3, [4:10] :/ 1 }; }

    function new(string name = "apb_seq_item");
        super.new(name);
    endfunction

    function string convert2string();
        return $sformatf("APB %s addr=0x%08x wdata=0x%08x strb=0x%0x | rdata=0x%08x slverr=%0b waits=%0d idle=%0d",
                         write ? "WR" : "RD", addr, wdata, strb, rdata, slverr, wait_states, idle_cycles);
    endfunction

endclass : apb_seq_item
