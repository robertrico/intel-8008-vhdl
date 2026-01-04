# Intel 8008 v8008_test FPGA Project Makefile
# Runs the search.asm test program on ECP5-5G Versa hardware
#
# Usage:
#   make deploy     - Complete workflow (assemble, synthesize, program FPGA)
#   make asm        - Assemble search.asm to hex
#   make hex2mem    - Convert hex to mem format
#   make bitstream  - Synthesize FPGA bitstream
#   make program    - Program FPGA SRAM (volatile)
#   make flash      - Program FPGA flash (persistent)

# Project configuration
PROJECT_NAME = v8008_test
TOP_ENTITY = v8008_test_top
TB_ENTITY = v8008_test_tb
PROJECT_ROOT = ../..
WORK_DIR = work

# Simulation configuration
SIM_STOP_TIME = 600us

# ROM program configuration
ROM_PROGRAM = search_as
ROM_SOURCE = $(PROJECT_ROOT)/test_programs/$(ROM_PROGRAM).asm
ROM_HEX = $(PROJECT_ROOT)/test_programs/$(ROM_PROGRAM).hex
ROM_MEM = $(PROJECT_ROOT)/test_programs/$(ROM_PROGRAM).mem
ROM_P = $(PROJECT_ROOT)/test_programs/$(ROM_PROGRAM).p

# Tools
AS_ASM ?= /Users/${USERNAME}/Development/asl-current/asl
P2HEX ?= /Users/${USERNAME}/Development/asl-current/p2hex
AS_INCLUDE ?= /Users/${USERNAME}/Development/asl-current/include
PYTHON ?= python3

# RTL source files (order matters for GHDL)
RTL_SOURCES = \
	$(PROJECT_ROOT)/src/components/i8008_alu.vhdl \
	$(PROJECT_ROOT)/src/components/phase_clocks.vhdl \
	$(PROJECT_ROOT)/src/components/rom_2kx8.vhdl \
	$(PROJECT_ROOT)/src/components/ram_1kx8.vhdl \
	$(PROJECT_ROOT)/src/components/v8008.vhdl \
	$(PROJECT_ROOT)/src/components/memory_controller.vhdl \
	$(PROJECT_ROOT)/src/components/reset_interrupt_controller.vhdl \
	src/$(TOP_ENTITY).vhdl

# Constraint file
LPF_FILE = constraints/$(PROJECT_NAME).lpf

# Testbench sources
TB_SOURCES = v8008_test_tb.vhdl

# Include common build targets
include $(PROJECT_ROOT)/common.mk

# Assembly targets
.PHONY: asm hex2mem

asm: $(ROM_HEX)

$(ROM_HEX): $(ROM_SOURCE)
	@echo "Assembling $(ROM_SOURCE) with AS assembler..."
	cd $(PROJECT_ROOT)/test_programs && $(AS_ASM) -cpu 8008new -i $(AS_INCLUDE) -o $(ROM_PROGRAM).p -L $(ROM_PROGRAM).asm
	cd $(PROJECT_ROOT)/test_programs && $(P2HEX) $(ROM_PROGRAM).p $(ROM_PROGRAM).hex -F Intel
	@echo "Assembly complete: $(ROM_HEX)"
	@echo "Listing file: $(PROJECT_ROOT)/test_programs/$(ROM_PROGRAM).lst"

hex2mem: $(ROM_MEM)

$(ROM_MEM): $(ROM_HEX)
	@echo "Converting $(ROM_HEX) to memory format..."
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py $(ROM_HEX) $(ROM_MEM)
	@echo "Memory file created: $(ROM_MEM)"

# Make bitstream depend on memory file
bitstream: hex2mem

# Clean ROM artifacts
clean-rom:
	rm -f $(ROM_HEX) $(ROM_MEM) $(ROM_P)
	rm -f $(PROJECT_ROOT)/test_programs/$(ROM_PROGRAM).lst

clean-all: clean clean-rom
