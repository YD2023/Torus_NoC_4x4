# Project Memory: 4x4 Torus NoC RTL

## Current Goal

Build the RTL for a student-scale 4x4 bidirectional torus Network-on-Chip in SystemVerilog. Develop bottom-up with permanent cocotb tests at each component boundary before integrating the next RTL layer.

## Source of Truth

- `torus4x4_spec.md` is the current implementation specification.
- The design implementation is SystemVerilog RTL; verification uses cocotb with Verilator.
- The current skeleton should compile, but internal behavior is mostly TODO-backed stubs.

## Network Model

- Topology: 4x4 2D bidirectional torus.
- Router radix: 5 ports per router: north, south, east, west, local.
- Coordinates:
  - `x` is 0 to 3 and increases west to east.
  - `y` is 0 to 3 and increases north to south.
  - `EAST = +x`, `WEST = -x`, `SOUTH = +y`, `NORTH = -y`.
- Wrap-around links:
  - `(3,y) <-> (0,y)` for every row.
  - `(x,3) <-> (x,0)` for every column.

## Routing and VC Policy

- Routing: deterministic minimal X-then-Y torus dimension-order routing.
- Tie-break: positive direction wins equal-hop ties.
  - X tie chooses east.
  - Y tie chooses south.
- Virtual channels:
  - MVP has 2 VCs: `VC0` and `VC1`.
  - Packets start in `VC0`.
  - Dateline crossings transition monotonically to `VC1`.
  - Once a packet is in `VC1`, it remains in `VC1`.
- Dateline crossings:
  - East dateline: `(3,y) -> (0,y)`.
  - West dateline: `(0,y) -> (3,y)`.
  - South dateline: `(x,3) -> (x,0)`.
  - North dateline: `(x,0) -> (x,3)`.

## RTL Skeleton Roles

- `rtl/noc_pkg.sv`: shared constants, enums, flit type, dimensions, and helper typedefs.
- `rtl/noc_link_if.sv`: valid/ready/flit/vc internal link interface.
- `rtl/fifo.sv`: synchronous FIFO primitive.
- `rtl/rr_arbiter.sv`: round-robin arbiter primitive.
- `rtl/route_compute_torus.sv`: combinational next-hop and next-VC route computation.
- `rtl/router_port_in.sv`: per-input-port VC FIFO and packet-state block placeholder.
- `rtl/router_crossbar.sv`: 5x5 crossbar placeholder.
- `rtl/router.sv`: five-port router shell.
- `rtl/torus4x4.sv`: 16-router torus integration shell.
- `rtl/noc_files.f`: canonical RTL filelist with `noc_pkg.sv` first for tool and IDE package resolution.

## Open Decisions

- Exact flit representation in implementation: packed struct helpers versus raw field slicing.
- Router pipeline timing and arbitration state details.
- Debug counter interface shape.

## Locked Primitive Decisions

- `fifo.sv` is a synchronous FIFO with combinational head peek on `data_o`.
- FIFO has no first-word fall-through on an empty push; `data_o` is zero while empty and shows the head entry once non-empty.
- FIFO pushes are accepted only when not full; pops are accepted only when not empty.
- FIFO pointer wrap is based on `DEPTH`, not bit overflow, so non-power-of-two depths are valid.
- `rr_arbiter.sv` uses a combinational grant from the current request vector.
- The round-robin pointer advances only when `advance_i` and `grant_valid_o` are both high.

## Primitive Confidence Status

- `fifo.sv` passes its permanent self-checking cocotb test in `tb/unit/test_fifo.py` with Icarus Verilog 11.0. It covers reset, ordering, full/empty boundaries, simultaneous operations, overflow/underflow rejection, and explicit pointer wrap.
- `rr_arbiter.sv` passed a temporary Verilator C++ sanity harness under `/tmp`. Covered no-request behavior, single request, pointer hold without `advance_i`, pointer advance, one-hot grants, and wrap across 5 requesters.
- `route_compute_torus.sv` passed a temporary Verilator C++ sanity harness under `/tmp`. Covered local routing, X-before-Y routing, positive tie-breaks, east/west/north/south dateline detection, and VC0-to-VC1 monotonic transition.
- Full RTL lint passes with `verilator --lint-only --sv --top-module noc_lint_top -f rtl/noc_files.f /tmp/noc_lint_top.sv`.

## Verification Workflow

- `tb/Makefile` dispatches component tests through per-component files under `tb/config/`; generated output is isolated by component and parameter variant under `tb/sim_build/`.
- Tests are grouped by verification level under `tb/unit/`, with `tb/component/` and `tb/integration/` to be added when those levels have tests.
- Leaf RTL modules are used directly as simulation tops. SystemVerilog wrappers are reserved for interface visibility or genuine multi-module integration needs.
- Icarus Verilog 11.0 is the current cocotb simulator; Verilator 4.038 remains the lint tool because cocotb 2.0.1 requires Verilator 5.036 or newer.
- Validate in this order: FIFO, round-robin arbiter, route computation, input port, crossbar/arbitration, one router, then the complete 4x4 torus.
- Each layer must retain passing lower-level tests before it becomes a dependency of the next layer.
