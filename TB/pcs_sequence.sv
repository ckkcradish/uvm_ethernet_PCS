import uvm_pkg::*;
`include "uvm_macros.svh"
`include "pcs_item.sv"

class pcs_sequence extends uvm_sequence(#pcs_item)
    `uvm_object_utils(pcs_sequence)


 rand int packet_num;

 constraint num_packets_c {
    packet_num inside {[1:10]};
  }

function new(string name = "pcs_sequence");
 super.new(name);
endfunction


virtual task body();
  pcs_item my_item;

  assert(this.randomize())
      else `uvm_fatal("SEQ_RAND", "pcs_psequence randomization failed")

  repeat(packet_num) begin 
    my_item = pcs_item::type_id::create("my_item");

     start_item(my_item);

      assert(my_item.randomize())
       else `uvm_fatal("ITEM_RAND", "pcs_item randomization failed")

     finish_item(my_item);
  end 

endtask

endclass