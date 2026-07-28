TOPLEVEL_LANG := verilog
TOPLEVEL := router_crossbar
COCOTB_TEST_MODULES := component.test_router_crossbar

NUM_PORTS ?= 5
NUM_REQ ?= 10
FLIT_W ?= 64
VC_W ?= 1
PORT_W ?= 3
export NUM_PORTS
export NUM_REQ
export FLIT_W
export VC_W
export PORT_W
BUILD_VARIANT := ports_$(NUM_PORTS)_req_$(NUM_REQ)

VERILOG_SOURCES := \
	$(ROOT_DIR)/rtl/noc_pkg.sv \
	$(ROOT_DIR)/rtl/rr_arbiter.sv \
	$(ROOT_DIR)/rtl/router_crossbar.sv

ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).NUM_PORTS=$(NUM_PORTS)
COMPILE_ARGS += -P$(TOPLEVEL).NUM_REQ=$(NUM_REQ)
COMPILE_ARGS += -P$(TOPLEVEL).FLIT_W=$(FLIT_W)
COMPILE_ARGS += -P$(TOPLEVEL).VC_W=$(VC_W)
COMPILE_ARGS += -P$(TOPLEVEL).PORT_W=$(PORT_W)
else ifeq ($(SIM),verilator)
COMPILE_ARGS += -GNUM_PORTS=$(NUM_PORTS)
COMPILE_ARGS += -GNUM_REQ=$(NUM_REQ)
COMPILE_ARGS += -GFLIT_W=$(FLIT_W)
COMPILE_ARGS += -GVC_W=$(VC_W)
COMPILE_ARGS += -GPORT_W=$(PORT_W)
endif
