TOPLEVEL_LANG := verilog
TOPLEVEL := torus4x4_core
COCOTB_TEST_MODULES := integration.test_torus4x4_core,integration.test_torus4x4_closure

TORUS_FIFO_DEPTH ?= 3
export TORUS_FIFO_DEPTH
BUILD_VARIANT := fifo_$(TORUS_FIFO_DEPTH)

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
