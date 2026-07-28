import noc_pkg::*;

module router_vc_in #(
  parameter int FLIT_W  = noc_pkg::NOC_FLIT_W,
  parameter int VC_W    = noc_pkg::NOC_VC_W,
  parameter int FIFO_D  = 4,
  parameter int COORD_W = noc_pkg::NOC_COORD_W,
  parameter int VC_ID   = 0,
  parameter int INPUT_PORT = noc_pkg::PORT_LOCAL
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic [COORD_W-1:0] cur_x_i,
  input  logic [COORD_W-1:0] cur_y_i,
  input  logic               push_i,
  input  logic               pop_i,
  input  logic [FLIT_W-1:0]  flit_i,
  output wire                full_o,
  output logic               valid_o,
  output logic [FLIT_W-1:0]  flit_o,
  output logic [2:0]         route_o,
  output logic [VC_W-1:0]    next_vc_o,
  output logic               protocol_error_o
);
  localparam logic [VC_W-1:0] VC_VALUE = VC_ID[VC_W-1:0];
  localparam int FIFO_COUNT_W = (FIFO_D <= 1) ? 1 : $clog2(FIFO_D + 1);

  wire                empty;
  wire                fifo_full;
  logic [FLIT_W-1:0]  fifo_data;
  logic [1:0]         fifo_flit_type;
  logic               packet_active_q;
  logic [2:0]        packet_route_q;
  logic [VC_W-1:0]   packet_next_vc_q;
  logic [2:0]        head_route;
  logic [VC_W-1:0]   head_next_vc;
  logic [VC_W-1:0]   route_next_vc;
  logic              head_dateline_cross;
  logic              head_dimension_change;
  logic               ingress_packet_active_q;
  logic [noc_pkg::NOC_PKT_LEN_W-1:0] ingress_packet_length_q;
  logic [noc_pkg::NOC_PKT_LEN_W:0]   ingress_flit_count_q;
  logic [1:0]                         ingress_flit_type;
  logic [noc_pkg::NOC_PKT_LEN_W-1:0] ingress_pkt_len;
  logic [noc_pkg::NOC_PKT_LEN_W:0]   ingress_next_count;
  logic [FIFO_COUNT_W-1:0]             unused_fifo_count;

  assign full_o = fifo_full;
  assign fifo_flit_type = fifo_data[noc_pkg::FLIT_TYPE_MSB:noc_pkg::FLIT_TYPE_LSB];
  assign valid_o = !empty;
  assign flit_o = fifo_data;
  assign route_o = packet_active_q ? packet_route_q : head_route;
  assign next_vc_o = packet_active_q ? packet_next_vc_q : head_next_vc;
  assign ingress_flit_type =
      flit_i[noc_pkg::FLIT_TYPE_MSB:noc_pkg::FLIT_TYPE_LSB];
  assign ingress_pkt_len =
      flit_i[noc_pkg::PKT_LEN_MSB:noc_pkg::PKT_LEN_LSB];
  assign ingress_next_count = ingress_flit_count_q + 1'b1;
  assign head_dimension_change =
      ((INPUT_PORT == int'(noc_pkg::PORT_EAST)) ||
       (INPUT_PORT == int'(noc_pkg::PORT_WEST))) &&
      ((head_route == noc_pkg::PORT_NORTH) ||
       (head_route == noc_pkg::PORT_SOUTH));
  assign head_next_vc = (head_dimension_change && !head_dateline_cross) ?
      noc_pkg::VC0 : route_next_vc;

  fifo #(
    .WIDTH(FLIT_W),
    .DEPTH(FIFO_D)
  ) u_fifo (
    .clk,
    .rst_n,
    .push(push_i),
    .pop(pop_i),
    .data_i(flit_i),
    .data_o(fifo_data),
    .full(fifo_full),
    .empty(empty),
    .count(unused_fifo_count)
  );

  route_compute_torus #(
    .COORD_W(COORD_W),
    .VC_W(VC_W)
  ) u_route (
    .cur_x_i,
    .cur_y_i,
    .dst_x_i(fifo_data[noc_pkg::DST_X_MSB:noc_pkg::DST_X_LSB]),
    .dst_y_i(fifo_data[noc_pkg::DST_Y_MSB:noc_pkg::DST_Y_LSB]),
    .vc_i(VC_VALUE),
    .route_o(head_route),
    .vc_o(route_next_vc),
    .dateline_cross_o(head_dateline_cross)
  );

  // Validate framing when a flit enters this VC, independent of FIFO drain.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ingress_packet_active_q <= 1'b0;
      ingress_packet_length_q <= '0;
      ingress_flit_count_q <= '0;
      protocol_error_o <= 1'b0;
    end else if (push_i && !full_o) begin
      if (!ingress_packet_active_q) begin
        case (ingress_flit_type)
          noc_pkg::FLIT_HEAD: begin
            ingress_packet_active_q <= 1'b1;
            ingress_packet_length_q <= ingress_pkt_len;
            ingress_flit_count_q <= {{noc_pkg::NOC_PKT_LEN_W{1'b0}}, 1'b1};
            if (ingress_pkt_len < 2) begin
              protocol_error_o <= 1'b1;
            end
          end
          noc_pkg::FLIT_HEADTAIL: begin
            ingress_packet_active_q <= 1'b0;
            ingress_packet_length_q <= '0;
            ingress_flit_count_q <= '0;
            if (ingress_pkt_len != 1) begin
              protocol_error_o <= 1'b1;
            end
          end
          default: begin
            protocol_error_o <= 1'b1;
          end
        endcase
      end else begin
        case (ingress_flit_type)
          noc_pkg::FLIT_BODY: begin
            if (!(&ingress_flit_count_q)) begin
              ingress_flit_count_q <= ingress_next_count;
            end
            if (ingress_next_count >= {1'b0, ingress_packet_length_q}) begin
              protocol_error_o <= 1'b1;
            end
          end
          noc_pkg::FLIT_TAIL: begin
            ingress_packet_active_q <= 1'b0;
            ingress_packet_length_q <= '0;
            ingress_flit_count_q <= '0;
            if (ingress_next_count != {1'b0, ingress_packet_length_q}) begin
              protocol_error_o <= 1'b1;
            end
          end
          noc_pkg::FLIT_HEAD: begin
            protocol_error_o <= 1'b1;
            ingress_packet_active_q <= 1'b1;
            ingress_packet_length_q <= ingress_pkt_len;
            ingress_flit_count_q <= {{noc_pkg::NOC_PKT_LEN_W{1'b0}}, 1'b1};
          end
          default: begin
            protocol_error_o <= 1'b1;
            ingress_packet_active_q <= 1'b0;
            ingress_packet_length_q <= '0;
            ingress_flit_count_q <= '0;
          end
        endcase
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      packet_active_q <= 1'b0;
      packet_route_q <= noc_pkg::PORT_LOCAL;
      packet_next_vc_q <= VC_VALUE;
    end else if (pop_i && !empty) begin
      if (packet_active_q) begin
        if ((fifo_flit_type == noc_pkg::FLIT_TAIL) ||
            (fifo_flit_type == noc_pkg::FLIT_HEADTAIL)) begin
          packet_active_q <= 1'b0;
        end
      end else if (fifo_flit_type == noc_pkg::FLIT_HEAD) begin
        packet_active_q <= 1'b1;
        packet_route_q <= head_route;
        packet_next_vc_q <= head_next_vc;
      end
    end
  end

  initial begin
    if (FLIT_W != noc_pkg::NOC_FLIT_W) begin
      $fatal(1, "router_vc_in FLIT_W must match the MVP flit format");
    end
    if (VC_W != 1) begin
      $fatal(1, "router_vc_in MVP requires VC_W=1");
    end
    if (FIFO_D <= 0) begin
      $fatal(1, "router_vc_in FIFO_D must be greater than zero");
    end
    if (COORD_W != noc_pkg::NOC_COORD_W) begin
      $fatal(1, "router_vc_in COORD_W must match the MVP coordinate format");
    end
    if ((VC_ID < 0) || (VC_ID >= noc_pkg::NOC_NUM_VCS)) begin
      $fatal(1, "router_vc_in VC_ID is outside the MVP VC range");
    end
    if ((INPUT_PORT < 0) || (INPUT_PORT >= noc_pkg::NOC_NUM_PORTS)) begin
      $fatal(1, "router_vc_in INPUT_PORT is outside the MVP port range");
    end
  end
endmodule
