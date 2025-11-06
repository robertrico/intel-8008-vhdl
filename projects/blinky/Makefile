# Makefile for Blinky Hardware Validation Project
# First hardware test for Intel 8008 on ECP5-5G Versa board

#==========================================
# Project Configuration
#==========================================
PROJECT_NAME = blinky
TOP_ENTITY = blinky_top
TB_ENTITY = blinky_tb

# Project root directory
PROJECT_ROOT = ../..
WORK_DIR = work

#==========================================
# Simulation Configuration
#==========================================
# Run simulation for 100ms (enough to see several blinks)
SIM_STOP_TIME = 100ms

#==========================================
# Source Files
#==========================================
RTL_SOURCES = src/blinky_top.vhdl \
              src/io_controller.vhdl \
              src/interrupt_controller.vhdl \
              $(PROJECT_ROOT)/src/components/s8008.vhdl \
              $(PROJECT_ROOT)/src/components/i8008_alu.vhdl \
              $(PROJECT_ROOT)/src/components/phase_clocks.vhdl \
              $(PROJECT_ROOT)/src/components/rom_2kx8.vhdl \
              $(PROJECT_ROOT)/src/components/ram_1kx8.vhdl

TB_SOURCES = blinky_tb.vhdl
INT_CTL_TB = src/interrupt_controller_tb.vhdl

#==========================================
# Constraint File Override
#==========================================
# Use project-specific constraint file instead of default
LPF_FILE = $(PROJECT_ROOT)/projects/blinky/constraints/blinky.lpf

#==========================================
# Program Assembly Configuration
#==========================================
NAKEN_ASM ?= /Users/hackbook/Development/naken_asm/naken_asm
PYTHON = python3

#==========================================
# Include Common Build Rules
#==========================================
include $(PROJECT_ROOT)/common.mk

#==========================================
# Project-Specific Targets
#==========================================

# Assemble the blinky program
.PHONY: asm
asm:
	@echo "=== Assembling blinky.asm ==="
	$(NAKEN_ASM) -I . -l -type hex -o blinky.hex blinky.asm
	@echo "✓ Assembly complete"

# Assemble the simple blinky program (minimal test)
.PHONY: asm-simple
asm-simple:
	@echo "=== Assembling blinky_simple.asm ==="
	$(NAKEN_ASM) -I . -l -type hex -o blinky_simple.hex blinky_simple.asm
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py blinky_simple.hex blinky_simple.mem
	@echo "✓ Generated blinky_simple.mem"

# Convert to MEM format
.PHONY: hex2mem
hex2mem: asm
	@echo "=== Converting to MEM format ==="
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py blinky.hex blinky.mem
	@echo "✓ Generated blinky.mem"

# Build everything (assemble simple program + synthesize FPGA)
.PHONY: all
all: asm-simple bitstream

# Clean project files
.PHONY: clean-proj
clean-proj: clean
	rm -f blinky.hex blinky.lst blinky.mem

.PHONY: help-proj
help-proj:
	@echo "Blinky Hardware Validation - Makefile"
	@echo "======================================"
	@echo ""
	@echo "Build Flow:"
	@echo "  1. make asm         - Assemble blinky.asm"
	@echo "  2. make hex2mem     - Convert to mem format"
	@echo "  3. make bitstream   - Synthesize for FPGA"
	@echo "  4. make program     - Program FPGA SRAM"
	@echo "  5. make flash       - Program FPGA flash"
	@echo ""
	@echo "Quick Commands:"
	@echo "  make all            - Build everything (asm + synthesis)"
	@echo "  make reports        - View timing/utilization"
	@echo "  make clean-proj     - Clean generated files"
	@echo ""
	@echo "Hardware Programming:"
	@echo "  make program        - Quick test (volatile SRAM)"
	@echo "  make flash          - Persistent (survives power cycle)"
	@echo ""
	@echo "Expected Behavior:"
	@echo "  - LED0 blinks at steady rate"
	@echo "  - Press SW3-2: Blink rate changes"
	@echo "  - Release SW3-2: Blink rate returns to normal"
	@echo "  - Debug pins on J39: Connect logic analyzer"
	@echo ""
	@echo "Debug Header (PMOD J39):"
	@echo "  Pin 1-8:   Data bus D0-D7"
	@echo "  Pin 9-11:  State outputs S0-S2"
	@echo "  Pin 12:    SYNC signal"
	@echo "  Pin 13-14: Phase clocks φ1, φ2"
	@echo "  Pin 15-16: READY, INT signals"
	@echo ""

# Target to verify constraint file exists
.PHONY: check-constraints
check-constraints:
	@if [ ! -f "$(LPF_FILE)" ]; then \
		echo "Error: Constraint file not found: $(LPF_FILE)"; \
		exit 1; \
	fi
	@echo "✓ Constraint file found: $(LPF_FILE)"

# Override bitstream target to check constraints first
bitstream: check-constraints hex2mem $(BITSTREAM_FILE)

# Test interrupt controller
.PHONY: test-interrupt-controller
test-interrupt-controller:
	@echo "=== Testing Interrupt Controller ==="
	/Users/hackbook/oss-cad-suite/bin/ghdl -a --std=08 --workdir=work src/interrupt_controller.vhdl
	/Users/hackbook/oss-cad-suite/bin/ghdl -a --std=08 --workdir=work $(INT_CTL_TB)
	/Users/hackbook/oss-cad-suite/bin/ghdl -e --std=08 --workdir=work interrupt_controller_tb
	/Users/hackbook/oss-cad-suite/bin/ghdl -r --std=08 --workdir=work interrupt_controller_tb
	@echo "✓ Interrupt Controller test complete"
