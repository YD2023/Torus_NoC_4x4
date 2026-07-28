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

  integer offset;
  logic [REQ_W-1:0] candidate_idx;
  function automatic logic [REQ_W-1:0] next_idx(
    input logic [REQ_W-1:0] value
  );
    if (int'(value) == (NUM_REQ - 1)) begin
      next_idx = '0;
    end else begin
      next_idx = value + {{(REQ_W-1){1'b0}}, 1'b1};
    end
  endfunction

  always @(*) begin
    grant_o = '0;
    grant_valid_o = 1'b0;
    grant_idx_o = '0;
    candidate_idx = 0;

    for (offset = 0; offset < NUM_REQ; offset = offset + 1) begin
      candidate_idx = REQ_W'((int'(rr_ptr_q) + offset) % NUM_REQ);
      if (!grant_valid_o && req_i[candidate_idx]) begin
        grant_o[candidate_idx] = 1'b1;
        grant_valid_o = 1'b1;
        grant_idx_o = candidate_idx;
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

`ifndef SYNTHESIS
  always @(posedge clk) begin
    if (rst_n) begin
      if ((grant_o & (grant_o - {{(NUM_REQ-1){1'b0}}, 1'b1})) != '0) begin
        $fatal(1, "rr_arbiter grant_o must be one-hot or zero");
      end
      if (grant_valid_o != (|grant_o)) begin
        $fatal(1, "rr_arbiter grant_valid_o must match grant_o");
      end
      if ((grant_o & ~req_i) != '0) begin
        $fatal(1, "rr_arbiter granted an inactive requester");
      end
      if (grant_valid_o && (int'(grant_idx_o) >= NUM_REQ)) begin
        $fatal(1, "rr_arbiter grant index is out of range");
      end
      if (grant_valid_o && !grant_o[grant_idx_o]) begin
        $fatal(1, "rr_arbiter grant index does not match grant vector");
      end
      if (int'(rr_ptr_q) >= NUM_REQ) begin
        $fatal(1, "rr_arbiter pointer is out of range");
      end
    end
  end
`endif

  initial begin
    if (NUM_REQ <= 0) begin
      $fatal(1, "rr_arbiter NUM_REQ must be greater than zero");
    end
  end
endmodule
