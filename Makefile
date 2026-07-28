.DEFAULT_GOAL := check

RTL_CORE_SOURCES := \
	rtl/noc_pkg.sv \
	rtl/fifo.sv \
	rtl/rr_arbiter.sv \
	rtl/route_compute_torus.sv \
	rtl/router_vc_in.sv \
	rtl/router_port_in.sv \
	rtl/router_crossbar.sv \
	rtl/router_core.sv \
	rtl/torus4x4_core.sv

.PHONY: check rtl-compile lint interface-smoke regression stress soak

check: rtl-compile lint interface-smoke regression

rtl-compile:
	iverilog -g2012 -tnull -s torus4x4_core $(RTL_CORE_SOURCES)

lint:
	verilator --lint-only -Wall -Wno-IMPORTSTAR \
		-DSYNTHESIS --top-module torus4x4_core $(RTL_CORE_SOURCES)

interface-smoke:
	bash tb/scripts/run_interface_smoke.sh

regression:
	$(MAKE) -C tb regression

stress:
	$(MAKE) -C tb test-torus-stress

soak:
	$(MAKE) -C tb test-torus-stress \
		STRESS_SEEDS=20260723,314159,271828 \
		STRESS_FIFO_DEPTHS=1,3,5 \
		STRESS_PACKETS=256 \
		STRESS_MINIMUM_PAIRS=240
