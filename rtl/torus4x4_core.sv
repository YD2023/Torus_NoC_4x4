import noc_pkg::*;

module torus4x4_core #(
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VC_W      = noc_pkg::NOC_VC_W,
  parameter int FIFO_D    = 4,
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
  output logic [noc_pkg::NOC_NUM_NODES*VC_W-1:0]   local_out_vc_o,
  output logic [noc_pkg::NOC_NUM_NODES*noc_pkg::NOC_NUM_PORTS*
                noc_pkg::NOC_NUM_VCS-1:0] protocol_error_o,
  output logic [noc_pkg::NOC_NUM_NODES*noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0]
      flits_received_o,
  output logic [noc_pkg::NOC_NUM_NODES*noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0]
      flits_sent_o,
  output logic [noc_pkg::NOC_NUM_NODES*noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0]
      blocked_empty_o,
  output logic [noc_pkg::NOC_NUM_NODES*noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0]
      blocked_backpressure_o,
  output logic [noc_pkg::NOC_NUM_NODES*COUNTER_W-1:0] packets_ejected_o
);
  localparam int NUM_NODES = noc_pkg::NOC_NUM_NODES;
  localparam int NUM_PORTS = noc_pkg::NOC_NUM_PORTS;
  localparam int NUM_VCS = noc_pkg::NOC_NUM_VCS;

  wire [NUM_PORTS-1:0]        node_in_valid [NUM_NODES];
  wire [NUM_PORTS-1:0]        node_in_ready [NUM_NODES];
  wire [NUM_PORTS*FLIT_W-1:0] node_in_flit [NUM_NODES];
  wire [NUM_PORTS*VC_W-1:0]   node_in_vc [NUM_NODES];
  wire [NUM_PORTS*NUM_VCS-1:0] node_in_vc_ready [NUM_NODES];
  wire [NUM_PORTS-1:0]        node_out_valid [NUM_NODES];
  wire [NUM_PORTS-1:0]        node_out_ready [NUM_NODES];
  wire [NUM_PORTS*FLIT_W-1:0] node_out_flit [NUM_NODES];
  wire [NUM_PORTS*VC_W-1:0]   node_out_vc [NUM_NODES];
  wire [NUM_PORTS*NUM_VCS-1:0] node_out_vc_ready [NUM_NODES];
  wire [NUM_PORTS*NUM_VCS-1:0] node_protocol_error [NUM_NODES];
  wire [NUM_PORTS*COUNTER_W-1:0] node_flits_received [NUM_NODES];
  wire [NUM_PORTS*COUNTER_W-1:0] node_flits_sent [NUM_NODES];
  wire [NUM_PORTS*COUNTER_W-1:0] node_blocked_empty [NUM_NODES];
  wire [NUM_PORTS*COUNTER_W-1:0] node_blocked_backpressure [NUM_NODES];
  wire [COUNTER_W-1:0] node_packets_ejected [NUM_NODES];

  for (genvar x = 0; x < noc_pkg::NOC_X_DIM; x++) begin : gen_x
    for (genvar y = 0; y < noc_pkg::NOC_Y_DIM; y++) begin : gen_y
      localparam int EAST_X   = (x + 1) % noc_pkg::NOC_X_DIM;
      localparam int WEST_X   = (x + noc_pkg::NOC_X_DIM - 1) % noc_pkg::NOC_X_DIM;
      localparam int SOUTH_Y  = (y + 1) % noc_pkg::NOC_Y_DIM;
      localparam int NORTH_Y  = (y + noc_pkg::NOC_Y_DIM - 1) % noc_pkg::NOC_Y_DIM;
      localparam int NODE_IDX = (x * noc_pkg::NOC_Y_DIM) + y;
      localparam int EAST_IDX = (EAST_X * noc_pkg::NOC_Y_DIM) + y;
      localparam int WEST_IDX = (WEST_X * noc_pkg::NOC_Y_DIM) + y;
      localparam int SOUTH_IDX = (x * noc_pkg::NOC_Y_DIM) + SOUTH_Y;
      localparam int NORTH_IDX = (x * noc_pkg::NOC_Y_DIM) + NORTH_Y;

      assign node_in_valid[NODE_IDX][noc_pkg::PORT_NORTH] =
          node_out_valid[NORTH_IDX][noc_pkg::PORT_SOUTH];
      assign node_in_flit[NODE_IDX][noc_pkg::PORT_NORTH*FLIT_W +: FLIT_W] =
          node_out_flit[NORTH_IDX][noc_pkg::PORT_SOUTH*FLIT_W +: FLIT_W];
      assign node_in_vc[NODE_IDX][noc_pkg::PORT_NORTH*VC_W +: VC_W] =
          node_out_vc[NORTH_IDX][noc_pkg::PORT_SOUTH*VC_W +: VC_W];

      assign node_in_valid[NODE_IDX][noc_pkg::PORT_SOUTH] =
          node_out_valid[SOUTH_IDX][noc_pkg::PORT_NORTH];
      assign node_in_flit[NODE_IDX][noc_pkg::PORT_SOUTH*FLIT_W +: FLIT_W] =
          node_out_flit[SOUTH_IDX][noc_pkg::PORT_NORTH*FLIT_W +: FLIT_W];
      assign node_in_vc[NODE_IDX][noc_pkg::PORT_SOUTH*VC_W +: VC_W] =
          node_out_vc[SOUTH_IDX][noc_pkg::PORT_NORTH*VC_W +: VC_W];

      assign node_in_valid[NODE_IDX][noc_pkg::PORT_EAST] =
          node_out_valid[EAST_IDX][noc_pkg::PORT_WEST];
      assign node_in_flit[NODE_IDX][noc_pkg::PORT_EAST*FLIT_W +: FLIT_W] =
          node_out_flit[EAST_IDX][noc_pkg::PORT_WEST*FLIT_W +: FLIT_W];
      assign node_in_vc[NODE_IDX][noc_pkg::PORT_EAST*VC_W +: VC_W] =
          node_out_vc[EAST_IDX][noc_pkg::PORT_WEST*VC_W +: VC_W];

      assign node_in_valid[NODE_IDX][noc_pkg::PORT_WEST] =
          node_out_valid[WEST_IDX][noc_pkg::PORT_EAST];
      assign node_in_flit[NODE_IDX][noc_pkg::PORT_WEST*FLIT_W +: FLIT_W] =
          node_out_flit[WEST_IDX][noc_pkg::PORT_EAST*FLIT_W +: FLIT_W];
      assign node_in_vc[NODE_IDX][noc_pkg::PORT_WEST*VC_W +: VC_W] =
          node_out_vc[WEST_IDX][noc_pkg::PORT_EAST*VC_W +: VC_W];

      assign node_in_valid[NODE_IDX][noc_pkg::PORT_LOCAL] = local_in_valid_i[NODE_IDX];
      assign node_in_flit[NODE_IDX][noc_pkg::PORT_LOCAL*FLIT_W +: FLIT_W] =
          local_in_flit_i[NODE_IDX*FLIT_W +: FLIT_W];
      assign node_in_vc[NODE_IDX][noc_pkg::PORT_LOCAL*VC_W +: VC_W] =
          local_in_vc_i[NODE_IDX*VC_W +: VC_W];
      assign local_in_ready_o[NODE_IDX] = node_in_ready[NODE_IDX][noc_pkg::PORT_LOCAL];

      assign node_out_vc_ready[NODE_IDX][noc_pkg::PORT_NORTH*NUM_VCS +: NUM_VCS] =
          node_in_vc_ready[NORTH_IDX][noc_pkg::PORT_SOUTH*NUM_VCS +: NUM_VCS];
      assign node_out_vc_ready[NODE_IDX][noc_pkg::PORT_SOUTH*NUM_VCS +: NUM_VCS] =
          node_in_vc_ready[SOUTH_IDX][noc_pkg::PORT_NORTH*NUM_VCS +: NUM_VCS];
      assign node_out_vc_ready[NODE_IDX][noc_pkg::PORT_EAST*NUM_VCS +: NUM_VCS] =
          node_in_vc_ready[EAST_IDX][noc_pkg::PORT_WEST*NUM_VCS +: NUM_VCS];
      assign node_out_vc_ready[NODE_IDX][noc_pkg::PORT_WEST*NUM_VCS +: NUM_VCS] =
          node_in_vc_ready[WEST_IDX][noc_pkg::PORT_EAST*NUM_VCS +: NUM_VCS];
      assign node_out_vc_ready[NODE_IDX][noc_pkg::PORT_LOCAL*NUM_VCS +: NUM_VCS] =
          {NUM_VCS{local_out_ready_i[NODE_IDX]}};

      assign node_out_ready[NODE_IDX][noc_pkg::PORT_NORTH] =
          node_in_ready[NORTH_IDX][noc_pkg::PORT_SOUTH];
      assign node_out_ready[NODE_IDX][noc_pkg::PORT_SOUTH] =
          node_in_ready[SOUTH_IDX][noc_pkg::PORT_NORTH];
      assign node_out_ready[NODE_IDX][noc_pkg::PORT_EAST] =
          node_in_ready[EAST_IDX][noc_pkg::PORT_WEST];
      assign node_out_ready[NODE_IDX][noc_pkg::PORT_WEST] =
          node_in_ready[WEST_IDX][noc_pkg::PORT_EAST];
      assign node_out_ready[NODE_IDX][noc_pkg::PORT_LOCAL] =
          local_out_ready_i[NODE_IDX];

      assign local_out_valid_o[NODE_IDX] = node_out_valid[NODE_IDX][noc_pkg::PORT_LOCAL];
      assign local_out_flit_o[NODE_IDX*FLIT_W +: FLIT_W] =
          node_out_flit[NODE_IDX][noc_pkg::PORT_LOCAL*FLIT_W +: FLIT_W];
      assign local_out_vc_o[NODE_IDX*VC_W +: VC_W] =
          node_out_vc[NODE_IDX][noc_pkg::PORT_LOCAL*VC_W +: VC_W];

      assign protocol_error_o[NODE_IDX*NUM_PORTS*NUM_VCS +:
                              NUM_PORTS*NUM_VCS] =
          node_protocol_error[NODE_IDX];

      assign flits_received_o[NODE_IDX*NUM_PORTS*COUNTER_W +:
                              NUM_PORTS*COUNTER_W] =
          node_flits_received[NODE_IDX];
      assign flits_sent_o[NODE_IDX*NUM_PORTS*COUNTER_W +:
                          NUM_PORTS*COUNTER_W] = node_flits_sent[NODE_IDX];
      assign blocked_empty_o[NODE_IDX*NUM_PORTS*COUNTER_W +:
                             NUM_PORTS*COUNTER_W] =
          node_blocked_empty[NODE_IDX];
      assign blocked_backpressure_o[NODE_IDX*NUM_PORTS*COUNTER_W +:
                                    NUM_PORTS*COUNTER_W] =
          node_blocked_backpressure[NODE_IDX];
      assign packets_ejected_o[NODE_IDX*COUNTER_W +: COUNTER_W] =
          node_packets_ejected[NODE_IDX];

      router_core #(
        .X_COORD(x),
        .Y_COORD(y),
        .FLIT_W(FLIT_W),
        .VC_W(VC_W),
        .FIFO_D(FIFO_D),
        .COUNTER_W(COUNTER_W),
        .VC_AWARE_FLOW(1'b1)
      ) u_router_core (
        .clk,
        .rst_n,
        .in_valid_i(node_in_valid[NODE_IDX]),
        .in_ready_o(node_in_ready[NODE_IDX]),
        .in_flit_i(node_in_flit[NODE_IDX]),
        .in_vc_i(node_in_vc[NODE_IDX]),
        .in_vc_ready_o(node_in_vc_ready[NODE_IDX]),
        .out_valid_o(node_out_valid[NODE_IDX]),
        .out_ready_i(node_out_ready[NODE_IDX]),
        .out_vc_ready_i(node_out_vc_ready[NODE_IDX]),
        .out_flit_o(node_out_flit[NODE_IDX]),
        .out_vc_o(node_out_vc[NODE_IDX]),
        .protocol_error_o(node_protocol_error[NODE_IDX]),
        .flits_received_o(node_flits_received[NODE_IDX]),
        .flits_sent_o(node_flits_sent[NODE_IDX]),
        .blocked_empty_o(node_blocked_empty[NODE_IDX]),
        .blocked_backpressure_o(node_blocked_backpressure[NODE_IDX]),
        .packets_ejected_o(node_packets_ejected[NODE_IDX])
      );
    end
  end

  initial begin
    if (FLIT_W != noc_pkg::NOC_FLIT_W) begin
      $fatal(1, "torus4x4_core FLIT_W must match the MVP flit format");
    end
    if (VC_W != noc_pkg::NOC_VC_W) begin
      $fatal(1, "torus4x4_core VC_W must match the MVP VC format");
    end
    if (FIFO_D <= 0) begin
      $fatal(1, "torus4x4_core FIFO_D must be greater than zero");
    end
    if (COUNTER_W <= 0) begin
      $fatal(1, "torus4x4_core COUNTER_W must be greater than zero");
    end
  end
endmodule
