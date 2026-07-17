.DEFAULT_GOAL := test

ROOT_DIR := $(abspath ..)
COMPONENT ?= fifo
SIM ?= icarus

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

.PHONY: test test-fifo regression list
test: sim

test-fifo:
	$(MAKE) test COMPONENT=fifo

regression:
	$(MAKE) test COMPONENT=fifo

list:
	@echo "fifo"

include $(shell cocotb-config --makefiles)/Makefile.sim
