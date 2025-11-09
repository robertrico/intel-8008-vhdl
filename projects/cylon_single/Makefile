# Makefile for Button-Driven Cylon LED Effect Project
# Demonstrates io_controller input functionality with Intel 8008

#==========================================
# Project Configuration
#==========================================
PROJECT_NAME = cylon_single
TOP_ENTITY = cylon_single_top
TB_ENTITY = cylon_single_tb

# Project root directory
PROJECT_ROOT = ../..
WORK_DIR = work

#==========================================
# Simulation Configuration
#==========================================
# Run simulation for 100ms (button-driven, longer observation time)
SIM_STOP_TIME = 100ms

#==========================================
# Source Files
#==========================================
RTL_SOURCES = src/cylon_single_top.vhdl \
              $(PROJECT_ROOT)/src/components/io_controller.vhdl \
              $(PROJECT_ROOT)/src/components/reset_interrupt_controller.vhdl \
              $(PROJECT_ROOT)/src/components/memory_controller.vhdl \
              $(PROJECT_ROOT)/src/components/debouncer.vhdl \
              $(PROJECT_ROOT)/src/components/s8008.vhdl \
              $(PROJECT_ROOT)/src/components/i8008_alu.vhdl \
              $(PROJECT_ROOT)/src/components/phase_clocks.vhdl \
              $(PROJECT_ROOT)/src/components/rom_2kx8.vhdl \
              $(PROJECT_ROOT)/src/components/ram_1kx8.vhdl

TB_SOURCES = cylon_single_tb.vhdl

#==========================================
# Constraint File Override
#==========================================
# Use project-specific constraint file instead of default
LPF_FILE = $(PROJECT_ROOT)/projects/cylon_single/constraints/cylon_single.lpf

#==========================================
# Program Assembly Configuration
#==========================================
NAKEN_ASM ?= /Users/${USERNAME}/Development/naken_asm/naken_asm
PYTHON = python3

#==========================================
# Include Common Build Rules
#==========================================
include $(PROJECT_ROOT)/common.mk

#==========================================
# Project-Specific Targets
#==========================================

# Assemble the cylon_single program
.PHONY: asm
asm:
	@echo "=== Assembling cylon_single.asm ==="
	$(NAKEN_ASM) -I . -l -type hex -o cylon_single.hex cylon_single.asm
	@echo "✓ Assembly complete"

# Convert to MEM format
.PHONY: hex2mem
hex2mem: asm
	@echo "=== Converting to MEM format ==="
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py cylon_single.hex cylon_single.mem
	@echo "✓ Generated cylon_single.mem"

# Build everything (assemble program + synthesize FPGA)
.PHONY: all
all: asm hex2mem bitstream

# Full build and program workflow - does everything you need!
.PHONY: deploy
deploy: clean-proj hex2mem bitstream program
	@echo ""
	@echo "========================================="
	@echo "✓ FPGA programmed and ready!"
	@echo "✓ Button-driven Cylon LED effect loaded"
	@echo "✓ Press button on A18 to advance pattern"
	@echo "========================================="

# Clean project files
.PHONY: clean-proj
clean-proj: clean
	rm -f cylon_single.hex cylon_single.lst cylon_single.mem
	rm -f build/*

.PHONY: help-proj
help-proj:
	@echo "Button-Driven Cylon LED Effect - Makefile"
	@echo "=========================================="
	@echo ""
	@echo "Build Flow:"
	@echo "  1. make asm         - Assemble cylon_single.asm"
	@echo "  2. make hex2mem     - Convert to mem format"
	@echo "  3. make bitstream   - Synthesize for FPGA"
	@echo "  4. make program     - Program FPGA SRAM"
	@echo "  5. make flash       - Program FPGA flash"
	@echo ""
	@echo "Quick Commands:"
	@echo "  make deploy         - Complete workflow: clean, build, and program FPGA"
	@echo "  make all            - Build everything (asm + synthesis)"
	@echo "  make reports        - View timing/utilization"
	@echo "  make clean-proj     - Clean generated files"
	@echo ""
	@echo "Hardware Programming:"
	@echo "  make program        - Quick test (volatile SRAM)"
	@echo "  make flash          - Persistent (survives power cycle)"
	@echo ""
	@echo "Expected Behavior:"
	@echo "  - Single LED shows current position in Cylon pattern"
	@echo "  - Pattern: LED0 -> LED1 -> ... -> LED7 -> LED6 -> ... -> LED0"
	@echo "  - Each button press (A18) advances one step"
	@echo "  - Button is active-low with pull-up (press = 0, release = 1)"
	@echo "  - Hardware debouncing at CPU clock (phi1 ~455 kHz)"
	@echo "  - Debug pins on J39: Connect logic analyzer to observe"
	@echo ""
	@echo "Debug Header (PMOD J39):"
	@echo "  Pin 1-8:   Data bus D0-D7"
	@echo "  Pin 9-11:  State outputs S0-S2"
	@echo "  Pin 12:    SYNC signal"
	@echo "  Pin 13-14: Phase clocks φ1, φ2"
	@echo "  Pin 15-16: READY, INT signals"
	@echo ""
	@echo "Reusable Components Used:"
	@echo "  - io_controller.vhdl              (generic I/O with INPUT support!)"
	@echo "  - reset_interrupt_controller.vhdl (startup interrupt)"
	@echo "  - memory_controller.vhdl          (ROM/RAM management)"
	@echo "  - debouncer.vhdl                  (button debouncing & edge detection)"
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
