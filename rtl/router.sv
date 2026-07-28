import noc_pkg::*;

module router #(
  parameter int X_COORD = 0,
  parameter int Y_COORD = 0,
  parameter int FLIT_W  = noc_pkg::NOC_FLIT_W,
  parameter int VC_W      = noc_pkg::NOC_VC_W,
  parameter int FIFO_D    = 4,
  parameter int COUNTER_W = 32
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

  output logic [noc_pkg::NOC_NUM_VCS-1:0] protocol_error_o
      [noc_pkg::NOC_NUM_PORTS],
  output logic [COUNTER_W-1:0] flits_received_o [noc_pkg::NOC_NUM_PORTS],
  output logic [COUNTER_W-1:0] flits_sent_o [noc_pkg::NOC_NUM_PORTS],
  output logic [COUNTER_W-1:0] blocked_empty_o [noc_pkg::NOC_NUM_PORTS],
  output logic [COUNTER_W-1:0] blocked_backpressure_o [noc_pkg::NOC_NUM_PORTS],
  output logic [COUNTER_W-1:0] packets_ejected_o
);
  localparam int NUM_PORTS = noc_pkg::NOC_NUM_PORTS;
  localparam int NUM_VCS = noc_pkg::NOC_NUM_VCS;

  logic [NUM_PORTS-1:0]        core_in_valid;
  logic [NUM_PORTS-1:0]        core_in_ready;
  logic [NUM_PORTS*FLIT_W-1:0] core_in_flit;
  logic [NUM_PORTS*VC_W-1:0]   core_in_vc;
  logic [NUM_PORTS*NUM_VCS-1:0] core_out_vc_ready;
  logic [NUM_PORTS-1:0]        core_out_valid;
  logic [NUM_PORTS-1:0]        core_out_ready;
  logic [NUM_PORTS*FLIT_W-1:0] core_out_flit;
  logic [NUM_PORTS*VC_W-1:0]   core_out_vc;
  logic [NUM_PORTS*NUM_VCS-1:0] protocol_error_flat;
  logic [NUM_PORTS*COUNTER_W-1:0] flits_received_flat;
  logic [NUM_PORTS*COUNTER_W-1:0] flits_sent_flat;
  logic [NUM_PORTS*COUNTER_W-1:0] blocked_empty_flat;
  logic [NUM_PORTS*COUNTER_W-1:0] blocked_backpressure_flat;

  assign core_in_valid[noc_pkg::PORT_NORTH] = north_i.valid;
  assign core_in_flit[noc_pkg::PORT_NORTH*FLIT_W +: FLIT_W] = north_i.flit;
  assign core_in_vc[noc_pkg::PORT_NORTH*VC_W +: VC_W] = north_i.vc_id;
  assign north_i.ready = core_in_ready[noc_pkg::PORT_NORTH];

  assign core_in_valid[noc_pkg::PORT_SOUTH] = south_i.valid;
  assign core_in_flit[noc_pkg::PORT_SOUTH*FLIT_W +: FLIT_W] = south_i.flit;
  assign core_in_vc[noc_pkg::PORT_SOUTH*VC_W +: VC_W] = south_i.vc_id;
  assign south_i.ready = core_in_ready[noc_pkg::PORT_SOUTH];

  assign core_in_valid[noc_pkg::PORT_EAST] = east_i.valid;
  assign core_in_flit[noc_pkg::PORT_EAST*FLIT_W +: FLIT_W] = east_i.flit;
  assign core_in_vc[noc_pkg::PORT_EAST*VC_W +: VC_W] = east_i.vc_id;
  assign east_i.ready = core_in_ready[noc_pkg::PORT_EAST];

  assign core_in_valid[noc_pkg::PORT_WEST] = west_i.valid;
  assign core_in_flit[noc_pkg::PORT_WEST*FLIT_W +: FLIT_W] = west_i.flit;
  assign core_in_vc[noc_pkg::PORT_WEST*VC_W +: VC_W] = west_i.vc_id;
  assign west_i.ready = core_in_ready[noc_pkg::PORT_WEST];

  assign core_in_valid[noc_pkg::PORT_LOCAL] = local_i.valid;
  assign core_in_flit[noc_pkg::PORT_LOCAL*FLIT_W +: FLIT_W] = local_i.flit;
  assign core_in_vc[noc_pkg::PORT_LOCAL*VC_W +: VC_W] = local_i.vc_id;
  assign local_i.ready = core_in_ready[noc_pkg::PORT_LOCAL];

  assign north_o.valid = core_out_valid[noc_pkg::PORT_NORTH];
  assign north_o.flit = core_out_flit[noc_pkg::PORT_NORTH*FLIT_W +: FLIT_W];
  assign north_o.vc_id = core_out_vc[noc_pkg::PORT_NORTH*VC_W +: VC_W];
  assign core_out_ready[noc_pkg::PORT_NORTH] = north_o.ready;

  assign south_o.valid = core_out_valid[noc_pkg::PORT_SOUTH];
  assign south_o.flit = core_out_flit[noc_pkg::PORT_SOUTH*FLIT_W +: FLIT_W];
  assign south_o.vc_id = core_out_vc[noc_pkg::PORT_SOUTH*VC_W +: VC_W];
  assign core_out_ready[noc_pkg::PORT_SOUTH] = south_o.ready;

  assign east_o.valid = core_out_valid[noc_pkg::PORT_EAST];
  assign east_o.flit = core_out_flit[noc_pkg::PORT_EAST*FLIT_W +: FLIT_W];
  assign east_o.vc_id = core_out_vc[noc_pkg::PORT_EAST*VC_W +: VC_W];
  assign core_out_ready[noc_pkg::PORT_EAST] = east_o.ready;

  assign west_o.valid = core_out_valid[noc_pkg::PORT_WEST];
  assign west_o.flit = core_out_flit[noc_pkg::PORT_WEST*FLIT_W +: FLIT_W];
  assign west_o.vc_id = core_out_vc[noc_pkg::PORT_WEST*VC_W +: VC_W];
  assign core_out_ready[noc_pkg::PORT_WEST] = west_o.ready;

  assign local_o.valid = core_out_valid[noc_pkg::PORT_LOCAL];
  assign local_o.flit = core_out_flit[noc_pkg::PORT_LOCAL*FLIT_W +: FLIT_W];
  assign local_o.vc_id = core_out_vc[noc_pkg::PORT_LOCAL*VC_W +: VC_W];
  assign core_out_ready[noc_pkg::PORT_LOCAL] = local_o.ready;

  for (genvar flow_port = 0; flow_port < NUM_PORTS; flow_port++) begin : gen_flow_ready
    assign core_out_vc_ready[flow_port*NUM_VCS +: NUM_VCS] =
        {NUM_VCS{core_out_ready[flow_port]}};
  end

  router_core #(
    .X_COORD(X_COORD),
    .Y_COORD(Y_COORD),
    .FLIT_W(FLIT_W),
    .VC_W(VC_W),
    .FIFO_D(FIFO_D),
    .COUNTER_W(COUNTER_W)
  ) u_core (
    .clk,
    .rst_n,
    .in_valid_i(core_in_valid),
    .in_ready_o(core_in_ready),
    .in_flit_i(core_in_flit),
    .in_vc_i(core_in_vc),
    .in_vc_ready_o(),
    .out_valid_o(core_out_valid),
    .out_ready_i(core_out_ready),
    .out_vc_ready_i(core_out_vc_ready),
    .out_flit_o(core_out_flit),
    .out_vc_o(core_out_vc),
    .protocol_error_o(protocol_error_flat),
    .flits_received_o(flits_received_flat),
    .flits_sent_o(flits_sent_flat),
    .blocked_empty_o(blocked_empty_flat),
    .blocked_backpressure_o(blocked_backpressure_flat),
    .packets_ejected_o
  );

  for (genvar counter_port = 0; counter_port < NUM_PORTS; counter_port++) begin : gen_counters
    assign protocol_error_o[counter_port] =
        protocol_error_flat[counter_port*NUM_VCS +: NUM_VCS];
    assign flits_received_o[counter_port] =
        flits_received_flat[counter_port*COUNTER_W +: COUNTER_W];
    assign flits_sent_o[counter_port] =
        flits_sent_flat[counter_port*COUNTER_W +: COUNTER_W];
    assign blocked_empty_o[counter_port] =
        blocked_empty_flat[counter_port*COUNTER_W +: COUNTER_W];
    assign blocked_backpressure_o[counter_port] =
        blocked_backpressure_flat[counter_port*COUNTER_W +: COUNTER_W];
  end
endmodule
