import noc_pkg::*;

module torus4x4 #(
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VC_W   = noc_pkg::NOC_VC_W
) (
  input logic clk,
  input logic rst_n,

  noc_link_if.sink   local_i [noc_pkg::NOC_NUM_NODES],
  noc_link_if.source local_o [noc_pkg::NOC_NUM_NODES]
);
  noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) east_west [noc_pkg::NOC_NUM_NODES] ();
  noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) west_east [noc_pkg::NOC_NUM_NODES] ();
  noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) south_north [noc_pkg::NOC_NUM_NODES] ();
  noc_link_if #(.FLIT_W(FLIT_W), .VC_W(VC_W)) north_south [noc_pkg::NOC_NUM_NODES] ();

  for (genvar x = 0; x < noc_pkg::NOC_X_DIM; x++) begin : gen_x
    for (genvar y = 0; y < noc_pkg::NOC_Y_DIM; y++) begin : gen_y
      localparam int EAST_X  = (x + 1) % noc_pkg::NOC_X_DIM;
      localparam int WEST_X  = (x + noc_pkg::NOC_X_DIM - 1) % noc_pkg::NOC_X_DIM;
      localparam int SOUTH_Y = (y + 1) % noc_pkg::NOC_Y_DIM;
      localparam int NORTH_Y = (y + noc_pkg::NOC_Y_DIM - 1) % noc_pkg::NOC_Y_DIM;
      localparam int NODE_IDX = (x * noc_pkg::NOC_Y_DIM) + y;
      localparam int EAST_IDX = (EAST_X * noc_pkg::NOC_Y_DIM) + y;
      localparam int WEST_IDX = (WEST_X * noc_pkg::NOC_Y_DIM) + y;
      localparam int SOUTH_IDX = (x * noc_pkg::NOC_Y_DIM) + SOUTH_Y;
      localparam int NORTH_IDX = (x * noc_pkg::NOC_Y_DIM) + NORTH_Y;

      router #(
        .X_COORD(x),
        .Y_COORD(y),
        .FLIT_W(FLIT_W),
        .VC_W(VC_W)
      ) u_router (
        .clk(clk),
        .rst_n(rst_n),

        .north_i(south_north[NORTH_IDX]),
        .north_o(north_south[NODE_IDX]),
        .south_i(north_south[SOUTH_IDX]),
        .south_o(south_north[NODE_IDX]),
        .east_i(west_east[EAST_IDX]),
        .east_o(east_west[NODE_IDX]),
        .west_i(east_west[WEST_IDX]),
        .west_o(west_east[NODE_IDX]),
        .local_i(local_i[NODE_IDX]),
        .local_o(local_o[NODE_IDX]),

        .flits_received_o(),
        .flits_sent_o(),
        .packets_ejected_o()
      );
    end
  end

  // TODO: expose optional network-level debug counters after router counters are finalized.
endmodule
