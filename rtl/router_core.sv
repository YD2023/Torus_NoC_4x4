import noc_pkg::*;

module router_core #(
  parameter int X_COORD = 0,
  parameter int Y_COORD = 0,
  parameter int FLIT_W  = noc_pkg::NOC_FLIT_W,
  parameter int VC_W    = noc_pkg::NOC_VC_W,
  parameter int FIFO_D    = 4,
  parameter int COORD_W  = noc_pkg::NOC_COORD_W,
  parameter int COUNTER_W = 32,
  parameter bit VC_AWARE_FLOW = 1'b0
) (
  input  logic                                      clk,
  input  logic                                      rst_n,
  input  logic [noc_pkg::NOC_NUM_PORTS-1:0]        in_valid_i,
  output logic [noc_pkg::NOC_NUM_PORTS-1:0]        in_ready_o,
  input  logic [noc_pkg::NOC_NUM_PORTS*FLIT_W-1:0] in_flit_i,
  input  logic [noc_pkg::NOC_NUM_PORTS*VC_W-1:0]   in_vc_i,
  output logic [noc_pkg::NOC_NUM_PORTS*noc_pkg::NOC_NUM_VCS-1:0]
      in_vc_ready_o,
  output logic [noc_pkg::NOC_NUM_PORTS-1:0]        out_valid_o,
  input  logic [noc_pkg::NOC_NUM_PORTS-1:0]        out_ready_i,
  input  logic [noc_pkg::NOC_NUM_PORTS*noc_pkg::NOC_NUM_VCS-1:0]
      out_vc_ready_i,
  output logic [noc_pkg::NOC_NUM_PORTS*FLIT_W-1:0] out_flit_o,
  output logic [noc_pkg::NOC_NUM_PORTS*VC_W-1:0]   out_vc_o,
  output logic [noc_pkg::NOC_NUM_PORTS*noc_pkg::NOC_NUM_VCS-1:0]
      protocol_error_o,
  output logic [noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0] flits_received_o,
  output logic [noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0] flits_sent_o,
  output logic [noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0] blocked_empty_o,
  output logic [noc_pkg::NOC_NUM_PORTS*COUNTER_W-1:0] blocked_backpressure_o,
  output logic [COUNTER_W-1:0]                         packets_ejected_o
);
  localparam int NUM_PORTS = noc_pkg::NOC_NUM_PORTS;
  localparam int NUM_VCS   = noc_pkg::NOC_NUM_VCS;
  localparam int NUM_REQ   = NUM_PORTS * NUM_VCS;
  localparam logic [COORD_W-1:0] CUR_X = X_COORD[COORD_W-1:0];
  localparam logic [COORD_W-1:0] CUR_Y = Y_COORD[COORD_W-1:0];

  function automatic logic [COUNTER_W-1:0] saturating_increment(
    input logic [COUNTER_W-1:0] value
  );
    if (&value) begin
      saturating_increment = value;
    end else begin
      saturating_increment = value + {{(COUNTER_W-1){1'b0}}, 1'b1};
    end
  endfunction

  wire [NUM_REQ-1:0]          switch_in_valid;
  wire [NUM_REQ-1:0]          switch_in_ready;
  wire [NUM_REQ-1:0]          switch_in_grant;
  wire [NUM_REQ-1:0]          switch_in_stalled;
  wire [NUM_REQ*FLIT_W-1:0]   switch_in_flit;
  wire [NUM_REQ*VC_W-1:0]     switch_in_vc;
  wire [NUM_REQ*3-1:0]        switch_in_route;
  wire [NUM_PORTS-1:0]        switch_out_valid;
  wire [NUM_PORTS-1:0]        switch_out_transfer;
  wire [NUM_PORTS*FLIT_W-1:0] switch_out_flit;
  wire [NUM_PORTS*VC_W-1:0]   switch_out_vc;

  for (genvar input_port = 0; input_port < NUM_PORTS; input_port++) begin : gen_input_port
    logic [1:0]        vc_valid;
    logic [1:0]        vc_ready;
    logic [FLIT_W-1:0] vc0_flit;
    logic [2:0]        vc0_route;
    logic [VC_W-1:0]   vc0_next;
    logic [FLIT_W-1:0] vc1_flit;
    logic [2:0]        vc1_route;
    logic [VC_W-1:0]   vc1_next;
    logic [NUM_VCS-1:0] protocol_error;
    logic [NUM_VCS-1:0] vc_rr_select;
    logic [NUM_VCS-1:0] vc_select;
    logic [NUM_VCS-1:0] vc_stalled;
    logic               vc_select_valid;
    logic               vc_selected_granted;
    logic               vc_selected_transferred;
    logic               vc_select_advance;
    logic [0:0]         unused_vc_select_idx;

    router_port_in #(
      .FLIT_W(FLIT_W),
      .VC_W(VC_W),
      .FIFO_D(FIFO_D),
      .COORD_W(COORD_W),
      .INPUT_PORT(input_port)
    ) u_input_port (
      .clk,
      .rst_n,
      .cur_x_i(CUR_X),
      .cur_y_i(CUR_Y),
      .link_valid_i(in_valid_i[input_port]),
      .link_ready_o(in_ready_o[input_port]),
      .link_flit_i(in_flit_i[input_port*FLIT_W +: FLIT_W]),
      .link_vc_i(in_vc_i[input_port*VC_W +: VC_W]),
      .vc_ready_o(vc_ready),
      .pop_vc_i(switch_in_ready[input_port*NUM_VCS +: NUM_VCS]),
      .vc_valid_o(vc_valid),
      .vc0_flit_o(vc0_flit),
      .vc0_route_o(vc0_route),
      .vc0_next_o(vc0_next),
      .vc1_flit_o(vc1_flit),
      .vc1_route_o(vc1_route),
      .vc1_next_o(vc1_next),
      .protocol_error_o(protocol_error)
    );

    rr_arbiter #(
      .NUM_REQ(NUM_VCS)
    ) u_vc_selector (
      .clk,
      .rst_n,
      .req_i(vc_valid),
      .advance_i(vc_select_advance),
      .grant_o(vc_rr_select),
      .grant_valid_o(vc_select_valid),
      .grant_idx_o(unused_vc_select_idx)
    );

    assign in_vc_ready_o[input_port*NUM_VCS +: NUM_VCS] = vc_ready;
    assign vc_stalled =
        switch_in_stalled[input_port*NUM_VCS +: NUM_VCS] & vc_valid;
    assign vc_select = (|vc_stalled) ? vc_stalled : vc_rr_select;
    assign switch_in_valid[input_port*NUM_VCS +: NUM_VCS] =
        vc_valid & vc_select;
    assign vc_selected_granted =
        |(vc_select & switch_in_grant[input_port*NUM_VCS +: NUM_VCS]);
    assign vc_selected_transferred =
        |(vc_select & switch_in_ready[input_port*NUM_VCS +: NUM_VCS]);
    assign vc_select_advance = vc_select_valid &&
        (vc_selected_transferred ||
         (!(|vc_stalled) && !vc_selected_granted));
    assign switch_in_flit[(input_port*NUM_VCS)*FLIT_W +: FLIT_W] = vc0_flit;
    assign switch_in_flit[(input_port*NUM_VCS + 1)*FLIT_W +: FLIT_W] = vc1_flit;
    assign switch_in_route[(input_port*NUM_VCS)*3 +: 3] = vc0_route;
    assign switch_in_route[(input_port*NUM_VCS + 1)*3 +: 3] = vc1_route;
    assign switch_in_vc[(input_port*NUM_VCS)*VC_W +: VC_W] = vc0_next;
    assign switch_in_vc[(input_port*NUM_VCS + 1)*VC_W +: VC_W] = vc1_next;
    assign protocol_error_o[input_port*NUM_VCS +: NUM_VCS] = protocol_error;
  end

  router_crossbar #(
    .NUM_PORTS(NUM_PORTS),
    .NUM_REQ(NUM_REQ),
    .FLIT_W(FLIT_W),
    .VC_W(VC_W),
    .PORT_W(3),
    .VC_AWARE_FLOW(VC_AWARE_FLOW)
  ) u_crossbar (
    .clk,
    .rst_n,
    .in_valid_i(switch_in_valid),
    .in_ready_o(switch_in_ready),
    .in_grant_o(switch_in_grant),
    .in_stalled_o(switch_in_stalled),
    .in_flit_i(switch_in_flit),
    .in_vc_i(switch_in_vc),
    .in_route_i(switch_in_route),
    .out_valid_o(switch_out_valid),
    .out_ready_i(out_ready_i),
    .out_vc_ready_i(out_vc_ready_i),
    .out_transfer_o(switch_out_transfer),
    .out_flit_o(switch_out_flit),
    .out_vc_o(switch_out_vc)
  );

  assign out_valid_o = switch_out_valid;
  assign out_flit_o = switch_out_flit;
  assign out_vc_o = switch_out_vc;

`ifndef SYNTHESIS
  integer invariant_input_port;
`endif

  integer counter_port;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      flits_received_o <= '0;
      flits_sent_o <= '0;
      blocked_empty_o <= '0;
      blocked_backpressure_o <= '0;
      packets_ejected_o <= '0;
    end else begin
      for (counter_port = 0; counter_port < NUM_PORTS;
           counter_port = counter_port + 1) begin
        if (in_valid_i[counter_port] && in_ready_o[counter_port]) begin
          flits_received_o[counter_port*COUNTER_W +: COUNTER_W] <=
              saturating_increment(
                  flits_received_o[counter_port*COUNTER_W +: COUNTER_W]);
        end
        if (switch_out_transfer[counter_port]) begin
          flits_sent_o[counter_port*COUNTER_W +: COUNTER_W] <=
              saturating_increment(
                  flits_sent_o[counter_port*COUNTER_W +: COUNTER_W]);
        end
        if (!(switch_in_valid[counter_port*NUM_VCS] ||
              switch_in_valid[counter_port*NUM_VCS + 1])) begin
          blocked_empty_o[counter_port*COUNTER_W +: COUNTER_W] <=
              saturating_increment(
                  blocked_empty_o[counter_port*COUNTER_W +: COUNTER_W]);
        end
        if (switch_out_valid[counter_port] && !out_ready_i[counter_port]) begin
          blocked_backpressure_o[counter_port*COUNTER_W +: COUNTER_W] <=
              saturating_increment(
                  blocked_backpressure_o[
                      counter_port*COUNTER_W +: COUNTER_W]);
        end
      end

      if (switch_out_transfer[noc_pkg::PORT_LOCAL] &&
          ((switch_out_flit[noc_pkg::PORT_LOCAL*FLIT_W + noc_pkg::FLIT_TYPE_LSB +: 2] ==
            noc_pkg::FLIT_TAIL) ||
           (switch_out_flit[noc_pkg::PORT_LOCAL*FLIT_W + noc_pkg::FLIT_TYPE_LSB +: 2] ==
            noc_pkg::FLIT_HEADTAIL))) begin
        packets_ejected_o <= saturating_increment(packets_ejected_o);
      end
    end
  end

`ifndef SYNTHESIS
  always @(posedge clk) begin
    if (rst_n) begin
      if ((switch_in_ready & ~switch_in_grant) != '0) begin
        $fatal(1, "router_core switch ready asserted without a grant");
      end
      if ((switch_in_ready & ~switch_in_valid) != '0) begin
        $fatal(1, "router_core transferred an unpresented requester");
      end

      for (invariant_input_port = 0; invariant_input_port < NUM_PORTS;
           invariant_input_port = invariant_input_port + 1) begin
        if ((switch_in_valid[invariant_input_port*NUM_VCS +: NUM_VCS] &
             (switch_in_valid[invariant_input_port*NUM_VCS +: NUM_VCS] -
              {{(NUM_VCS-1){1'b0}}, 1'b1})) != '0) begin
          $fatal(1, "router_core presented multiple VCs from one input");
        end
        if ((switch_in_grant[invariant_input_port*NUM_VCS +: NUM_VCS] &
             (switch_in_grant[invariant_input_port*NUM_VCS +: NUM_VCS] -
              {{(NUM_VCS-1){1'b0}}, 1'b1})) != '0) begin
          $fatal(1, "router_core granted multiple VCs from one input");
        end
        if ((switch_in_stalled[invariant_input_port*NUM_VCS +: NUM_VCS] &
             (switch_in_stalled[invariant_input_port*NUM_VCS +: NUM_VCS] -
              {{(NUM_VCS-1){1'b0}}, 1'b1})) != '0) begin
          $fatal(1, "router_core stalled multiple VCs from one input");
        end
      end
    end
  end
`endif

  initial begin
    if (FLIT_W != noc_pkg::NOC_FLIT_W) begin
      $fatal(1, "router_core FLIT_W must match the MVP flit format");
    end
    if (VC_W != 1 || NUM_VCS != 2) begin
      $fatal(1, "router_core MVP requires exactly two one-bit virtual channels");
    end
    if (FIFO_D <= 0) begin
      $fatal(1, "router_core FIFO_D must be greater than zero");
    end
    if (COORD_W != noc_pkg::NOC_COORD_W) begin
      $fatal(1, "router_core COORD_W must match the MVP coordinate format");
    end
    if ((X_COORD < 0) || (X_COORD >= noc_pkg::NOC_X_DIM) ||
        (Y_COORD < 0) || (Y_COORD >= noc_pkg::NOC_Y_DIM)) begin
      $fatal(1, "router_core coordinates are outside the torus dimensions");
    end
    if (COUNTER_W <= 0) begin
      $fatal(1, "router_core COUNTER_W must be greater than zero");
    end
  end
endmodule
