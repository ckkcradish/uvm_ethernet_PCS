import uvm_pkg::*;
 `include "uvm_macros.svh"
 `include "pcs_if.sv"

class pcs_monitor extends uvm_monitor;
 `uvm_component_utils(pcs_monitor)

virtual pcs_if vif;

uvm_analysis_port#(pcs_monitem) mon_ap;


function new(string name= pcs_monitor, uvm_component parent= null);
 super.new(name,parent);
 mon_ap=new("mon_ap", this);
endfunction

function void build_phase(uvm_phase phase);
 super.build_phase(phase);

  if(!uvm_config_db#(virtual pcs_if)::get(this,"","vif",vif)) begin
     `uvm_fatal(get_type_name(), "failed to get virtual interface")
  end

endfunction

virtual task run_phase(uvm_phase phase);
 super.run_phase(phase);
  pcs_monitem monitem;
  forever begin
     @(vif.mon_cb);

     monitem.rst_n=vif.cb_mon.rst_n;
     monitem.enc_in=vif.cb_mon.enc_in;
     monitem.enc_out=vif.cb_mon.enc_out;

    mon_ap.write(monitem);
  end
endtask

endclass


     
