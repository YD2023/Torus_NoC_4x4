TOPLEVEL_LANG := verilog
TOPLEVEL := router_core
COCOTB_TEST_MODULES := component.test_router_core

ROUTER_X ?= 3
ROUTER_Y ?= 0
ROUTER_FIFO_DEPTH ?= 3
ROUTER_COUNTER_WIDTH ?= 4
export ROUTER_X
export ROUTER_Y
export ROUTER_FIFO_DEPTH
export ROUTER_COUNTER_WIDTH
BUILD_VARIANT := x_$(ROUTER_X)_y_$(ROUTER_Y)_fifo_$(ROUTER_FIFO_DEPTH)_counter_$(ROUTER_COUNTER_WIDTH)

VERILOG_SOURCES := \
	$(ROOT_DIR)/rtl/noc_pkg.sv \
	$(ROOT_DIR)/rtl/fifo.sv \
	$(ROOT_DIR)/rtl/rr_arbiter.sv \
	$(ROOT_DIR)/rtl/route_compute_torus.sv \
	$(ROOT_DIR)/rtl/router_vc_in.sv \
	$(ROOT_DIR)/rtl/router_port_in.sv \
	$(ROOT_DIR)/rtl/router_crossbar.sv \
	$(ROOT_DIR)/rtl/router_core.sv

ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).X_COORD=$(ROUTER_X)
COMPILE_ARGS += -P$(TOPLEVEL).Y_COORD=$(ROUTER_Y)
COMPILE_ARGS += -P$(TOPLEVEL).FIFO_D=$(ROUTER_FIFO_DEPTH)
COMPILE_ARGS += -P$(TOPLEVEL).COUNTER_W=$(ROUTER_COUNTER_WIDTH)
else ifeq ($(SIM),verilator)
COMPILE_ARGS += -GX_COORD=$(ROUTER_X)
COMPILE_ARGS += -GY_COORD=$(ROUTER_Y)
COMPILE_ARGS += -GFIFO_D=$(ROUTER_FIFO_DEPTH)
COMPILE_ARGS += -GCOUNTER_W=$(ROUTER_COUNTER_WIDTH)
endif
