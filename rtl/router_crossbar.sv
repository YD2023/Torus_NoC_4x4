import noc_pkg::*;

module router_crossbar #(
  parameter int NUM_PORTS = noc_pkg::NOC_NUM_PORTS,
  parameter int NUM_REQ   = NUM_PORTS * noc_pkg::NOC_NUM_VCS,
  parameter int FLIT_W    = noc_pkg::NOC_FLIT_W,
  parameter int VC_W      = noc_pkg::NOC_VC_W,
  parameter int PORT_W    = 3,
  parameter bit VC_AWARE_FLOW = 1'b0
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic [NUM_REQ-1:0]           in_valid_i,
  output logic [NUM_REQ-1:0]           in_ready_o,
  output logic [NUM_REQ-1:0]           in_grant_o,
  output logic [NUM_REQ-1:0]           in_stalled_o,
  input  logic [NUM_REQ*FLIT_W-1:0]    in_flit_i,
  input  logic [NUM_REQ*VC_W-1:0]      in_vc_i,
  input  logic [NUM_REQ*PORT_W-1:0]    in_route_i,
  output logic [NUM_PORTS-1:0]         out_valid_o,
  input  logic [NUM_PORTS-1:0]         out_ready_i,
  input  logic [NUM_PORTS*(1 << VC_W)-1:0] out_vc_ready_i,
  output logic [NUM_PORTS-1:0]         out_transfer_o,
  output logic [NUM_PORTS*FLIT_W-1:0]  out_flit_o,
  output logic [NUM_PORTS*VC_W-1:0]    out_vc_o
);
  localparam int REQ_W = (NUM_REQ <= 1) ? 1 : $clog2(NUM_REQ);
  localparam int NUM_VCS = 1 << VC_W;

  logic [NUM_REQ-1:0]           request_by_output [NUM_PORTS];
  logic [NUM_REQ-1:0]           ready_request_by_output [NUM_PORTS];
  logic [NUM_REQ-1:0]           arbiter_request_by_output [NUM_PORTS];
  logic [NUM_REQ-1:0]           grant_by_output [NUM_PORTS];
  logic [NUM_PORTS-1:0]         grant_valid;
  logic [NUM_PORTS-1:0]         selected_ready;

  logic [REQ_W-1:0]            grant_idx_by_output [NUM_PORTS];
  logic [NUM_PORTS*NUM_VCS-1:0] locked_valid_q;
  logic [REQ_W-1:0]             locked_idx_q [NUM_PORTS*NUM_VCS];
  logic [NUM_PORTS-1:0]         stalled_valid_q;
  logic [REQ_W-1:0]             stalled_idx_q [NUM_PORTS];
  integer request_out_port;
  integer request_idx;
  integer select_out_port;
  integer select_idx;

`ifndef SYNTHESIS
  logic [NUM_PORTS-1:0]        protocol_hold_valid_q;
  logic [NUM_PORTS*FLIT_W-1:0] protocol_hold_flit_q;
  logic [NUM_PORTS*VC_W-1:0]   protocol_hold_vc_q;
  integer invariant_out_port;
`endif

  integer state_out_port;
  integer state_vc;
  always @(*) begin
    for (request_out_port = 0; request_out_port < NUM_PORTS;
         request_out_port = request_out_port + 1) begin
      request_by_output[request_out_port] = '0;
      ready_request_by_output[request_out_port] = '0;

      for (request_idx = 0; request_idx < NUM_REQ; request_idx = request_idx + 1) begin
        if ((!stalled_valid_q[request_out_port] ||
             (request_idx == int'(stalled_idx_q[request_out_port]))) &&
            (!locked_valid_q[request_out_port*NUM_VCS +
                 int'(in_vc_i[request_idx*VC_W +: VC_W])] ||
             (request_idx == int'(locked_idx_q[request_out_port*NUM_VCS +
                 int'(in_vc_i[request_idx*VC_W +: VC_W])]))) &&
            in_valid_i[request_idx] &&
            (int'(in_route_i[request_idx*PORT_W +: PORT_W]) == request_out_port)) begin
          request_by_output[request_out_port][request_idx] = 1'b1;
          if (out_vc_ready_i[request_out_port*NUM_VCS +
              int'(in_vc_i[request_idx*VC_W +: VC_W])]) begin
            ready_request_by_output[request_out_port][request_idx] = 1'b1;
          end
        end
      end

      if (VC_AWARE_FLOW &&
          (request_out_port != int'(noc_pkg::PORT_LOCAL))) begin
        arbiter_request_by_output[request_out_port] =
            ready_request_by_output[request_out_port];
      end else begin
        arbiter_request_by_output[request_out_port] =
            request_by_output[request_out_port];
      end
    end
  end

  for (genvar output_idx = 0; output_idx < NUM_PORTS; output_idx++) begin : gen_output_arbiter
    rr_arbiter #(
      .NUM_REQ(NUM_REQ)
    ) u_arbiter (
      .clk,
      .rst_n,
      .req_i(arbiter_request_by_output[output_idx]),
      .advance_i(out_transfer_o[output_idx]),
      .grant_o(grant_by_output[output_idx]),
      .grant_valid_o(grant_valid[output_idx]),
      .grant_idx_o(grant_idx_by_output[output_idx])
    );
  end

  assign out_valid_o = grant_valid;
  assign out_transfer_o = grant_valid & selected_ready;

  always @(*) begin
    in_ready_o = '0;
    in_grant_o = '0;
    in_stalled_o = '0;
    out_flit_o = '0;
    out_vc_o = '0;
    selected_ready = '0;

    for (select_out_port = 0; select_out_port < NUM_PORTS;
         select_out_port = select_out_port + 1) begin
      if (stalled_valid_q[select_out_port]) begin
        in_stalled_o[stalled_idx_q[select_out_port]] = 1'b1;
      end

      for (select_idx = 0; select_idx < NUM_REQ; select_idx = select_idx + 1) begin
        if (grant_by_output[select_out_port][select_idx]) begin
          out_flit_o[select_out_port*FLIT_W +: FLIT_W] =
              in_flit_i[select_idx*FLIT_W +: FLIT_W];
          out_vc_o[select_out_port*VC_W +: VC_W] =
              in_vc_i[select_idx*VC_W +: VC_W];
          in_grant_o[select_idx] = 1'b1;
          if (VC_AWARE_FLOW &&
              (select_out_port != int'(noc_pkg::PORT_LOCAL))) begin
            selected_ready[select_out_port] =
                out_vc_ready_i[select_out_port*NUM_VCS +
                    int'(in_vc_i[select_idx*VC_W +: VC_W])];
          end else begin
            selected_ready[select_out_port] = out_ready_i[select_out_port];
          end
          in_ready_o[select_idx] = selected_ready[select_out_port];
        end
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      locked_valid_q <= '0;
      stalled_valid_q <= '0;
      for (state_out_port = 0; state_out_port < NUM_PORTS;
           state_out_port = state_out_port + 1) begin
        for (state_vc = 0; state_vc < NUM_VCS; state_vc = state_vc + 1) begin
          locked_idx_q[state_out_port*NUM_VCS + state_vc] <= '0;
        end
        stalled_idx_q[state_out_port] <= '0;
      end
    end else begin
      for (state_out_port = 0; state_out_port < NUM_PORTS;
           state_out_port = state_out_port + 1) begin
        if (grant_valid[state_out_port] && !selected_ready[state_out_port]) begin
          stalled_valid_q[state_out_port] <= 1'b1;
          stalled_idx_q[state_out_port] <= grant_idx_by_output[state_out_port];
        end else if (out_transfer_o[state_out_port]) begin
          stalled_valid_q[state_out_port] <= 1'b0;
        end

        if (out_transfer_o[state_out_port]) begin
          if (!locked_valid_q[state_out_port*NUM_VCS +
                  int'(out_vc_o[state_out_port*VC_W +: VC_W])] &&
              (out_flit_o[state_out_port*FLIT_W + noc_pkg::FLIT_TYPE_LSB +: 2] ==
               noc_pkg::FLIT_HEAD)) begin
            locked_valid_q[state_out_port*NUM_VCS +
                int'(out_vc_o[state_out_port*VC_W +: VC_W])] <= 1'b1;
            locked_idx_q[state_out_port*NUM_VCS +
                int'(out_vc_o[state_out_port*VC_W +: VC_W])] <=
                grant_idx_by_output[state_out_port];
          end else if (locked_valid_q[state_out_port*NUM_VCS +
                           int'(out_vc_o[state_out_port*VC_W +: VC_W])] &&
                       (out_flit_o[state_out_port*FLIT_W + noc_pkg::FLIT_TYPE_LSB +: 2] ==
                        noc_pkg::FLIT_TAIL)) begin
            locked_valid_q[state_out_port*NUM_VCS +
                int'(out_vc_o[state_out_port*VC_W +: VC_W])] <= 1'b0;
          end
        end
      end
    end
  end
`ifndef SYNTHESIS
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      protocol_hold_valid_q <= '0;
      protocol_hold_flit_q <= '0;
      protocol_hold_vc_q <= '0;
    end else begin
      if ((in_ready_o & ~in_grant_o) != '0) begin
        $fatal(1, "router_crossbar ready asserted without a grant");
      end
      if ((in_stalled_o & ~in_valid_i) != '0) begin
        $fatal(1, "router_crossbar stalled owner is not being presented");
      end

      for (invariant_out_port = 0; invariant_out_port < NUM_PORTS;
           invariant_out_port = invariant_out_port + 1) begin
        if (protocol_hold_valid_q[invariant_out_port]) begin
          if (!out_valid_o[invariant_out_port]) begin
            $fatal(1, "router_crossbar withdrew valid while backpressured");
          end
          if (out_flit_o[invariant_out_port*FLIT_W +: FLIT_W] !=
              protocol_hold_flit_q[invariant_out_port*FLIT_W +: FLIT_W]) begin
            $fatal(1, "router_crossbar changed flit while backpressured");
          end
          if (out_vc_o[invariant_out_port*VC_W +: VC_W] !=
              protocol_hold_vc_q[invariant_out_port*VC_W +: VC_W]) begin
            $fatal(1, "router_crossbar changed VC while backpressured");
          end
        end

        protocol_hold_valid_q[invariant_out_port] <=
            out_valid_o[invariant_out_port] && !out_ready_i[invariant_out_port];
        if (out_valid_o[invariant_out_port] && !out_ready_i[invariant_out_port]) begin
          protocol_hold_flit_q[invariant_out_port*FLIT_W +: FLIT_W] <=
              out_flit_o[invariant_out_port*FLIT_W +: FLIT_W];
          protocol_hold_vc_q[invariant_out_port*VC_W +: VC_W] <=
              out_vc_o[invariant_out_port*VC_W +: VC_W];
        end
      end
    end
  end
`endif

  initial begin
    if (NUM_PORTS <= 0) begin
      $fatal(1, "router_crossbar NUM_PORTS must be greater than zero");
    end
    if (NUM_REQ <= 0) begin
      $fatal(1, "router_crossbar NUM_REQ must be greater than zero");
    end
    if (FLIT_W != noc_pkg::NOC_FLIT_W) begin
      $fatal(1, "router_crossbar FLIT_W must match the MVP flit format");
    end
    if (VC_W <= 0) begin
      $fatal(1, "router_crossbar VC_W must be greater than zero");
    end
    if ((PORT_W <= 0) || ((1 << PORT_W) < NUM_PORTS)) begin
      $fatal(1, "router_crossbar PORT_W cannot encode every output port");
    end
  end
endmodule
