import noc_pkg::*;

module noc_interface_smoke_top #(
  parameter int TARGET = 1,
  parameter int X_COORD = 3,
  parameter int Y_COORD = 0,
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VC_W = noc_pkg::NOC_VC_W,
  parameter int FIFO_D = 3,
  parameter int COUNTER_W = 32
) (
  input  logic                                      clk,
  input  logic                                      rst_n,
  input  logic [noc_pkg::NOC_NUM_NODES-1:0]        local_in_valid_i,
  output logic [noc_pkg::NOC_NUM_NODES-1:0]        local_in_ready_o,
  input  logic [noc_pkg::NOC_NUM_NODES*FLIT_W-1:0] local_in_flit_i,
  input  logic [noc_pkg::NOC_NUM_NODES*VC_W-1:0]   local_in_vc_i,
  output logic [noc_pkg::NOC_NUM_NODES-1:0]        local_out_valid_o,
  input  logic [noc_pkg::NOC_NUM_NODES-1:0]        local_out_ready_i,
  output logic [noc_pkg::NOC_NUM_NODES*FLIT_W-1:0] local_out_flit_o,
  output logic [noc_pkg::NOC_NUM_NODES*VC_W-1:0]   local_out_vc_o
);
  localparam int NUM_NODES = noc_pkg::NOC_NUM_NODES;
  localparam int NUM_PORTS = noc_pkg::NOC_NUM_PORTS;
  localparam int NUM_VCS = noc_pkg::NOC_NUM_VCS;

  generate
    if (TARGET == 0) begin : gen_router
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) north_i_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) north_o_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) south_i_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) south_o_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) east_i_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) east_o_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) west_i_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) west_o_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) local_i_link();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) local_o_link();
      logic [NUM_VCS-1:0] unused_protocol_error [NUM_PORTS];
      logic [COUNTER_W-1:0] unused_flits_received [NUM_PORTS];
      logic [COUNTER_W-1:0] unused_flits_sent [NUM_PORTS];
      logic [COUNTER_W-1:0] unused_blocked_empty [NUM_PORTS];
      logic [COUNTER_W-1:0] unused_blocked_backpressure [NUM_PORTS];
      logic [COUNTER_W-1:0] unused_packets_ejected;

      noc_endpoint_link_adapter #(.FLIT_W(FLIT_W), .VC_W(VC_W)) u_north (
        .inject_o(north_i_link), .eject_i(north_o_link),
        .in_valid_i(local_in_valid_i[0]), .in_ready_o(local_in_ready_o[0]),
        .in_flit_i(local_in_flit_i[0*FLIT_W +: FLIT_W]),
        .in_vc_i(local_in_vc_i[0*VC_W +: VC_W]),
        .out_valid_o(local_out_valid_o[0]), .out_ready_i(local_out_ready_i[0]),
        .out_flit_o(local_out_flit_o[0*FLIT_W +: FLIT_W]),
        .out_vc_o(local_out_vc_o[0*VC_W +: VC_W])
      );
      noc_endpoint_link_adapter #(.FLIT_W(FLIT_W), .VC_W(VC_W)) u_south (
        .inject_o(south_i_link), .eject_i(south_o_link),
        .in_valid_i(local_in_valid_i[1]), .in_ready_o(local_in_ready_o[1]),
        .in_flit_i(local_in_flit_i[1*FLIT_W +: FLIT_W]),
        .in_vc_i(local_in_vc_i[1*VC_W +: VC_W]),
        .out_valid_o(local_out_valid_o[1]), .out_ready_i(local_out_ready_i[1]),
        .out_flit_o(local_out_flit_o[1*FLIT_W +: FLIT_W]),
        .out_vc_o(local_out_vc_o[1*VC_W +: VC_W])
      );
      noc_endpoint_link_adapter #(.FLIT_W(FLIT_W), .VC_W(VC_W)) u_east (
        .inject_o(east_i_link), .eject_i(east_o_link),
        .in_valid_i(local_in_valid_i[2]), .in_ready_o(local_in_ready_o[2]),
        .in_flit_i(local_in_flit_i[2*FLIT_W +: FLIT_W]),
        .in_vc_i(local_in_vc_i[2*VC_W +: VC_W]),
        .out_valid_o(local_out_valid_o[2]), .out_ready_i(local_out_ready_i[2]),
        .out_flit_o(local_out_flit_o[2*FLIT_W +: FLIT_W]),
        .out_vc_o(local_out_vc_o[2*VC_W +: VC_W])
      );
      noc_endpoint_link_adapter #(.FLIT_W(FLIT_W), .VC_W(VC_W)) u_west (
        .inject_o(west_i_link), .eject_i(west_o_link),
        .in_valid_i(local_in_valid_i[3]), .in_ready_o(local_in_ready_o[3]),
        .in_flit_i(local_in_flit_i[3*FLIT_W +: FLIT_W]),
        .in_vc_i(local_in_vc_i[3*VC_W +: VC_W]),
        .out_valid_o(local_out_valid_o[3]), .out_ready_i(local_out_ready_i[3]),
        .out_flit_o(local_out_flit_o[3*FLIT_W +: FLIT_W]),
        .out_vc_o(local_out_vc_o[3*VC_W +: VC_W])
      );
      noc_endpoint_link_adapter #(.FLIT_W(FLIT_W), .VC_W(VC_W)) u_local (
        .inject_o(local_i_link), .eject_i(local_o_link),
        .in_valid_i(local_in_valid_i[4]), .in_ready_o(local_in_ready_o[4]),
        .in_flit_i(local_in_flit_i[4*FLIT_W +: FLIT_W]),
        .in_vc_i(local_in_vc_i[4*VC_W +: VC_W]),
        .out_valid_o(local_out_valid_o[4]), .out_ready_i(local_out_ready_i[4]),
        .out_flit_o(local_out_flit_o[4*FLIT_W +: FLIT_W]),
        .out_vc_o(local_out_vc_o[4*VC_W +: VC_W])
      );

      assign local_in_ready_o[NUM_NODES-1:NUM_PORTS] = 0;
      assign local_out_valid_o[NUM_NODES-1:NUM_PORTS] = 0;
      assign local_out_flit_o[NUM_NODES*FLIT_W-1:NUM_PORTS*FLIT_W] = 0;
      assign local_out_vc_o[NUM_NODES*VC_W-1:NUM_PORTS*VC_W] = 0;

      router #(
        .X_COORD(X_COORD), .Y_COORD(Y_COORD), .FLIT_W(FLIT_W), .VC_W(VC_W),
        .FIFO_D(FIFO_D), .COUNTER_W(COUNTER_W)
      ) u_router (
        .clk, .rst_n,
        .north_i(north_i_link), .north_o(north_o_link),
        .south_i(south_i_link), .south_o(south_o_link),
        .east_i(east_i_link), .east_o(east_o_link),
        .west_i(west_i_link), .west_o(west_o_link),
        .local_i(local_i_link), .local_o(local_o_link),
        .protocol_error_o(unused_protocol_error),
        .flits_received_o(unused_flits_received),
        .flits_sent_o(unused_flits_sent),
        .blocked_empty_o(unused_blocked_empty),
        .blocked_backpressure_o(unused_blocked_backpressure),
        .packets_ejected_o(unused_packets_ejected)
      );
    end else begin : gen_torus
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) local_i [NUM_NODES]();
      noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) local_o [NUM_NODES]();
      logic [NUM_NODES*NUM_PORTS*NUM_VCS-1:0] unused_protocol_error;
      logic [NUM_NODES*NUM_PORTS*COUNTER_W-1:0] unused_flits_received;
      logic [NUM_NODES*NUM_PORTS*COUNTER_W-1:0] unused_flits_sent;
      logic [NUM_NODES*NUM_PORTS*COUNTER_W-1:0] unused_blocked_empty;
      logic [NUM_NODES*NUM_PORTS*COUNTER_W-1:0] unused_blocked_backpressure;
      logic [NUM_NODES*COUNTER_W-1:0] unused_packets_ejected;

      for (genvar node = 0; node < NUM_NODES; node++) begin : gen_endpoint
        noc_endpoint_link_adapter #(.FLIT_W(FLIT_W), .VC_W(VC_W)) u_endpoint (
          .inject_o(local_i[node]), .eject_i(local_o[node]),
          .in_valid_i(local_in_valid_i[node]), .in_ready_o(local_in_ready_o[node]),
          .in_flit_i(local_in_flit_i[node*FLIT_W +: FLIT_W]),
          .in_vc_i(local_in_vc_i[node*VC_W +: VC_W]),
          .out_valid_o(local_out_valid_o[node]),
          .out_ready_i(local_out_ready_i[node]),
          .out_flit_o(local_out_flit_o[node*FLIT_W +: FLIT_W]),
          .out_vc_o(local_out_vc_o[node*VC_W +: VC_W])
        );
      end

      torus4x4 #(
        .FLIT_W(FLIT_W), .VC_W(VC_W), .FIFO_D(FIFO_D),
        .COUNTER_W(COUNTER_W)
      ) u_torus (
        .clk, .rst_n, .local_i, .local_o,
        .protocol_error_o(unused_protocol_error),
        .flits_received_o(unused_flits_received),
        .flits_sent_o(unused_flits_sent),
        .blocked_empty_o(unused_blocked_empty),
        .blocked_backpressure_o(unused_blocked_backpressure),
        .packets_ejected_o(unused_packets_ejected)
      );
    end
  endgenerate

  initial begin
    if ((TARGET != 0) && (TARGET != 1)) begin
      $fatal(1, "noc_interface_smoke_top TARGET must be 0 or 1");
    end
  end
endmodule

module noc_endpoint_link_adapter #(
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VC_W = noc_pkg::NOC_VC_W
) (
  noc_link_if.source inject_o,
  noc_link_if.sink   eject_i,
  input  logic              in_valid_i,
  output logic              in_ready_o,
  input  logic [FLIT_W-1:0] in_flit_i,
  input  logic [VC_W-1:0]   in_vc_i,
  output logic              out_valid_o,
  input  logic              out_ready_i,
  output logic [FLIT_W-1:0] out_flit_o,
  output logic [VC_W-1:0]   out_vc_o
);
  assign inject_o.valid = in_valid_i;
  assign inject_o.flit = in_flit_i;
  assign inject_o.vc_id = in_vc_i;
  assign in_ready_o = inject_o.ready;

  assign out_valid_o = eject_i.valid;
  assign out_flit_o = eject_i.flit;
  assign out_vc_o = eject_i.vc_id;
  assign eject_i.ready = out_ready_i;
endmodule
