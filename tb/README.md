# Cocotb Verification

The testbench is organized by verification level. Each RTL component is compiled
directly as the cocotb top whenever its ports are simulator-visible. The current
testbench contains pure Python oracle checks, three primitive suites, three
router component suites, directed, closure, and randomized torus integration suites, a shared
production-interface smoke harness, and a reproducible multi-seed stress matrix.

Icarus Verilog is the default cocotb simulator in this workspace. Verilator
remains the RTL lint tool until its installed version supports cocotb 2.x.

## Layout

```text
tb/
|- Makefile
|- config/
|  |- fifo.mk
|  |- rr_arbiter.mk
|  |- route_compute_torus.mk
|  |- router_port_in.mk
|  |- router_crossbar.mk
|  |- router_core.mk
|  |- torus4x4_core.mk
|  `- torus4x4_random.mk
|- common/
|  |- clock_reset.py
|  |- flit.py
|  `- packed.py
|- model/
|  |- torus_ref.py
|  |- functional_coverage.py
|  |- test_torus_ref.py
|  |- test_packet_scoreboard.py
|  `- test_functional_coverage.py
|- drivers/
|  `- torus_local.py
|- monitors/
|  `- torus_scoreboard.py
|- harness/
|  `- noc_interface_smoke_top.sv
|- verilator/
|  `- interface_smoke.cpp
|- scripts/
|  |- run_interface_smoke.sh
|  `- run_torus_stress.py
|- unit/
|  |- test_fifo.py
|  |- test_rr_arbiter.py
|  `- test_route_compute_torus.py
|- component/
|  |- test_router_port_in.py
|  |- test_router_crossbar.py
|  `- test_router_core.py
|- integration/
|  |- test_torus4x4_core.py
|  |- test_torus4x4_closure.py
|  `- test_torus4x4_random.py
`- sim_build/
```

Component configs own the RTL sources, top-level module, cocotb module, and
parameters for one test target. Generated output is isolated by component.

## Running

```sh
make -C tb test
make -C tb test COMPONENT=fifo
make -C tb test-fifo
make -C tb test-rr-arbiter
make -C tb test-route-compute
make -C tb test-router-port-in
make -C tb test-crossbar
make -C tb test-router
make -C tb test-torus
make -C tb test-torus-random
make -C tb test-torus-stress
make -C tb test-model
make -C tb regression
make interface-smoke
make check
make soak
```

Override component and stress parameters from the command line:

```sh
make -C tb test-fifo FIFO_WIDTH=32 FIFO_DEPTH=5
make -C tb test-rr-arbiter NUM_REQ=7
make -C tb test-router-port-in PORT_FIFO_DEPTH=4
make -C tb test-router ROUTER_FIFO_DEPTH=4 ROUTER_COUNTER_WIDTH=8
make -C tb test-torus TORUS_FIFO_DEPTH=4
make -C tb test-torus-random TORUS_RANDOM_SEED=314159 RANDOM_PACKETS=64
make -C tb test-torus-stress \
  STRESS_SEEDS=11,22,33 \
  STRESS_FIFO_DEPTHS=1,4 \
  STRESS_PACKETS=96 \
  STRESS_MINIMUM_PAIRS=160
```

The directed closure suite checks packets longer than the configured FIFO depth,
sustained interleaved VC0 and VC1 streams on one physical input, in-flight reset
flush and recovery, and malformed-flit forwarding with sticky status. The shared
Verilator harness dynamically exercises both production `noc_link_if` wrappers
without creating a separate top for each component. The installed Verilator
4.038 build uses hierarchy flattening and a dedicated build directory for this
interface compatibility check.

Packet ownership is tracked per `(physical output, outgoing VC)`, so packet
flits remain contiguous within a VC while an independent sibling VC can use a
gap on the same link. Inside `torus4x4_core`, cardinal flow control carries two
ready bits per link and arbitration considers only requesters whose exact
downstream VC FIFO can accept data. Public links remain the specified tagged
single valid/ready interface.

VC dateline classes are monotonic within one dimension. At the legal X-to-Y
DOR boundary, the class restarts at VC0 unless the first Y hop crosses the Y
dateline and therefore requires VC1. The Python oracle and router tests enforce
the same dimension-local policy.

The randomized target uses deterministic per-test seeds, uniform and 75%
hotspot traffic, packet lengths from one to four flits, randomized endpoint
backpressure, exact packet scoreboarding, and a 200-cycle no-progress watchdog.
Every packet is injected on VC0; its expected ejection VC comes from the
independent Python torus model.
Every legal randomized drain also requires the complete network
`protocol_error_o` vector to remain zero. Directed negative tests intentionally
exercise malformed starts, invalid lengths, positional faults, sticky status,
header resynchronization, hierarchy ordering, and reset clearing.

Functional coverage includes all five route outcomes, four directional
datelines, X and Y ties, hop counts zero through four, packet lengths one
through four, both final VCs, both traffic patterns, endpoint participation,
and unique source/destination pairs. Each random run writes
`functional_coverage.json`. The stress runner merges its matrix under
`tb/sim_build/stress/` and writes both `functional_coverage.json` and
`stress_summary.json`.

Router observability tests use a reduced counter width to exercise saturation quickly.
Production defaults remain 32 bits, with per-input empty-cycle, per-output
backpressure-cycle, received-flit, sent-flit, and packet-ejection counters.

The installed Icarus and Verilator versions do not support useful cocotb RTL
line/toggle coverage in this workspace. Functional coverage is enforced now;
RTL code coverage remains a toolchain-upgrade checkpoint.

## Adding A Component

1. Add `config/<component>.mk` with its sources, RTL top, and cocotb module.
2. Add its test under `unit/`, `component/`, or `integration/`.
3. Add the component name to the Makefile's `list` and `regression` targets.
4. Reuse helpers from `common/` instead of duplicating drivers and protocol code.

Add a SystemVerilog wrapper only when interface visibility or multi-module
integration requires one; ordinary leaf modules should be tested directly.
