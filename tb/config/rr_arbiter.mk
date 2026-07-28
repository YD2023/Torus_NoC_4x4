TOPLEVEL_LANG := verilog
TOPLEVEL := rr_arbiter
COCOTB_TEST_MODULES := unit.test_rr_arbiter

NUM_REQ ?= 5
export NUM_REQ
BUILD_VARIANT := num_req_$(NUM_REQ)

VERILOG_SOURCES := \
	$(ROOT_DIR)/rtl/noc_pkg.sv \
	$(ROOT_DIR)/rtl/rr_arbiter.sv

ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).NUM_REQ=$(NUM_REQ)
else ifeq ($(SIM),verilator)
COMPILE_ARGS += -GNUM_REQ=$(NUM_REQ)
endif
