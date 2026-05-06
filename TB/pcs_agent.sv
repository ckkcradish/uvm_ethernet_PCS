`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

class pcs_agent extends uvm_agent;
  `uvm_component_utils(pcs_agent)

  pcs_sequencer seqr;
  pcs_driver    drv;
  pcs_monitor   mon;

  virtual pcs_if vif;
  int pcs_id;

  function new(string name="pcs_agent", uvm_component parent=null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual pcs_if)::get(this, "", "vif", vif))
      `uvm_fatal("AGT", "vif not set")

    if (!uvm_config_db#(int)::get(this, "", "pcs_id", pcs_id))
      pcs_id = -1;

    seqr = pcs_sequencer::type_id::create("seqr", this);
    drv  = pcs_driver   ::type_id::create("drv",  this);
    mon  = pcs_monitor  ::type_id::create("mon",  this);

    uvm_config_db#(virtual pcs_if)::set(this, "drv", "vif", vif);
    uvm_config_db#(virtual pcs_if)::set(this, "mon", "vif", vif);

    uvm_config_db#(int)::set(this, "drv", "pcs_id", pcs_id);
    uvm_config_db#(int)::set(this, "mon", "pcs_id", pcs_id);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass