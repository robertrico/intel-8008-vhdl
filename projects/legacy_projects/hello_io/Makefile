# Makefile for Hello I/O Project
# Intel 8008 I/O-based "Hello, World!" demonstration

#==========================================
# Project Configuration
#==========================================
PROJECT_NAME = hello_io
TOP_ENTITY ?= s8008
TB_ENTITY ?= s8008_hello_io_tb

# Project root directory (two levels up)
PROJECT_ROOT = ../..
WORK_DIR = work
BUILD_DIR = build

#==========================================
# Simulation Configuration
#==========================================
STOP_TIME_s8008_hello_io_tb = 5000us
SIM_STOP_TIME ?= $(or $(STOP_TIME_$(TB_ENTITY)),1ms)

#==========================================
# Include Common Build Rules
#==========================================
include $(PROJECT_ROOT)/common.mk

#==========================================
# Source Files (defined AFTER common.mk to use absolute paths)
#==========================================
RTL_SOURCES = $(PROJECT_ROOT)/src/components/i8008_alu.vhdl \
              $(PROJECT_ROOT)/src/components/phase_clocks.vhdl \
              $(PROJECT_ROOT)/src/components/rom_2kx8.vhdl \
              $(PROJECT_ROOT)/src/components/ram_1kx8.vhdl \
              $(PROJECT_ROOT)/src/components/io_console.vhdl \
              $(PROJECT_ROOT)/src/components/s8008.vhdl

TB_SOURCES = s8008_hello_io_tb.vhdl

#==========================================
# Program Assembly Configuration
#==========================================
NAKEN_ASM ?= /Users/${USERNAME}/Development/naken_asm/naken_asm
PYTHON = python3

#==========================================
# Project-Specific Targets
#==========================================

# Default target: assemble and run simulation
.PHONY: all
all: asm hex2mem sim view-output

# Assemble the hello_io program
.PHONY: asm
asm: | $(BUILD_DIR)
	@echo "=== Assembling $(PROJECT_NAME).asm ==="
	$(NAKEN_ASM) -I . -l -type hex -o $(BUILD_DIR)/$(PROJECT_NAME).hex $(PROJECT_NAME).asm
	@echo "✓ Assembly complete: $(BUILD_DIR)/$(PROJECT_NAME).hex"
	@echo "✓ Listing file: $(BUILD_DIR)/$(PROJECT_NAME).lst"

# Convert HEX to MEM format
.PHONY: hex2mem
hex2mem: asm
	@echo "=== Converting HEX to MEM format ==="
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py $(BUILD_DIR)/$(PROJECT_NAME).hex $(BUILD_DIR)/$(PROJECT_NAME).mem
	@echo "✓ Generated $(BUILD_DIR)/$(PROJECT_NAME).mem"

# Run simulation (depends on hex2mem)
.PHONY: run
run: hex2mem sim

# View console output
.PHONY: view-output
view-output:
	@echo ""
	@echo "========================================"
	@echo "Console Output:"
	@echo "========================================"
	@cat console_output.txt 2>/dev/null || echo "No output file generated"
	@echo "========================================"

# Clean project-specific files
.PHONY: clean-proj
clean-proj: clean
	rm -rf $(BUILD_DIR)
	rm -f console_output.txt

.PHONY: help-proj
help-proj:
	@echo "Hello I/O Project Makefile"
	@echo "=========================="
	@echo ""
	@echo "Targets:"
	@echo "  all          - Assemble program, run simulation, view output"
	@echo "  asm          - Assemble hello_io.asm to hex"
	@echo "  hex2mem      - Convert hex to mem format"
	@echo "  run          - Assemble and run simulation"
	@echo "  sim          - Run simulation only"
	@echo "  view-output  - Display console output file"
	@echo "  clean-proj   - Clean all generated files"
	@echo "  help-proj    - Show this help"
