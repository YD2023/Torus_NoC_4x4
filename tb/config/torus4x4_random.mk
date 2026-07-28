TOPLEVEL_LANG := verilog
TOPLEVEL := torus4x4_core
COCOTB_TEST_MODULES := integration.test_torus4x4_random

TORUS_FIFO_DEPTH ?= 3
TORUS_RANDOM_SEED ?= 20260723
RANDOM_PACKETS ?= 48
export TORUS_FIFO_DEPTH TORUS_RANDOM_SEED RANDOM_PACKETS
BUILD_VARIANT := fifo_$(TORUS_FIFO_DEPTH)_seed_$(TORUS_RANDOM_SEED)_packets_$(RANDOM_PACKETS)
TORUS_COVERAGE_FILE ?= $(CURDIR)/sim_build/torus4x4_random/$(BUILD_VARIANT)/functional_coverage.json
export TORUS_COVERAGE_FILE

VERILOG_SOURCES := \
	$(ROOT_DIR)/rtl/noc_pkg.sv \
	$(ROOT_DIR)/rtl/fifo.sv \
	$(ROOT_DIR)/rtl/rr_arbiter.sv \
	$(ROOT_DIR)/rtl/route_compute_torus.sv \
	$(ROOT_DIR)/rtl/router_vc_in.sv \
	$(ROOT_DIR)/rtl/router_port_in.sv \
	$(ROOT_DIR)/rtl/router_crossbar.sv \
	$(ROOT_DIR)/rtl/router_core.sv \
	$(ROOT_DIR)/rtl/torus4x4_core.sv

ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).FIFO_D=$(TORUS_FIFO_DEPTH)
else ifeq ($(SIM),verilator)
COMPILE_ARGS += -GFIFO_D=$(TORUS_FIFO_DEPTH)
endif
