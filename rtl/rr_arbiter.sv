import noc_pkg::*;

module rr_arbiter #(
  parameter int NUM_REQ = 10,
  localparam int REQ_W = (NUM_REQ <= 1) ? 1 : $clog2(NUM_REQ)
) (
  input  logic               clk,
  input  logic               rst_n,
  input  logic [NUM_REQ-1:0] req_i,
  input  logic               advance_i,
  output logic [NUM_REQ-1:0] grant_o,
  output logic               grant_valid_o,
  output logic [REQ_W-1:0]   grant_idx_o
);
  logic [REQ_W-1:0] rr_ptr_q;

  function automatic logic [REQ_W-1:0] idx_to_vec(input int unsigned idx);
    idx_to_vec = idx[REQ_W-1:0];
  endfunction

  function automatic logic [REQ_W-1:0] next_idx(input logic [REQ_W-1:0] idx);
    if (int'(idx) == (NUM_REQ - 1)) begin
      next_idx = '0;
    end else begin
      next_idx = idx + {{(REQ_W-1){1'b0}}, 1'b1};
    end
  endfunction

  always_comb begin
    grant_o = '0;
    grant_valid_o = 1'b0;
    grant_idx_o = '0;

    for (int offset = 0; offset < NUM_REQ; offset++) begin
      automatic int unsigned idx = (int'(rr_ptr_q) + offset) % NUM_REQ;
      if (!grant_valid_o && req_i[idx]) begin
        grant_o[idx] = 1'b1;
        grant_valid_o = 1'b1;
        grant_idx_o = idx_to_vec(idx);
      end
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rr_ptr_q <= '0;
    end else if (advance_i && grant_valid_o) begin
      rr_ptr_q <= next_idx(grant_idx_o);
    end
  end

  initial begin
    if (NUM_REQ <= 0) begin
      $error("rr_arbiter NUM_REQ must be greater than zero");
    end
  end
endmodule
