# Specification for a Student-Scale 4x4 Torus NoC in SystemVerilog and cocotb

## Scope and document basis

This specification is written as an implementation-facing design document rather than a literature review. Its structure follows a standard systems-engineering pattern: purpose and scope, interface requirements, architecture, and verification. That choice is intentional. ISO/IEC/IEEE 29148 defines requirements engineering as a life-cycle discipline, and NASA’s systems-engineering guidance explicitly calls out purpose and scope, interface requirements, and verification/validation plan outlines as core document elements. 

The technical target is a realistic three-month project for two master’s-level students: a synthesizable 4x4 bidirectional torus NoC in SystemVerilog, with Python and cocotb for verification. The recommended scope deliberately favors a clean deterministic design over a feature-maximal research router. That recommendation is supported by both the literature and open-source practice: low-complexity distributed routing is attractive for NoCs, simple routers are favored when area and verification effort matter, and educational/open-source designs tend to succeed when they are modular and tested bottom-up.

Torus topology is a sensible choice for a resume project because it is a real NoC/interconnect topology with practical relevance, not just a classroom variant. Torus networks add wrap-around links to reduce longest paths and increase path diversity, and they continue to appear in real systems and research prototypes. At the same time, even-sized tori create equal-length path ties, and torus DOR needs explicit deadlock handling, so the project exposes you to the exact routing and flow-control issues that make NoCs educationally valuable. 

## Recommended project scope and rationale

The open-source landscape is useful here because it shows what features are common, what features are heavy, and what features are realistic to borrow. RaveNoC provides a configurable SystemVerilog mesh with valid/ready signaling, pipelined wormhole switching, virtual channels, and optional clock-domain-crossing support. tnoc provides a configurable SystemVerilog mesh with wormhole flow control, virtual channels, on/off flow control, and AXI4 support. NoCRouter implements a mesh router with wormhole switching, multiple virtual channels, DOR, and on/off flow control, with a bottom-up design/testing methodology. ProNoC is a parameterized VC-based FPGA-oriented NoC generator. Recent torus-capable implementations also exist: ReCONNECT is a SystemVerilog RTL NoC supporting multiple topologies including torus and credit-based flow control, while OpenNoc uses a lighter-weight unidirectional torus with deflection routing. 

Taken together, those implementations suggest a very clear scoping rule: your first version should **not** try to combine torus routing, adaptive routing, AXI integration, CDC, QoS, and a complex VC allocator all at once. Advanced projects do support those features, but they do so with significantly more infrastructure. For a three-month student project, the highest-value scope is a single-clock torus, deterministic minimal routing, two virtual channels used for deadlock freedom, per-port input buffering, a simple separable or centralized round-robin arbitration policy, and a cocotb verification environment with a cycle-accurate Python reference model. 

The most important architectural decision is the routing/flow-control pair. The literature strongly supports minimal deterministic dimension-order routing as the simplest distributed NoC routing style, and it also makes clear that torus networks need more than ordinary mesh XY routing. In an even-sized torus, multiple equal-hop paths can exist in a dimension, so a deterministic tie-break rule is required. More importantly, torus DOR requires at least two virtual channels to avoid cyclic dependencies, and the classic dateline technique is the simplest way to do that.

That leads to the recommended minimum viable product:

| Item | Recommended choice |
|---|---|
| Topology | 4x4 bidirectional 2D torus |
| Router radix | 5 ports: North, South, East, West, Local |
| Flow control | Wormhole, flit-based |
| Deadlock control | 2 virtual channels with dateline-based VC transition |
| Routing | Deterministic minimal X-then-Y torus DOR |
| Tie-break | Positive direction wins on equal-hop ties |
| Link protocol | Internal valid/ready handshake |
| Clocking | Single synchronous clock domain |
| Verification | cocotb + Python reference model + randomized regression |
| Non-goals for MVP | Adaptive routing, AXI NI, CDC, formal proofs, QoS, multicasting |

This is the right balance of ambition and finishability. It still teaches topology, routing, buffering, arbitration, backpressure, verification architecture, and end-to-end performance measurement. It just avoids the “feature pile-up” that often causes student NoC projects to stall.

## Normative implementation specification

The following requirements are the recommended normative baseline. They use **shall** language because this section is meant to be implemented directly.

| Requirement ID | Requirement |
|---|---|
| SYS-TOPO | The design shall instantiate 16 routers arranged as a 4x4 2D torus. |
| SYS-PORTS | Each router shall expose five ports: north, south, east, west, and local. |
| SYS-ROUTING | The routing algorithm shall be deterministic minimal X-then-Y torus DOR. |
| SYS-TIE | When an even-dimension shortest-path tie occurs, the preferred direction shall be the positive direction. |
| SYS-VC | The network shall implement two virtual channels, VC0 and VC1. |
| SYS-DEADLOCK | The two VCs shall be used as escape classes with dateline-based monotonic transition from VC0 to VC1. |
| SYS-FLOW | Flow control shall be flit-based wormhole with valid/ready backpressure. |
| SYS-CLOCK | The entire MVP shall operate in one synchronous clock domain. |
| SYS-VERIFY | Verification shall include router-level and network-level cocotb regressions with packet-level scoreboarding. |

A 4x4 torus keeps the router radix at five while adding wrap-around connectivity at the network boundary. That is important: compared with a mesh, the topology changes the endpoint connectivity, but the individual router remains a five-port block. For a 4x4 network, torus wrap-around reduces the longest minimal path relative to mesh; for an even-by-even torus, the longest path is \((M+N)/2\), while for mesh XY routing it is \(M+N-2\). For \(M=N=4\), that means a longest minimal path of 4 hops for torus versus 6 for mesh.

A simple coordinate system should be fixed up front:

- `x ∈ {0,1,2,3}` increases from west to east.
- `y ∈ {0,1,2,3}` increases from north to south.
- `EAST = +x`, `WEST = -x`, `SOUTH = +y`, `NORTH = -y`.

A compact original topology diagram for implementation is below.

```text
             x=0        x=1        x=2        x=3
y=0        (0,0)------(1,0)------(2,0)------(3,0)
             |                                   |
             |                                   |
y=1        (0,1)------(1,1)------(2,1)------(3,1)
             |                                   |
             |                                   |
y=2        (0,2)------(1,2)------(2,2)------(3,2)
             |                                   |
             |                                   |
y=3        (0,3)------(1,3)------(2,3)------(3,3)
             |                                   |
             +-----------------------------------+

Wrap-around links:
(3,y) <-> (0,y) for all y
(x,3) <-> (x,0) for all x
```

The tie-break rule matters because in an even-sized torus there are source/destination pairs with two equal-hop shortest paths in a dimension. The literature explicitly notes that when a dimension size is even, equal-hop alternative paths occur, so the implementation needs a deterministic preference rule. The recommended rule is simple: if `+x` and `-x` are equally short, choose `+x`; if `+y` and `-y` are equally short, choose `+y`. That gives you determinism, easier debug, and straightforward scoreboarding. 

The recommended flit format is also intentionally simple and fully synthesizable.

| Field | Bits | Notes |
|---|---:|---|
| `flit_type` | 2 | `00=HEAD`, `01=BODY`, `10=TAIL`, `11=HEADTAIL` |
| `dst_x` | 2 | Destination X coordinate |
| `dst_y` | 2 | Destination Y coordinate |
| `src_x` | 2 | Source X coordinate |
| `src_y` | 2 | Source Y coordinate |
| `pkt_len` | 8 | Packet length in flits |
| `payload` | 46 | Payload or metadata |
| **Total** | **64** | Default flit width |

This 64-bit format is a recommendation, not a literature requirement, but it is well aligned with open-source RTL practice that keeps flits in a compact packed structure while exposing routing metadata in the head flit. It is large enough to be useful and small enough to remain easy to inspect in waveforms. RaveNoC and related SystemVerilog NoCs likewise parameterize flit width and packet size rather than hard-coding a complicated transport layer. citeturn4view3turn4view4

The internal link interface should be expressed as a SystemVerilog `interface`, because that materially improves readability and reuse. Open-source NoCRouter explicitly emphasizes this style. A recommended interface shape is:

```systemverilog
interface noc_link_if #(parameter int FLIT_W = 64, parameter int VC_W = 1);
  logic                 valid;
  logic                 ready;
  logic [FLIT_W-1:0]    flit;
  logic [VC_W-1:0]      vc_id;   // 0 or 1 in MVP
endinterface
```

Using interfaces and packed structs here is not just stylistic. It reduces wiring noise across 16 routers and makes cocotb handle naming cleaner. That is exactly the sort of modularity advantage you want in a student project. citeturn4view1

## Router microarchitecture

The generic VC-router literature describes a canonical decomposition: input buffers, routing logic, VC allocation, switch allocation, and crossbar traversal. Open-source mesh routers mirror that decomposition closely. For your schedule, the right move is to implement the same conceptual structure but simplify the VC side: use two fixed VC classes selected by routing/dateline rules, and do **not** build a fully general output-VC allocator in the MVP. 

Here is the recommended block diagram for one router.

```text
                    +--------------------------------------+
North in ---------->|                                      |----------> North out
South in ---------->|  Input Port Blocks (N,S,E,W,L)       |----------> South out
East  in ---------->|  - VC0 FIFO                          |----------> East  out
West  in ---------->|  - VC1 FIFO                          |----------> West  out
Local in ---------->|  - Head parser                       |----------> Local out
                    |  - Route state / packet state        |
                    |                                      |
                    |  Route compute  -> request matrix    |
                    |  Round-robin output arbiters         |
                    |  5x5 crossbar                        |
                    +--------------------------------------+
```

The input side should be organized as **five input-port blocks**, each with **two FIFOs**, one per VC class. This follows the standard VC-flow-control model in the literature, where each input port contains buffers associated with its VCs, and it also matches how existing RTL designs factor routers into input and output modules. 

The routing computation should only inspect head flits. Once a head flit arrives at the head of a FIFO, the router computes the desired output port from the current router coordinates and the destination coordinates. Body and tail flits should inherit that stored route from per-input-VC packet state. This is simpler than redecoding every flit and is consistent with common VC-router behavior. 

The actual next-hop function should be:

```text
if (cur_x != dst_x):
    dx_pos = (dst_x - cur_x + 4) % 4
    dx_neg = (cur_x - dst_x + 4) % 4
    if dx_pos < dx_neg: route = EAST
    else if dx_neg < dx_pos: route = WEST
    else route = EAST   // tie -> positive direction
else if (cur_y != dst_y):
    dy_pos = (dst_y - cur_y + 4) % 4
    dy_neg = (cur_y - dst_y + 4) % 4
    if dy_pos < dy_neg: route = SOUTH
    else if dy_neg < dy_pos: route = NORTH
    else route = SOUTH  // tie -> positive direction
else:
    route = LOCAL
```

This is still dimension-order routing, just adapted for torus modular distance. The basic attraction of XY/DOR remains the same as in the literature: it is distributed, low-complexity, and avoids routing tables for the simple case. 

Deadlock avoidance should use **four directional dateline sets**, one for each wrap direction class:

- east dateline: hop from `(3,y)` to `(0,y)`
- west dateline: hop from `(0,y)` to `(3,y)`
- south dateline: hop from `(x,3)` to `(x,0)`
- north dateline: hop from `(x,0)` to `(x,3)`

The rule is monotonic and simple: a packet starts in `VC0`; if the current hop crosses a dateline, the outgoing flit is marked for `VC1`; once in `VC1`, the packet stays in `VC1` for the remainder of its route. This is the classic dateline-style idea described in the torus-routing literature and by Cray’s torus routing work: virtual channels are used primarily to prevent deadlock around torus links, and crossing the dateline forces the packet into the higher VC class. 

The corresponding implementation rule can be written as:

```text
next_vc = current_vc
if route == EAST  and cur_x == 3: next_vc = 1
if route == WEST  and cur_x == 0: next_vc = 1
if route == SOUTH and cur_y == 3: next_vc = 1
if route == NORTH and cur_y == 0: next_vc = 1
```

This VC scheme is deliberately minimalist. It uses the two VCs as **escape classes for correctness**, not as independent priority/QoS channels. That is a very good trade for a first torus. The literature is explicit that torus DOR needs at least two VCs, while many higher-performance proposals exist mainly to improve VC utilization or adaptivity, not because the two-VC baseline is invalid. 

Output arbitration should be **round-robin per output port** across all eligible input VCs requesting that port. RaveNoC uses round-robin arbitration in its output module, and the generic VC-router literature also describes arbitration as a central component of the router. For your project, one round-robin pointer per output port is enough. Do not overcomplicate it with speculative allocation in the MVP. 

The recommended timing model is two conceptual stages per hop:

- **Stage A**: input acceptance into FIFO and head-flit route update if needed.
- **Stage B**: output arbitration, crossbar traversal, and flit launch when downstream `ready` is asserted.

That is simpler than a full textbook RC/VA/SA/ST pipeline, but it preserves the right educational content: buffered inputs, route computation, arbitration, backpressure, and crossbar transfer. It also aligns with the literature’s repeated emphasis that on-chip routers should remain simple when buffer and latency costs matter. 

Finally, add a small amount of debug hardware from day one. Every router should expose at least:

- flits received per input port
- flits sent per output port
- blocked cycles due to empty input
- blocked cycles due to downstream backpressure
- count of packets ejected locally

These counters are not academically required, but they pay for themselves immediately in cocotb scoreboards and in resume/demo value.

## Verification specification

The cocotb side should be designed as a real verification environment, not as a pile of directed tests. cocotb’s official quickstart explicitly notes that the HDL DUT can be instantiated directly in the simulator without extra HDL wrapper code, and the testbench can access internals through the `dut` object. The official runner documentation also makes it straightforward to build and run HDL from Python, optionally under `pytest`.

The simulator recommendation is straightforward. Use **Verilator as the default high-speed regression simulator**, because cocotb supports Verilator 5.036+ and Verilator itself is designed as a fast Verilog/SystemVerilog compiler/simulator with linting and coverage support. Keep **Icarus Verilog** as a secondary open-source compatibility path, and use **Questa** only if you already have access and want interactive GUI debug. cocotb’s simulator-support documentation explicitly lists support for Icarus 11.0+, Verilator 5.036+, and Questa; Verilator’s own documentation also supports assertions, code generation, and coverage analysis. 

The structure of the verification environment should be:

| Layer | What it checks |
|---|---|
| Pure Python model | Routing math, tie-breaks, dateline transitions, expected paths |
| cocotb link drivers/monitors | Handshake correctness and link-level transactions |
| Router tests | FIFO behavior, arbitration, local ejection, VC transitions |
| Network tests | End-to-end delivery, deadlock freedom under bounded load, ordering per source VC |
| Regression scripts | Multi-seed randomized testing, waveform dumps, coverage collection |

A good cocotb pattern here is to use passive monitors and a scoreboard/reference-model comparison, which is exactly how cocotb documents the use of monitors and scoreboards. In modern cocotb flows, the bus/testbenching helpers live in `cocotb-bus`, but you can also write a small custom scoreboard yourself if you want tighter control over packet semantics. 

The **Python reference model** should be the center of the environment. It should implement exactly the same:

- coordinate system
- shortest-path selection
- positive-direction tie-break rule
- dateline crossing rule
- expected next-hop at each router

That gives you a reliable oracle for both directed and randomized tests. Importantly, this also helps prevent the common student-project mistake of “verifying against the RTL’s own behavior” instead of a separate model.

The test plan should be built in layers:

**Directed unit tests.** Verify FIFO full/empty behavior, valid/ready stability, reset to empty state, flit-type legality, local loopback, and each individual dateline crossing case. These tests should explicitly target the edge routers, because torus bugs disproportionately happen at wrap-around boundaries. The torus literature makes clear that the hard part is not ordinary XY routing; it is the interaction between wrap-around links, equal-hop choices, and VC usage. 

**Directed router tests.** For one router with mocked neighboring readiness, verify that a head flit chooses the correct next port for all 16 destinations relative to the router’s own coordinate, that body and tail flits follow stored state, and that two or more requesters contending for one output port are served fairly by round-robin over time. Open-source NoCRouter’s emphasis on bottom-up verification is the right model to copy here.

**End-to-end network tests.** Inject packets across the full 4x4 torus for corner pairs such as `(0,0)->(3,0)`, `(0,0)->(0,3)`, `(3,3)->(0,0)`, and tie cases such as `(0,0)->(2,0)` and `(0,0)->(0,2)`. These tests must verify not only arrival, but also that the observed route matches the specified deterministic route. For an even torus, tie-case determinism is part of the functionality, not an implementation detail. 

**Randomized traffic tests.** Use uniform-random and hotspot traffic, because they are standard synthetic traffic patterns in torus-routing evaluation. The DTDOR work explicitly uses uniform and hotspot traffic in its evaluation methodology, which makes them good choices for your student benchmarking too.

**Deadlock-screening tests.** Under bounded injection rates, run long randomized regressions with a watchdog timeout. The pass condition is not “high performance”; it is “the network continues to make forward progress and eventually drains all injected packets.” This is where the dateline/VC design pays off.

**Coverage and debug outputs.** With Verilator, add `--coverage` for code coverage and `--trace-fst` or `--trace` as needed for waveforms. cocotb documents the Verilator integration points for coverage and tracing, and Verilator itself supports line, toggle, FSM, and property/covergroup-related coverage modes. 

A practical project layout is:

```text
rtl/
  noc_pkg.sv
  noc_link_if.sv
  fifo.sv
  rr_arbiter.sv
  route_compute_torus.sv
  router_port_in.sv
  router_crossbar.sv
  router.sv
  torus4x4.sv

tb/
  model/
    torus_ref.py
  drivers/
    link_driver.py
  monitors/
    link_monitor.py
  tests/
    test_fifo.py
    test_rr_arbiter.py
    test_route_compute.py
    test_router_directed.py
    test_router_random.py
    test_torus_end_to_end.py
    test_torus_hotspot.py
  conftest.py
  run.py
```

That structure is intentionally modest, but it is already strong enough to look professional.

## Twelve-week execution plan and success criteria

A project like this is realistic in three months **if you freeze the scope early**. The literature favors simpler routers when on-chip area and latency matter, and open-source student-oriented designs tend to succeed when they are modular and verified bottom-up. That combination strongly supports a phased plan rather than parallel feature chasing. 

The recommended schedule is:

| Weeks | Milestone | Deliverables |
|---|---|---|
| 1–2 | Spec freeze | Coordinate system, packet format, routing rules, VC/dateline rules, repo skeleton |
| 3–4 | Primitive RTL | FIFO, round-robin arbiter, route-compute module, interfaces, package types |
| 5–6 | Single router | 5-port router passing directed cocotb tests |
| 7–8 | 4x4 torus integration | Full topology wiring, local injection/ejection, basic end-to-end tests |
| 9–10 | Randomized verification | Python reference model, scoreboard, regressions, hotspot/uniform tests |
| 11 | Metrics and cleanup | Counters, waveforms, coverage, lint, README diagrams |
| 12 | Packaging | Final report, architecture figures, verification summary, demo video or plots |

The success criteria should be explicit.

**MVP success** means all of the following are true:

- the 4x4 torus compiles and simulates cleanly;
- packets reach the correct destination under directed and randomized tests;
- wrap-around tie cases use the documented preferred direction;
- dateline crossings transition from VC0 to VC1 exactly as specified;
- no deadlock is observed in long bounded-load randomized regressions;
- the repo contains a top-level block diagram, routing pseudocode, and reproducible cocotb regression commands.

**Stretch success** may include any of the following, but none should block MVP completion:

- credit-based flow control
- a general free-VC allocator
- AXI-stream or AXI-lite network interfaces
- adaptive routing
- synthesis results on FPGA
- formal assertions beyond simulation
- load-latency plotting scripts similar to NoC research/simulator workflows

That last point matters for presentation. If you finish the MVP and then add one small performance study—uniform versus hotspot latency curves, or mesh-versus-torus path statistics—you will have a much stronger resume artifact than if you attempt an over-ambitious router and never stabilize it. Open-source projects such as RaveNoC and ReCONNECT visibly benefit from reproducible regression and evaluation workflows, and your project should imitate that professionalism even if the architecture is simpler. 

The final recommendation, in one sentence, is this: **build a clean deterministic torus first, prove it thoroughly with cocotb, and only then spend any remaining time on performance extras.** That scope is academically grounded, implementable in three months, and strong enough to stand on a resume as a serious NoC project. 