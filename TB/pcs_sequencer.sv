import uvm_pkg::*;
`include "uvm_macros.svh"

`include "pcs_item.sv"

class pcs_sequencer extends uvm_sequencer#(pcs_item)
 `uvm_component_utils(pcs_sequencer)

  function new(string name= "uvm_sequencer", uvm_component parent = null);
   super.new(name, parent);
  endfunction

endclass