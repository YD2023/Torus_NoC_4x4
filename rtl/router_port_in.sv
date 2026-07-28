import noc_pkg::*;

module router_port_in #(
  parameter int FLIT_W  = noc_pkg::NOC_FLIT_W,
  parameter int VC_W    = noc_pkg::NOC_VC_W,
  parameter int FIFO_D  = 4,
  parameter int COORD_W = noc_pkg::NOC_COORD_W,
  parameter int INPUT_PORT = noc_pkg::PORT_LOCAL
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic [COORD_W-1:0] cur_x_i,
  input  logic [COORD_W-1:0] cur_y_i,
  input  logic               link_valid_i,
  output logic               link_ready_o,
  input  logic [FLIT_W-1:0]  link_flit_i,
  input  logic [VC_W-1:0]    link_vc_i,
  output logic [1:0]         vc_ready_o,
  input  logic [1:0]         pop_vc_i,
  output logic [1:0]         vc_valid_o,
  output logic [FLIT_W-1:0]  vc0_flit_o,
  output logic [2:0]         vc0_route_o,
  output logic [VC_W-1:0]    vc0_next_o,
  output logic [FLIT_W-1:0]  vc1_flit_o,
  output logic [2:0]         vc1_route_o,
  output logic [VC_W-1:0]    vc1_next_o,
  output logic [1:0]         protocol_error_o
);
  wire [1:0] vc_full;
  logic       vc0_push;
  logic       vc1_push;

  assign vc_ready_o = ~vc_full;
  assign link_ready_o = link_vc_i[0] ? vc_ready_o[1] : vc_ready_o[0];
  assign vc0_push = link_valid_i && link_ready_o && (link_vc_i == 1'b0);
  assign vc1_push = link_valid_i && link_ready_o && (link_vc_i == 1'b1);

  router_vc_in #(
    .FLIT_W(FLIT_W),
    .VC_W(VC_W),
    .FIFO_D(FIFO_D),
    .COORD_W(COORD_W),
    .VC_ID(0),
    .INPUT_PORT(INPUT_PORT)
  ) u_vc0 (
    .clk,
    .rst_n,
    .cur_x_i,
    .cur_y_i,
    .push_i(vc0_push),
    .pop_i(pop_vc_i[0]),
    .flit_i(link_flit_i),
    .full_o(vc_full[0]),
    .valid_o(vc_valid_o[0]),
    .flit_o(vc0_flit_o),
    .route_o(vc0_route_o),
    .next_vc_o(vc0_next_o),
    .protocol_error_o(protocol_error_o[0])
  );

  router_vc_in #(
    .FLIT_W(FLIT_W),
    .VC_W(VC_W),
    .FIFO_D(FIFO_D),
    .COORD_W(COORD_W),
    .VC_ID(1),
    .INPUT_PORT(INPUT_PORT)
  ) u_vc1 (
    .clk,
    .rst_n,
    .cur_x_i,
    .cur_y_i,
    .push_i(vc1_push),
    .pop_i(pop_vc_i[1]),
    .flit_i(link_flit_i),
    .full_o(vc_full[1]),
    .valid_o(vc_valid_o[1]),
    .flit_o(vc1_flit_o),
    .route_o(vc1_route_o),
    .next_vc_o(vc1_next_o),
    .protocol_error_o(protocol_error_o[1])
  );

  initial begin
    if (FLIT_W != noc_pkg::NOC_FLIT_W) begin
      $fatal(1, "router_port_in FLIT_W must match the MVP flit format");
    end
    if (VC_W != 1) begin
      $fatal(1, "router_port_in MVP requires VC_W=1");
    end
    if (FIFO_D <= 0) begin
      $fatal(1, "router_port_in FIFO_D must be greater than zero");
    end
    if (COORD_W != noc_pkg::NOC_COORD_W) begin
      $fatal(1, "router_port_in COORD_W must match the MVP coordinate format");
    end
    if ((INPUT_PORT < 0) || (INPUT_PORT >= noc_pkg::NOC_NUM_PORTS)) begin
      $fatal(1, "router_port_in INPUT_PORT is outside the MVP port range");
    end
  end
endmodule
