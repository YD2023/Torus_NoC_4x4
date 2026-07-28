# Project Memory: 4x4 Torus NoC RTL

## Current Goal

Build the RTL for a student-scale 4x4 bidirectional torus Network-on-Chip in SystemVerilog. Develop bottom-up with permanent cocotb tests at each component boundary before integrating the next RTL layer.

## Source of Truth

- `torus4x4_spec.md` is the current implementation specification.
- The design implementation is SystemVerilog RTL; cocotb currently runs on Icarus Verilog and Verilator is used for lint.
- The complete 4x4 torus datapath is implemented and verified with directed and deterministic randomized traffic, packet scoreboarding, backpressure stability checks, and a bounded no-progress watchdog.
- The scalar RTL hierarchy has reproducible compile and synthesis-path lint gates, fixed-MVP parameter contracts, and simulation-only structural invariants.

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
  - Packets start the X dimension in `VC0`.
  - A dateline crossing transitions monotonically from `VC0` to `VC1` for the remainder of that dimension.
  - At the X-to-Y DOR boundary, the two VC classes are reused: the first Y hop starts in `VC0`, unless that hop is itself a Y dateline crossing and therefore uses `VC1`.
  - There is no VC1-to-VC0 downgrade within one dimension. The only restart is the legal X-to-Y class boundary.
- Implementation clarification: the specification's global "once VC1, always VC1" wording is refined to monotonicity per dimension. Keeping X-dateline traffic in VC1 throughout Y permits a cyclic Y-channel dependency with only two VCs; independent class reuse at the DOR boundary removes that dependency.
- Dateline crossings:
  - East dateline: `(3,y) -> (0,y)`.
  - West dateline: `(0,y) -> (3,y)`.
  - South dateline: `(x,3) -> (x,0)`.
  - North dateline: `(x,0) -> (x,3)`.

## RTL Roles

- `rtl/noc_pkg.sv`: shared constants, enums, flit type, dimensions, and helper typedefs.
- `rtl/noc_link_if.sv`: valid/ready/flit/vc internal link interface.
- `rtl/fifo.sv`: synchronous FIFO primitive.
- `rtl/rr_arbiter.sv`: round-robin arbiter primitive.
- `rtl/route_compute_torus.sv`: combinational next-hop and next-VC route computation.
- `rtl/router_vc_in.sv`: one VC FIFO plus route and next-VC packet state.
- `rtl/router_port_in.sv`: two-VC ingress demultiplexing and selected-VC backpressure.
- `rtl/router_crossbar.sv`: ten-requester, five-output switch stage with per-output arbitration and per-output-VC packet ownership.
- `rtl/router_core.sv`: scalar five-port router datapath used as the component-test boundary.
- `rtl/router.sv`: standalone `noc_link_if` adapter around `router_core.sv`.
- `rtl/torus4x4_core.sv`: scalar 16-router torus datapath and wrap-around wiring used as the integration-test boundary.
- `rtl/torus4x4.sv`: `noc_link_if` local-endpoint adapter around `torus4x4_core.sv`.
- `rtl/noc_files.f`: canonical RTL filelist with `noc_pkg.sv` first for tool and IDE package resolution.

## Open Decisions

- FPGA family, part, clock constraint, and synthesis engine; no synthesis tool is currently installed, so area, frequency, and timing results remain pending.
- RTL line/toggle coverage after upgrading to a cocotb-compatible Verilator or another coverage-capable simulator.
- Optional malformed-flit quarantine or drop behavior; the current MVP detects and forwards malformed traffic.

## Locked Primitive Decisions

- `fifo.sv` is a synchronous FIFO with combinational head peek on `data_o`.
- FIFO has no first-word fall-through on an empty push; `data_o` is zero while empty and shows the head entry once non-empty.
- FIFO pushes are accepted only when not full; pops are accepted only when not empty.
- FIFO pointer wrap is based on `DEPTH`, not bit overflow, so non-power-of-two depths are valid.
- `rr_arbiter.sv` uses a combinational grant from the current request vector.
- The round-robin pointer advances only when `advance_i` and `grant_valid_o` are both high.
- Simulation-only arbiter invariants check one-hot-or-zero grants, grant-valid consistency, active-request ownership, index-vector consistency, and pointer range. They are excluded when `SYNTHESIS` is defined.

## Locked Input-Port Decisions

- The MVP input port has exactly two VCs represented by `VC_W=1`.
- `router_port_in.sv` uses explicit valid/ready/flit/vc signals; the router may connect these directly to members of its physical `noc_link_if` links.
- Each input VC is a scalar `router_vc_in.sv` instance containing one FIFO and independent packet state.
- An unclaimed HEAD or HEADTAIL route is computed combinationally while it is at the FIFO front.
- A multi-flit packet's route and outgoing VC are captured only when its HEAD is successfully popped.
- BODY and TAIL inherit the captured route and outgoing VC; successful TAIL pop releases the state.
- HEADTAIL uses its combinational route and does not leave packet state active.
- Each input instance is parameterized by its physical input port. A horizontal arrival that turns into Y restarts the VC class at the X-to-Y boundary, unless its first Y hop crosses the Y dateline.
- Each VC validates framing when a flit is accepted, independently of when that FIFO later drains. Legal framing is either `HEAD(pkt_len >= 2) -> BODY* -> TAIL` with TAIL at the declared position, or standalone `HEADTAIL(pkt_len == 1)`.
- BODY and TAIL `pkt_len` fields are ignored; the position check uses the length captured from HEAD, matching the head-only metadata policy.
- Malformed flits are still buffered and forwarded. Each VC latches a sticky `protocol_error_o` bit, reset is the only clear mechanism, and an unexpected HEAD or HEADTAIL acts as a deterministic framing resynchronization point.

## Locked Switch Decisions

- The switch has 10 requesters: two input VCs for each of five physical input ports.
- Requester ordering is `requester = input_port * 2 + vc`, using the package port order NORTH, SOUTH, EAST, WEST, LOCAL.
- Allocation is separable: one two-requester round-robin selector first chooses at most one VC per physical input, then one `rr_arbiter.sv` instance serves each physical output; unrelated outputs may transfer in parallel.
- An input selector advances after its selected VC transfers or loses output arbitration, allowing a ready sibling VC to make progress.
- A requester is ready only when it owns that output's grant and the selected downstream VC can accept it.
- Arbitration state advances only on a successful valid/ready transfer; downstream stalls preserve the current choice.
- Each output captures a visible stalled grant independently of packet ownership, so a newly arriving requester cannot replace `flit` or `vc` while `valid && !ready`.
- Registered stalled ownership is fed back to the input selector and overrides its round-robin choice until the held transfer completes. This keeps the crossbar owner and the one-VC-per-input presentation aligned through backpressure.
- Routes outside the five legal port IDs generate no request.
- A transferred HEAD acquires ownership of its `(output, outgoing VC)` for its requester until that packet's TAIL transfers.
- HEADTAIL transfers do not retain ownership; an owned packet keeps its output reserved even while its input VC is temporarily empty.
- Packet ownership prevents two packets targeting the same downstream VC class from interleaving. A packet gap on one VC does not block an eligible packet on the other VC of the same physical link.
- In torus mode, cardinal arbitration considers only requesters whose exact downstream VC FIFO reports ready. This prevents one full VC from pinning an otherwise usable physical link. Local and standalone public links retain ordinary tagged valid/ready behavior.
- Flat packed buses place requester 0 and output 0 in their least-significant slices.
- Simulation-only crossbar invariants require ready to imply grant, every stalled owner to remain presented, and `valid`, `flit`, and `vc` to remain stable throughout downstream backpressure.

## Locked Router Decisions

- `router_core.sv` owns all functional router behavior and exposes flat scalar buses for reliable Icarus/cocotb visibility.
- `router.sv` provides a standalone `noc_link_if` router boundary; `torus4x4_core.sv` instantiates `router_core.sv` directly.
- Each physical input port instantiates one `router_port_in.sv`, producing two switch requesters in `port * 2 + vc` order. A first-stage selector permits at most one of those two requesters to enter switch allocation in a cycle.
- A buffered flit pops only when its requester is granted and its selected physical output completes a valid/ready transfer.
- There is no empty-FIFO combinational bypass: ingress acceptance is Stage A and the buffered flit becomes eligible for Stage B traversal afterward.
- Crossbar outputs connect directly to the five physical egress links with the computed outgoing VC tag.
- `router_core.sv` exposes per-input-VC readiness for internal torus wiring. `router.sv` intentionally leaves that internal output open and maps each public scalar output-ready signal to both VC-ready classes.
- `flits_received_o` increments on accepted physical input handshakes.
- `flits_sent_o` increments on completed physical output handshakes.
- `packets_ejected_o` increments on a locally transferred TAIL or HEADTAIL.
- `blocked_empty_o` increments per physical input on each active cycle when both input VC FIFOs are empty. This intentionally measures idle input cycles as well as starvation.
- `blocked_backpressure_o` increments per physical output on each active cycle where `valid && !ready`.
- All observability counters use parameter `COUNTER_W`, default to 32 bits, clear only on reset, and saturate at their maximum value instead of wrapping.
- The scalar core and interface adapter both use the package port order NORTH, SOUTH, EAST, WEST, LOCAL.
- Router protocol status uses `error_index = port * NOC_NUM_VCS + vc`, producing ten sticky bits per router.
- Simulation-only router invariants enforce at most one presented, granted, or stalled VC per physical input and require every transfer-ready requester to be both valid and granted.
- MVP parameter guards reject incompatible flit, VC, coordinate, FIFO-depth, coordinate-value, and counter-width configurations at time zero. The current packed flit field map is fixed at 64 bits rather than generically relocatable.

## Locked Network Decisions

- `torus4x4_core.sv` owns all functional topology wiring; `torus4x4.sv` only adapts the 16 local interfaces.
- Node indices use `node = x * NOC_Y_DIM + y`, so node 0 is `(0,0)`, node 1 is `(0,1)`, and node 15 is `(3,3)`.
- Each north input consumes the north neighbor's south output; south consumes north, east consumes west, and west consumes east.
- Each cardinal output's two VC-ready classes are wired to the matching opposite-direction input VC FIFOs at the destination router. The public endpoint remains one tagged valid/ready link.
- Neighbor coordinates use modulo-4 arithmetic in both dimensions, including every boundary wrap link.
- Local endpoint vectors use the same node ordering, with node 0 in the least-significant scalar or packed-data slice.
- The scalar torus instantiates the already-verified `router_core.sv` directly so cocotb and production RTL share one functional hierarchy.
- A private one-link adapter is used in `torus4x4.sv` because Verilator 4.038 cannot directly select members from generated interface arrays.
- Directed hop latency is one cycle per physical network hop after source-local FIFO acceptance; local ejection requires zero network hops.
- The scalar and interface torus boundaries expose all router counters as flat packed vectors. Per-port counters use node-major ordering with `counter_index = node * NOC_NUM_PORTS + port`; packet-ejection counters use node index directly.
- Torus protocol status is also node-major, with `error_index = node * NOC_NUM_PORTS * NOC_NUM_VCS + port * NOC_NUM_VCS + vc`.

## Locked Verification Decisions

- `tb/model/torus_ref.py` is an independent pure Python oracle for node indexing, minimal X-then-Y paths, positive tie-breaking, dateline crossings, and per-dimension VC transitions.
- `tb/drivers/torus_local.py` owns per-source injection queues and drives the packed local endpoint buses without embedding routing expectations.
- `tb/monitors/torus_scoreboard.py` checks exact flit identity, destination, final VC, per-packet order, packet completion, and non-interleaving independently for each `(destination, VC)` stream. Legal interleaving between endpoint VCs is accepted.
- The ejection monitor requires `valid`, `flit`, and `vc` to remain stable through endpoint backpressure.
- Random traffic is reproducible through `TORUS_RANDOM_SEED` and `RANDOM_PACKETS`; the default seed is `20260723` with 48 packets per pattern.
- Uniform and 75% hotspot traffic use one- to four-flit packets. All packets enter on VC0 and the reference model predicts the final ejection VC.
- Sink readiness is randomized, with every eighth cycle forced ready at all endpoints to avoid testbench-created permanent starvation.
- A 200-cycle endpoint no-progress watchdog screens for deadlock; every run also has a packet-count-scaled absolute cycle limit and must fully drain.
- `tb/model/functional_coverage.py` records directions, directional datelines, X/Y ties, hop counts, packet lengths, final VCs, traffic patterns, participating endpoints, and source/destination pairs. Required bins and minimum breadth are pass criteria.
- Each randomized run writes a deterministic JSON coverage report. `tb/scripts/run_torus_stress.py` runs seed/FIFO-depth matrices, merges reports, writes `stress_summary.json`, and returns failure for any simulation or aggregate coverage shortfall.
- The default stress matrix uses five fixed seeds, FIFO depths 1, 3, and 5, 64 packets per traffic pattern, and a minimum of 192 unique endpoint pairs.
- The release-style root `make soak` gate uses three fixed seeds, FIFO depths 1, 3, and 5, 256 packets per traffic pattern, and a minimum of 240 unique endpoint pairs.

## Component Confidence Status

- `fifo.sv` passes its permanent self-checking cocotb test in `tb/unit/test_fifo.py` with Icarus Verilog 11.0. It covers reset, ordering, full/empty boundaries, simultaneous operations, overflow/underflow rejection, and explicit pointer wrap.
- `rr_arbiter.sv` passes three permanent cocotb tests in `tb/unit/test_rr_arbiter.py` at both 5 requesters and the 1-requester boundary. They cover no-request behavior, pointer hold and advance, one-hot/index consistency, persistent-request fairness, sparse requests, skipped inactive requesters, and wrap-around. The Icarus-compatible RTL also passes Verilator lint.
- `router_port_in.sv` passes five permanent component tests in `tb/component/test_router_port_in.py` at FIFO depths 3 and 4. They cover VC-selective buffering and backpressure, FIFO ordering, underflow tolerance, dateline next-VC transition, BODY/TAIL route inheritance, HEADTAIL state release, independent interleaved VC0/VC1 packet state, plus malformed starts, invalid header lengths, early TAIL, late BODY, nested-header resynchronization, sticky status, and reset clearing. The hierarchy also passes Verilator lint.
- `route_compute_torus.sv` passes an exhaustive permanent cocotb test in `tb/unit/test_route_compute_torus.py`: all 256 source/destination pairs are checked for both incoming VCs (512 cases total). Coverage assertions require local delivery, all four directions, X-before-Y behavior, both positive-direction tie-breaks, all four datelines, and per-hop VC preservation. The module also passes Verilator lint.
- `torus4x4_core.sv` and its complete synthesizable implementation hierarchy pass warning-clean Verilator 4.038 lint with only the intentional package wildcard-import warning suppressed. A shared flattened Verilator harness dynamically exercises both production `noc_link_if` wrappers; it uses a dedicated clean build path to avoid stale incremental objects from this older tool. Cocotb 2.0.1 still requires Verilator 5.036 or newer, so Icarus remains the cocotb simulator.
- `router_crossbar.sv` passes seven permanent component tests in `tb/component/test_router_crossbar.py`. They cover idle and invalid routes, five simultaneous independent outputs, downstream backpressure, late-requester stalled-grant stability, sparse round-robin fairness, HEADTAIL release, multi-flit output ownership through an input gap and TAIL, and sibling-VC bypass during a packet gap.
- `router_core.sv` passes eleven permanent component tests in `tb/component/test_router_core.py` at FIFO depths 3 and 4. They cover all five routes, dateline VC transitions, five parallel paths, full-FIFO backpressure and ordered recovery, contiguous multi-flit arbitration, exact empty-input and downstream-backpressure event semantics, forced narrow-width saturation for every counter class, per-port/VC protocol status ordering and reset propagation, one-VC-per-input enforcement, dual-VC round-robin fairness, stalled-selection stability, sibling retry after output loss, and VC-class restart at the X-to-Y boundary.
- `torus4x4_core.sv` passes eight permanent integration tests across `tb/integration/test_torus4x4_core.py` and `tb/integration/test_torus4x4_closure.py`. They cover local and cardinal paths, all four datelines, positive X/Y ties, the four-hop longest path, ordered multi-flit wrap delivery, concurrent end-to-end packets, node-major counters and protocol status, packets longer than FIFO depth under backpressure, sustained dual-VC streams, and in-flight reset flush/recovery.
- `tb/integration/test_torus4x4_random.py` passes deterministic uniform and hotspot traffic with randomized endpoint backpressure. Every legal randomized drain also requires the complete network protocol-status vector to remain zero. The default run checks 96 packets and 235 flits, fills every required functional coverage bin, and reaches all 16 sources and destinations across 67 unique endpoint pairs.
- The randomized ejection stability monitor exposed and drove fixes for late-requester grant replacement, input-selector/crossbar stalled-owner divergence, physical-output ownership that blocked a sibling VC, global VC-class reuse across dimensions, and physical ready coupling between downstream VCs.
- The final `make soak` gate passes all 9 cases across three seeds and FIFO depths 1, 3, and 5. It drains 4,608 packets and 11,535 flits, fills every required architecture bin, and reaches 250 of 256 source/destination pairs.
- The complete quick regression passes 39 cocotb tests plus 13 pure Python oracle, scoreboard, and coverage tests. Both production `noc_link_if` wrappers also pass their shared dynamic smoke harness.

## Verification Workflow

- The root `Makefile` provides `rtl-compile`, `lint`, `interface-smoke`, `regression`, `stress`, `soak`, and combined `check` quality gates. `rtl-compile` compiles with simulation invariants enabled; `lint` defines `SYNTHESIS` and checks the implementation hierarchy; `check` also dynamically validates both public wrappers.
- `tb/Makefile` dispatches component tests through per-component files under `tb/config/`; generated output is isolated by component and parameter variant under `tb/sim_build/`.
- Tests are grouped by verification level under `tb/unit/`, `tb/component/`, and `tb/integration/`.
- Reusable verification code is grouped under `tb/model/`, `tb/drivers/`, `tb/monitors/`, and `tb/common/`.
- `make -C tb regression` is the fast bottom-up gate. `make -C tb test-torus-stress` is the configurable matrix runner. Root `make soak` is the stronger release-style matrix and remains intentionally separate from `make check`.
- Stress reports are generated under `tb/sim_build/stress/` and remain untracked.
- Leaf RTL modules are used directly as simulation tops. SystemVerilog wrappers are reserved for interface visibility or genuine multi-module integration needs.
- Icarus Verilog 11.0 is the current cocotb simulator; Verilator 4.038 remains the lint tool because cocotb 2.0.1 requires Verilator 5.036 or newer. No Yosys, commercial synthesis tool, or target-device constraint set is installed, so compile/lint readiness must not be described as completed FPGA synthesis. The current tools cannot provide useful cocotb RTL line/toggle coverage, so functional coverage is enforced while RTL code coverage remains open.
- Validate in this order: FIFO, round-robin arbiter, route computation, input port, crossbar/arbitration, one router, then the complete 4x4 torus.
- Each layer must retain passing lower-level tests before it becomes a dependency of the next layer.
