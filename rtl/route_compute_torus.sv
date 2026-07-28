import noc_pkg::*;

module route_compute_torus #(
  parameter int X_DIM   = noc_pkg::NOC_X_DIM,
  parameter int Y_DIM   = noc_pkg::NOC_Y_DIM,
  parameter int COORD_W = noc_pkg::NOC_COORD_W,
  parameter int VC_W    = noc_pkg::NOC_VC_W
) (
  input  logic [COORD_W-1:0] cur_x_i,
  input  logic [COORD_W-1:0] cur_y_i,
  input  logic [COORD_W-1:0] dst_x_i,
  input  logic [COORD_W-1:0] dst_y_i,
  input  logic [VC_W-1:0]    vc_i,
  output noc_pkg::port_id_e  route_o,
  output logic [VC_W-1:0]    vc_o,
  output logic               dateline_cross_o
);
  int unsigned dx_pos;
  int unsigned dx_neg;
  int unsigned dy_pos;
  int unsigned dy_neg;

  always_comb begin
    dx_pos = (int'(dst_x_i) + X_DIM - int'(cur_x_i)) % X_DIM;
    dx_neg = (int'(cur_x_i) + X_DIM - int'(dst_x_i)) % X_DIM;
    dy_pos = (int'(dst_y_i) + Y_DIM - int'(cur_y_i)) % Y_DIM;
    dy_neg = (int'(cur_y_i) + Y_DIM - int'(dst_y_i)) % Y_DIM;

    route_o = noc_pkg::PORT_LOCAL;

    if (cur_x_i != dst_x_i) begin
      if (dx_pos <= dx_neg) begin
        route_o = noc_pkg::PORT_EAST;
      end else begin
        route_o = noc_pkg::PORT_WEST;
      end
    end else if (cur_y_i != dst_y_i) begin
      if (dy_pos <= dy_neg) begin
        route_o = noc_pkg::PORT_SOUTH;
      end else begin
        route_o = noc_pkg::PORT_NORTH;
      end
    end

    dateline_cross_o = 1'b0;
    if ((route_o == noc_pkg::PORT_EAST)  && (int'(cur_x_i) == X_DIM - 1)) dateline_cross_o = 1'b1;
    if ((route_o == noc_pkg::PORT_WEST)  && (int'(cur_x_i) == 0))         dateline_cross_o = 1'b1;
    if ((route_o == noc_pkg::PORT_SOUTH) && (int'(cur_y_i) == Y_DIM - 1)) dateline_cross_o = 1'b1;
    if ((route_o == noc_pkg::PORT_NORTH) && (int'(cur_y_i) == 0))         dateline_cross_o = 1'b1;

    vc_o = vc_i;
    if (dateline_cross_o) begin
      vc_o = {{(VC_W-1){1'b0}}, 1'b1};
    end
  end

  initial begin
    if ((X_DIM <= 0) || (Y_DIM <= 0)) begin
      $fatal(1, "route_compute_torus dimensions must be greater than zero");
    end
    if ((COORD_W <= 0) || ((1 << COORD_W) < X_DIM) ||
        ((1 << COORD_W) < Y_DIM)) begin
      $fatal(1, "route_compute_torus COORD_W cannot encode all coordinates");
    end
    if (VC_W != 1) begin
      $fatal(1, "route_compute_torus MVP requires VC_W=1");
    end
  end
endmodule
