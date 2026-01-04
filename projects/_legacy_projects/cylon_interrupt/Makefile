# Makefile for Interrupt-Driven Cylon LED Effect Project
# Demonstrates generic interrupt_controller with Intel 8008

#==========================================
# Project Configuration
#==========================================
PROJECT_NAME = cylon_interrupt
TOP_ENTITY = cylon_interrupt_top
TB_ENTITY = cylon_interrupt_tb

# Project root directory
PROJECT_ROOT = ../..
WORK_DIR = work

#==========================================
# Simulation Configuration
#==========================================
# Run simulation for 100ms (interrupt-driven, longer observation time)
SIM_STOP_TIME = 100ms

#==========================================
# Source Files
#==========================================
RTL_SOURCES = $(PROJECT_ROOT)/src/components/interrupt_controller.vhdl \
              $(PROJECT_ROOT)/src/components/io_controller.vhdl \
              $(PROJECT_ROOT)/src/components/memory_controller.vhdl \
              $(PROJECT_ROOT)/src/components/debouncer.vhdl \
              $(PROJECT_ROOT)/src/components/i8008_alu.vhdl \
              $(PROJECT_ROOT)/src/components/s8008.vhdl \
              $(PROJECT_ROOT)/src/components/phase_clocks.vhdl \
              $(PROJECT_ROOT)/src/components/rom_2kx8.vhdl \
              $(PROJECT_ROOT)/src/components/ram_1kx8.vhdl \
              src/cylon_interrupt_top.vhdl

TB_SOURCES = cylon_interrupt_tb.vhdl

#==========================================
# Constraint File Override
#==========================================
# Use project-specific constraint file instead of default
LPF_FILE = $(PROJECT_ROOT)/projects/cylon_interrupt/constraints/cylon_interrupt.lpf

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

# Assemble the cylon_interrupt program
.PHONY: asm
asm:
	@echo "=== Assembling cylon_interrupt.asm ==="
	$(NAKEN_ASM) -I . -l -type hex -o test_programs/cylon_interrupt.hex test_programs/cylon_interrupt.asm
	@echo "✓ Assembly complete"

# Convert to MEM format
.PHONY: hex2mem
hex2mem: asm
	@echo "=== Converting to MEM format ==="
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py test_programs/cylon_interrupt.hex test_programs/cylon_interrupt.mem
	@echo "✓ Generated cylon_interrupt.mem"

# Build everything (assemble program + synthesize FPGA)
.PHONY: all
all: asm hex2mem bitstream

# Full build and program workflow - does everything you need!
.PHONY: deploy
deploy: clean-proj hex2mem bitstream program
	@echo ""
	@echo "========================================="
	@echo "✓ FPGA programmed and ready!"
	@echo "✓ Interrupt-driven Cylon LED effect loaded"
	@echo "✓ Press button on A18 to trigger interrupt"
	@echo "========================================="
	@echo ""
	@echo "Interrupt Architecture:"
	@echo "  RST 0 (0x000): Startup interrupt"
	@echo "  RST 1 (0x008): Button interrupt"
	@echo ""

# Clean project files
.PHONY: clean-proj
clean-proj: clean
	rm -f test_programs/cylon_interrupt.hex test_programs/cylon_interrupt.lst test_programs/cylon_interrupt.mem
	rm -f build/*

.PHONY: help-proj
help-proj:
	@echo "Interrupt-Driven Cylon LED Effect - Makefile"
	@echo "============================================="
	@echo ""
	@echo "Build Flow:"
	@echo "  1. make asm         - Assemble cylon_interrupt.asm"
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
	@echo "  - System initializes via startup interrupt (RST 0)"
	@echo "  - Single LED shows current position"
	@echo "  - Each button press triggers interrupt (RST 1)"
	@echo "  - ISR advances pattern one step"
	@echo "  - Pattern: LED0 -> LED1 -> ... -> LED7 -> LED6 -> ... -> LED0"
	@echo "  - Button is active-low with pull-up (press = 0, release = 1)"
	@echo "  - Hardware debouncing at CPU clock (phi1 ~455 kHz)"
	@echo ""
	@echo "Interrupt Controller Features:"
	@echo "  - 2 interrupt sources (startup, button)"
	@echo "  - Priority encoding (startup > button)"
	@echo "  - Software-controlled masking (OUT 9)"
	@echo "  - Status registers (INP 1, INP 2)"
	@echo "  - Edge-triggered button input"
	@echo ""
	@echo "Debug Header (PMOD J39):"
	@echo "  Pin 1-8:   Data bus D0-D7"
	@echo "  Pin 9-11:  State outputs S0-S2"
	@echo "  Pin 12:    SYNC signal"
	@echo "  Pin 13-14: Phase clocks φ1, φ2"
	@echo "  Pin 15-16: READY, INT signals"
	@echo ""
	@echo "Reusable Components Used:"
	@echo "  - interrupt_controller.vhdl       (NEW! Generic multi-source interrupt)"
	@echo "  - io_controller.vhdl              (Generic I/O with interrupt support)"
	@echo "  - memory_controller.vhdl          (ROM/RAM management)"
	@echo "  - debouncer.vhdl                  (Button debouncing & edge detection)"
	@echo ""
	@echo "I/O Ports:"
	@echo "  OUT 8:  LED bank (8 bits, active-low)"
	@echo "  OUT 9: Interrupt mask register"
	@echo "  INP 1:  Interrupt status register"
	@echo "  INP 2:  Active interrupt source"
	@echo ""

# Target to verify constraint file exists
.PHONY: check-constraints
check-constraints:
	@if [ ! -f "$(LPF_FILE)" ]; then \
		echo "Error: Constraint file not found: $(LPF_FILE)"; \
		exit 1; \
	fi
	@echo "✓ Constraint file found: $(LPF_FILE)"

# Override bitstream target to check constraints and ensure clean GHDL cache
bitstream: check-constraints
	@echo "Cleaning GHDL cache to ensure fresh ROM data..."
	@rm -rf work/*.o work/*.cf 2>/dev/null || true
	@$(MAKE) hex2mem $(BITSTREAM_FILE)
