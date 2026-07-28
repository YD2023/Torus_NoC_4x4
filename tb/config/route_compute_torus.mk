TOPLEVEL_LANG := verilog
TOPLEVEL := route_compute_torus
COCOTB_TEST_MODULES := unit.test_route_compute_torus

X_DIM ?= 4
Y_DIM ?= 4
COORD_W ?= 2
VC_W ?= 1
export X_DIM
export Y_DIM
export COORD_W
export VC_W
BUILD_VARIANT := x_$(X_DIM)_y_$(Y_DIM)_coord_$(COORD_W)_vc_$(VC_W)

VERILOG_SOURCES := \
	$(ROOT_DIR)/rtl/noc_pkg.sv \
	$(ROOT_DIR)/rtl/route_compute_torus.sv

ifeq ($(SIM),icarus)
COMPILE_ARGS += -P$(TOPLEVEL).X_DIM=$(X_DIM)
COMPILE_ARGS += -P$(TOPLEVEL).Y_DIM=$(Y_DIM)
COMPILE_ARGS += -P$(TOPLEVEL).COORD_W=$(COORD_W)
COMPILE_ARGS += -P$(TOPLEVEL).VC_W=$(VC_W)
else ifeq ($(SIM),verilator)
COMPILE_ARGS += -GX_DIM=$(X_DIM)
COMPILE_ARGS += -GY_DIM=$(Y_DIM)
COMPILE_ARGS += -GCOORD_W=$(COORD_W)
COMPILE_ARGS += -GVC_W=$(VC_W)
endif
