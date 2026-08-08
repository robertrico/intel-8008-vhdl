# cocotb build glue: delegates to cocotb's own Makefile.sim.
# Invoked from the top-level Makefile as: make cocotb-<module> [DUT_VARIANT=...]
# TOPLEVEL selects the DUT entity; MODULE the python test file test_<entity>.py.
# DUT_VARIANT=rtl (default) compiles the b8008 sources; netlist compiles the
# write_vhdl round trip from build/synth instead (issue #235 validation).

SIM ?= ghdl
TOPLEVEL_LANG ?= vhdl
TOPLEVEL ?= stack_pointer
MODULE ?= test_$(TOPLEVEL)
DUT_VARIANT ?= rtl
REPO := $(abspath ../..)

ifeq ($(DUT_VARIANT),netlist)
VHDL_SOURCES = $(REPO)/build/synth/$(TOPLEVEL)_netlist.vhdl
else
VHDL_SOURCES = $(REPO)/src/b8008/b8008_types.vhdl $(REPO)/src/b8008/$(TOPLEVEL).vhdl
endif

COMPILE_ARGS = --std=08
SIM_ARGS = --wave=$(TOPLEVEL)_$(DUT_VARIANT).ghw

include $(shell cocotb-config --makefiles)/Makefile.sim
