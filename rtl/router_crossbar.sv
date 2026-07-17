import noc_pkg::*;

module router_crossbar #(
  parameter int NUM_PORTS = noc_pkg::NOC_NUM_PORTS,
  parameter int FLIT_W    = noc_pkg::NOC_FLIT_W,
  parameter int VC_W      = noc_pkg::NOC_VC_W
) (
  input  logic [NUM_PORTS-1:0]             in_valid_i,
  output logic [NUM_PORTS-1:0]             in_ready_o,
  input  logic [FLIT_W-1:0]                in_flit_i [NUM_PORTS],
  input  logic [VC_W-1:0]                  in_vc_i [NUM_PORTS],
  input  noc_pkg::port_id_e                select_i [NUM_PORTS],
  output logic [NUM_PORTS-1:0]             out_valid_o,
  input  logic [NUM_PORTS-1:0]             out_ready_i,
  output logic [FLIT_W-1:0]                out_flit_o [NUM_PORTS],
  output logic [VC_W-1:0]                  out_vc_o [NUM_PORTS]
);
  always_comb begin
    in_ready_o = '0;
    out_valid_o = '0;

    for (int out_port = 0; out_port < NUM_PORTS; out_port++) begin
      out_flit_o[out_port] = '0;
      out_vc_o[out_port] = '0;
    end

    for (int in_port = 0; in_port < NUM_PORTS; in_port++) begin
      automatic int out_idx = int'(select_i[in_port]);
      if (in_valid_i[in_port] && (out_idx < NUM_PORTS) && !out_valid_o[out_idx]) begin
        out_valid_o[out_idx] = 1'b1;
        out_flit_o[out_idx] = in_flit_i[in_port];
        out_vc_o[out_idx] = in_vc_i[in_port];
        in_ready_o[in_port] = out_ready_i[out_idx];
      end
    end
  end

  // TODO: replace first-wins behavior with per-output round-robin arbitration.
endmodule
