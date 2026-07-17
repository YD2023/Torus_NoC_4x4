import noc_pkg::*;

module fifo #(
  parameter int WIDTH = noc_pkg::NOC_FLIT_W,
  parameter int DEPTH = 4,
  localparam int PTR_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH),
  localparam int COUNT_W = (DEPTH <= 1) ? 1 : $clog2(DEPTH + 1)
) (
  input  logic                 clk,
  input  logic                 rst_n,
  input  logic                 push,
  input  logic                 pop,
  input  logic [WIDTH-1:0]     data_i,
  output logic [WIDTH-1:0]     data_o,
  output logic                 full,
  output logic                 empty,
  output logic [COUNT_W-1:0]   count
);
  logic [WIDTH-1:0] mem [0:DEPTH-1];
  logic [PTR_W-1:0] wr_ptr;
  logic [PTR_W-1:0] rd_ptr;
  logic             push_accept;
  logic             pop_accept;

  function automatic logic [PTR_W-1:0] next_ptr(input logic [PTR_W-1:0] ptr);
    if (int'(ptr) == (DEPTH - 1)) begin
      next_ptr = '0;
    end else begin
      next_ptr = ptr + {{(PTR_W-1){1'b0}}, 1'b1};
    end
  endfunction

  assign full = (int'(count) == DEPTH);
  assign empty = (count == '0);
  assign data_o = empty ? '0 : mem[rd_ptr];
  assign push_accept = push && !full;
  assign pop_accept = pop && !empty;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr <= '0;
      rd_ptr <= '0;
      count  <= '0;
    end else begin
      if (push_accept) begin
        mem[wr_ptr] <= data_i;
        wr_ptr <= next_ptr(wr_ptr);
      end

      if (pop_accept) begin
        rd_ptr <= next_ptr(rd_ptr);
      end

      unique case ({push_accept, pop_accept})
        2'b10: count <= count + {{(COUNT_W-1){1'b0}}, 1'b1};
        2'b01: count <= count - {{(COUNT_W-1){1'b0}}, 1'b1};
        default: count <= count;
      endcase
    end
  end

  initial begin
    if (WIDTH <= 0) begin
      $error("fifo WIDTH must be greater than zero");
    end
    if (DEPTH <= 0) begin
      $error("fifo DEPTH must be greater than zero");
    end
  end
endmodule
