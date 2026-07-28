.DEFAULT_GOAL := test

ROOT_DIR := $(abspath ..)
COMPONENT ?= fifo
SIM ?= icarus
STRESS_SEEDS ?= 20260723,314159,271828,161803,424242
STRESS_FIFO_DEPTHS ?= 1,3,5
STRESS_PACKETS ?= 64
STRESS_MINIMUM_PAIRS ?= 192

COMPONENT_CONFIG := $(CURDIR)/config/$(COMPONENT).mk
ifeq ($(wildcard $(COMPONENT_CONFIG)),)
$(error Unknown COMPONENT '$(COMPONENT)'; run 'make list' to see available components)
endif
include $(COMPONENT_CONFIG)
CUSTOM_COMPILE_DEPS += $(COMPONENT_CONFIG)
BUILD_VARIANT ?= default

export PYTHONPATH := $(CURDIR):$(PYTHONPATH)

SIM_BUILD := $(CURDIR)/sim_build/$(COMPONENT)/$(BUILD_VARIANT)
COCOTB_RESULTS_FILE := $(SIM_BUILD)/results.xml

.PHONY: test test-model test-fifo test-rr-arbiter test-route-compute test-router-port-in test-crossbar test-router test-torus test-torus-random test-torus-stress regression list
test: sim

test-model:
	PYTHONPATH=$(CURDIR) python3 -m unittest model.test_torus_ref model.test_packet_scoreboard model.test_functional_coverage

test-fifo:
	$(MAKE) test COMPONENT=fifo

test-rr-arbiter:
	$(MAKE) test COMPONENT=rr_arbiter

test-route-compute:
	$(MAKE) test COMPONENT=route_compute_torus

test-router-port-in:
	$(MAKE) test COMPONENT=router_port_in

test-crossbar:
	$(MAKE) test COMPONENT=router_crossbar

test-router:
	$(MAKE) test COMPONENT=router_core

test-torus:
	$(MAKE) test COMPONENT=torus4x4_core

test-torus-random:
	$(MAKE) test COMPONENT=torus4x4_random

test-torus-stress:
	PYTHONPATH=$(CURDIR) python3 scripts/run_torus_stress.py --sim "$(SIM)" --seeds "$(STRESS_SEEDS)" --fifo-depths "$(STRESS_FIFO_DEPTHS)" --packets "$(STRESS_PACKETS)" --minimum-pairs "$(STRESS_MINIMUM_PAIRS)"

regression:
	$(MAKE) test-model
	$(MAKE) test COMPONENT=fifo
	$(MAKE) test COMPONENT=rr_arbiter
	$(MAKE) test COMPONENT=route_compute_torus
	$(MAKE) test COMPONENT=router_port_in
	$(MAKE) test COMPONENT=router_crossbar
	$(MAKE) test COMPONENT=router_core
	$(MAKE) test COMPONENT=torus4x4_core
	$(MAKE) test COMPONENT=torus4x4_random

list:
	@echo "fifo"
	@echo "rr_arbiter"
	@echo "route_compute_torus"
	@echo "router_port_in"
	@echo "router_crossbar"
	@echo "router_core"
	@echo "torus4x4_core"
	@echo "torus4x4_random"

include $(shell cocotb-config --makefiles)/Makefile.sim
