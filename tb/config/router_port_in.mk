TOPLEVEL_LANG := verilog
TOPLEVEL := router_port_in
COCOTB_TEST_MODULES := component.test_router_port_in

PORT_FIFO_DEPTH ?= 3
export PORT_FIFO_DEPTH
BUILD_VARIANT := fifo_depth_$(PORT_FIFO_DEPTH)

VERILOG_SOURCES := \
	$(ROOT_DIR)/rtl/noc_pkg.sv \
	$(ROOT_DIR)/rtl/fifo.sv \
	$(ROOT_DIR)/rtl/route_compute_torus.sv \
	$(ROOT_DIR)/rtl/router_vc_in.sv \
	$(ROOT_DIR)/rtl/router_port_in.sv \

ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).FIFO_D=$(PORT_FIFO_DEPTH)
else ifeq ($(SIM),verilator)
COMPILE_ARGS += -GFIFO_D=$(PORT_FIFO_DEPTH)
endif
