import noc_pkg::*;

module torus_local_link_adapter #(
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VC_W   = noc_pkg::NOC_VC_W
) (
  noc_link_if.sink   local_i,
  noc_link_if.source local_o,
  output logic                 local_in_valid_o,
  input  logic                 local_in_ready_i,
  output logic [FLIT_W-1:0]    local_in_flit_o,
  output logic [VC_W-1:0]      local_in_vc_o,
  input  logic                 local_out_valid_i,
  output logic                 local_out_ready_o,
  input  logic [FLIT_W-1:0]    local_out_flit_i,
  input  logic [VC_W-1:0]      local_out_vc_i
);
  assign local_in_valid_o = local_i.valid;
  assign local_in_flit_o = local_i.flit;
  assign local_in_vc_o = local_i.vc_id;
  assign local_i.ready = local_in_ready_i;

  assign local_o.valid = local_out_valid_i;
  assign local_o.flit = local_out_flit_i;
  assign local_o.vc_id = local_out_vc_i;
  assign local_out_ready_o = local_o.ready;
endmodule

module torus4x4 #(
  parameter int FLIT_W = noc_pkg::NOC_FLIT_W,
  parameter int VC_W      = noc_pkg::NOC_VC_W,
  parameter int FIFO_D    = 4,
  parameter int COUNTER_W = 32
) (
  input logic clk,
  input logic rst_n,

  noc_link_if.sink   local_i [noc_pkg::NOC_NUM_NODES],
  noc_link_if.source local_o [noc_pkg::NOC_NUM_NODES],

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

  logic [NUM_NODES-1:0]        core_local_in_valid;
  logic [NUM_NODES-1:0]        core_local_in_ready;
  logic [NUM_NODES*FLIT_W-1:0] core_local_in_flit;
  logic [NUM_NODES*VC_W-1:0]   core_local_in_vc;
  logic [NUM_NODES-1:0]        core_local_out_valid;
  logic [NUM_NODES-1:0]        core_local_out_ready;
  logic [NUM_NODES*FLIT_W-1:0] core_local_out_flit;
  logic [NUM_NODES*VC_W-1:0]   core_local_out_vc;

  for (genvar node = 0; node < NUM_NODES; node++) begin : gen_local_adapter
    torus_local_link_adapter #(
      .FLIT_W(FLIT_W),
      .VC_W(VC_W)
    ) u_adapter (
      .local_i(local_i[node]),
      .local_o(local_o[node]),
      .local_in_valid_o(core_local_in_valid[node]),
      .local_in_ready_i(core_local_in_ready[node]),
      .local_in_flit_o(core_local_in_flit[node*FLIT_W +: FLIT_W]),
      .local_in_vc_o(core_local_in_vc[node*VC_W +: VC_W]),
      .local_out_valid_i(core_local_out_valid[node]),
      .local_out_ready_o(core_local_out_ready[node]),
      .local_out_flit_i(core_local_out_flit[node*FLIT_W +: FLIT_W]),
      .local_out_vc_i(core_local_out_vc[node*VC_W +: VC_W])
    );
  end

  torus4x4_core #(
    .FLIT_W(FLIT_W),
    .VC_W(VC_W),
    .FIFO_D(FIFO_D),
    .COUNTER_W(COUNTER_W)
  ) u_core (
    .clk,
    .rst_n,
    .local_in_valid_i(core_local_in_valid),
    .local_in_ready_o(core_local_in_ready),
    .local_in_flit_i(core_local_in_flit),
    .local_in_vc_i(core_local_in_vc),
    .local_out_valid_o(core_local_out_valid),
    .local_out_ready_i(core_local_out_ready),
    .local_out_flit_o(core_local_out_flit),
    .local_out_vc_o(core_local_out_vc),
    .protocol_error_o,
    .flits_received_o,
    .flits_sent_o,
    .blocked_empty_o,
    .blocked_backpressure_o,
    .packets_ejected_o
  );
endmodule
