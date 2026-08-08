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
else ifeq ($(TOPLEVEL),b8008_top)
# Whole-system DUT (bus-protocol monitor): full core + system glue.
# The ROM is served by the Python testbench through the external ROM
# port, so no ROM model is compiled.
B8008_CORE_SRCS = b8008_types stack_pointer stack_memory \
	instruction_register instruction_decoder condition_flags \
	register_file scratchpad_decoder ahl_pointer temp_registers \
	carry_lookahead alu io_buffer mem_mux_refresh \
	state_timing_generator machine_cycle_control memory_io_control \
	register_alu_control interrupt_ready_ff b8008 ram_sync \
	address_decoder b8008_top
VHDL_SOURCES = $(REPO)/src/components/phase_clocks.vhdl \
	$(foreach m,$(B8008_CORE_SRCS),$(REPO)/src/b8008/$(m).vhdl)
else
VHDL_SOURCES = $(REPO)/src/b8008/b8008_types.vhdl $(REPO)/src/b8008/$(TOPLEVEL).vhdl
endif

COMPILE_ARGS = --std=08
SIM_ARGS = --wave=$(TOPLEVEL)_$(DUT_VARIANT).ghw

include $(shell cocotb-config --makefiles)/Makefile.sim
