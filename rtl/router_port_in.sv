import noc_pkg::*;

module router_port_in #(
  parameter int FLIT_W  = noc_pkg::NOC_FLIT_W,
  parameter int VC_W    = noc_pkg::NOC_VC_W,
  parameter int FIFO_D  = 4,
  parameter int COORD_W = noc_pkg::NOC_COORD_W
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic [COORD_W-1:0]           cur_x_i,
  input  logic [COORD_W-1:0]           cur_y_i,
  noc_link_if.sink                     link_i,
  input  logic [noc_pkg::NOC_NUM_VCS-1:0] pop_vc_i,
  output logic [noc_pkg::NOC_NUM_VCS-1:0] vc_valid_o,
  output logic [FLIT_W-1:0]            vc_flit_o [noc_pkg::NOC_NUM_VCS],
  output noc_pkg::port_id_e            vc_route_o [noc_pkg::NOC_NUM_VCS],
  output logic [VC_W-1:0]              vc_next_o [noc_pkg::NOC_NUM_VCS]
);
  logic [noc_pkg::NOC_NUM_VCS-1:0] vc_full;
  logic [noc_pkg::NOC_NUM_VCS-1:0] vc_empty;
  logic [VC_W-1:0] selected_vc;

  assign selected_vc = link_i.vc_id;
  assign link_i.ready = !vc_full[selected_vc];

  for (genvar vc = 0; vc < noc_pkg::NOC_NUM_VCS; vc++) begin : gen_vc_fifo
    logic [FLIT_W-1:0] fifo_data;
    logic fifo_push;

    assign fifo_push = link_i.valid && link_i.ready && (selected_vc == vc[VC_W-1:0]);
    assign vc_valid_o[vc] = !vc_empty[vc];
    assign vc_flit_o[vc] = fifo_data;

    fifo #(
      .WIDTH(FLIT_W),
      .DEPTH(FIFO_D)
    ) u_fifo (
      .clk(clk),
      .rst_n(rst_n),
      .push(fifo_push),
      .pop(pop_vc_i[vc]),
      .data_i(link_i.flit),
      .data_o(fifo_data),
      .full(vc_full[vc]),
      .empty(vc_empty[vc]),
      .count()
    );

    route_compute_torus u_route (
      .cur_x_i(cur_x_i),
      .cur_y_i(cur_y_i),
      .dst_x_i(fifo_data[noc_pkg::DST_X_MSB:noc_pkg::DST_X_LSB]),
      .dst_y_i(fifo_data[noc_pkg::DST_Y_MSB:noc_pkg::DST_Y_LSB]),
      .vc_i(vc[VC_W-1:0]),
      .route_o(vc_route_o[vc]),
      .vc_o(vc_next_o[vc]),
      .dateline_cross_o()
    );
  end

  // TODO: store per-packet route state so body and tail flits inherit the head route.
endmodule
