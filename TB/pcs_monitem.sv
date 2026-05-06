`include "uvm_macros.svh"
import uvm_pkg::*;

class pcs_monitem extends uvm_sequence_item;

 bit rst_n;
 bit [8:0] enc_in;
 bit [11:0] enc_out;

`uvm_object_utils_begin(pcs_monitem)
 `uvm_field_int(rst_n,UVM_ALL_ON)
 `uvm_field_int(enc_in,UVM_ALL_ON)
 `uvm_field_int(enc_out,UVM_ALL_ON)
`uvm_object_utils_end

 function new(string name="pcs_monitem");
  super.new(name);
 endfunction

endclass 

