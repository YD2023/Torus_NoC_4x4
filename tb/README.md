# Cocotb Verification

The testbench is organized by verification level. Each RTL component is compiled
directly as the cocotb top whenever its ports are simulator-visible. The current
testbench contains only the FIFO unit test.

Icarus Verilog is the default cocotb simulator in this workspace. Verilator
remains the RTL lint tool until its installed version supports cocotb 2.x.

## Layout

```text
tb/
|- Makefile
|- config/
|  `- fifo.mk
|- common/
|  `- clock_reset.py
|- unit/
|  `- test_fifo.py
`- sim_build/
```

Component configs own the RTL sources, top-level module, cocotb module, and
parameters for one test target. Generated output is isolated by component.

## Running

```sh
make -C tb test
make -C tb test COMPONENT=fifo
make -C tb test-fifo
make -C tb regression
```

Override the FIFO configuration from the command line:

```sh
make -C tb test-fifo FIFO_WIDTH=32 FIFO_DEPTH=5
```

## Adding A Component

1. Add `config/<component>.mk` with its sources, RTL top, and cocotb module.
2. Add its test under `unit/`, `component/`, or `integration/`.
3. Add the component name to the Makefile's `list` and `regression` targets.
4. Reuse helpers from `common/` instead of duplicating drivers and protocol code.

Add a SystemVerilog wrapper only when interface visibility or multi-module
integration requires one; ordinary leaf modules should be tested directly.
