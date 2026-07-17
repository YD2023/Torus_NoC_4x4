import noc_pkg::*;

module router #(
  parameter int X_COORD = 0,
  parameter int Y_COORD = 0,
  parameter int FLIT_W  = noc_pkg::NOC_FLIT_W,
  parameter int VC_W    = noc_pkg::NOC_VC_W,
  parameter int FIFO_D  = 4
) (
  input logic clk,
  input logic rst_n,

  noc_link_if.sink   north_i,
  noc_link_if.source north_o,
  noc_link_if.sink   south_i,
  noc_link_if.source south_o,
  noc_link_if.sink   east_i,
  noc_link_if.source east_o,
  noc_link_if.sink   west_i,
  noc_link_if.source west_o,
  noc_link_if.sink   local_i,
  noc_link_if.source local_o,

  output logic [31:0] flits_received_o [noc_pkg::NOC_NUM_PORTS],
  output logic [31:0] flits_sent_o [noc_pkg::NOC_NUM_PORTS],
  output logic [31:0] packets_ejected_o
);
  localparam logic [noc_pkg::NOC_COORD_W-1:0] CUR_X = X_COORD[noc_pkg::NOC_COORD_W-1:0];
  localparam logic [noc_pkg::NOC_COORD_W-1:0] CUR_Y = Y_COORD[noc_pkg::NOC_COORD_W-1:0];

  noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) in_links [noc_pkg::NOC_NUM_PORTS] ();
  noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) out_links [noc_pkg::NOC_NUM_PORTS] ();

  assign in_links[noc_pkg::PORT_NORTH].valid = north_i.valid;
  assign in_links[noc_pkg::PORT_NORTH].flit  = north_i.flit;
  assign in_links[noc_pkg::PORT_NORTH].vc_id = north_i.vc_id;
  assign north_i.ready = in_links[noc_pkg::PORT_NORTH].ready;

  assign in_links[noc_pkg::PORT_SOUTH].valid = south_i.valid;
  assign in_links[noc_pkg::PORT_SOUTH].flit  = south_i.flit;
  assign in_links[noc_pkg::PORT_SOUTH].vc_id = south_i.vc_id;
  assign south_i.ready = in_links[noc_pkg::PORT_SOUTH].ready;

  assign in_links[noc_pkg::PORT_EAST].valid = east_i.valid;
  assign in_links[noc_pkg::PORT_EAST].flit  = east_i.flit;
  assign in_links[noc_pkg::PORT_EAST].vc_id = east_i.vc_id;
  assign east_i.ready = in_links[noc_pkg::PORT_EAST].ready;

  assign in_links[noc_pkg::PORT_WEST].valid = west_i.valid;
  assign in_links[noc_pkg::PORT_WEST].flit  = west_i.flit;
  assign in_links[noc_pkg::PORT_WEST].vc_id = west_i.vc_id;
  assign west_i.ready = in_links[noc_pkg::PORT_WEST].ready;

  assign in_links[noc_pkg::PORT_LOCAL].valid = local_i.valid;
  assign in_links[noc_pkg::PORT_LOCAL].flit  = local_i.flit;
  assign in_links[noc_pkg::PORT_LOCAL].vc_id = local_i.vc_id;
  assign local_i.ready = in_links[noc_pkg::PORT_LOCAL].ready;

  assign north_o.valid = out_links[noc_pkg::PORT_NORTH].valid;
  assign north_o.flit  = out_links[noc_pkg::PORT_NORTH].flit;
  assign north_o.vc_id = out_links[noc_pkg::PORT_NORTH].vc_id;
  assign out_links[noc_pkg::PORT_NORTH].ready = north_o.ready;

  assign south_o.valid = out_links[noc_pkg::PORT_SOUTH].valid;
  assign south_o.flit  = out_links[noc_pkg::PORT_SOUTH].flit;
  assign south_o.vc_id = out_links[noc_pkg::PORT_SOUTH].vc_id;
  assign out_links[noc_pkg::PORT_SOUTH].ready = south_o.ready;

  assign east_o.valid = out_links[noc_pkg::PORT_EAST].valid;
  assign east_o.flit  = out_links[noc_pkg::PORT_EAST].flit;
  assign east_o.vc_id = out_links[noc_pkg::PORT_EAST].vc_id;
  assign out_links[noc_pkg::PORT_EAST].ready = east_o.ready;

  assign west_o.valid = out_links[noc_pkg::PORT_WEST].valid;
  assign west_o.flit  = out_links[noc_pkg::PORT_WEST].flit;
  assign west_o.vc_id = out_links[noc_pkg::PORT_WEST].vc_id;
  assign out_links[noc_pkg::PORT_WEST].ready = west_o.ready;

  assign local_o.valid = out_links[noc_pkg::PORT_LOCAL].valid;
  assign local_o.flit  = out_links[noc_pkg::PORT_LOCAL].flit;
  assign local_o.vc_id = out_links[noc_pkg::PORT_LOCAL].vc_id;
  assign out_links[noc_pkg::PORT_LOCAL].ready = local_o.ready;

  for (genvar port = 0; port < noc_pkg::NOC_NUM_PORTS; port++) begin : gen_stub_links
    assign in_links[port].ready = 1'b0;
    assign out_links[port].valid = 1'b0;
    assign out_links[port].flit = '0;
    assign out_links[port].vc_id = '0;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      packets_ejected_o <= '0;
      for (int port = 0; port < noc_pkg::NOC_NUM_PORTS; port++) begin
        flits_received_o[port] <= '0;
        flits_sent_o[port] <= '0;
      end
    end else begin
      // TODO: update counters when the real datapath is connected.
      packets_ejected_o <= packets_ejected_o;
      for (int port = 0; port < noc_pkg::NOC_NUM_PORTS; port++) begin
        flits_received_o[port] <= flits_received_o[port];
        flits_sent_o[port] <= flits_sent_o[port];
      end
    end
  end

  // TODO: instantiate input port blocks, route computation, arbiters, and crossbar.
endmodule
