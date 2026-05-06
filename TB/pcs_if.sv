interface pcs_if(input logic clk);

logic rst_n;
logic [8:0] enc_in;
logic [11:0] enc_out;


clocking cb_dr@(posedge clk);
 output rst_n;
 output enc_in;
 input enc_out;
endclocking

clocking cb_mon@(posedge clk);
 input rst_n;
 input enc_in;
 input enc_out;
endclocking

modport DRV(clocking cb_dr, input clk);
modport MON(clocking cb_mon, input clk);
modport DUT(input clk, input rst_n, input enc_in,output enc_out);

endinterface