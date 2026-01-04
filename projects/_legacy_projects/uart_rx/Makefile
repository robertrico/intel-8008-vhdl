# Makefile for UART RX Project
# Demonstrates bidirectional UART (TX + RX) with Intel 8008

#==========================================
# Project Configuration
#==========================================
PROJECT_NAME = uart_rx
TOP_ENTITY = uart_rx_top
TB_ENTITY = uart_rx_tb

# Project root directory
PROJECT_ROOT = ../..
WORK_DIR = work

#==========================================
# Simulation Configuration
#==========================================
# Run simulation for 500ms (longer to observe interactive echo with CPU polling)
SIM_STOP_TIME = 500ms

#==========================================
# Source Files
#==========================================
RTL_SOURCES = $(PROJECT_ROOT)/src/components/uart_tx.vhdl \
              $(PROJECT_ROOT)/src/components/uart_rx.vhdl \
              $(PROJECT_ROOT)/src/components/s8008_uart.vhdl \
              $(PROJECT_ROOT)/src/components/interrupt_controller.vhdl \
              $(PROJECT_ROOT)/src/components/io_controller.vhdl \
              $(PROJECT_ROOT)/src/components/memory_controller.vhdl \
              $(PROJECT_ROOT)/src/components/i8008_alu.vhdl \
              $(PROJECT_ROOT)/src/components/s8008.vhdl \
              $(PROJECT_ROOT)/src/components/phase_clocks.vhdl \
              $(PROJECT_ROOT)/src/components/rom_2kx8.vhdl \
              $(PROJECT_ROOT)/src/components/ram_1kx8.vhdl \
              src/uart_rx_top.vhdl

TB_SOURCES = uart_rx_tb.vhdl

#==========================================
# Constraint File Override
#==========================================
# Use project-specific constraint file instead of default
LPF_FILE = $(PROJECT_ROOT)/projects/uart_rx/constraints/uart_rx.lpf

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

# Assemble the uart_rx program
.PHONY: asm
asm:
	@echo "=== Assembling uart_rx.asm ==="
	$(NAKEN_ASM) -I . -l -type hex -o test_programs/uart_rx.hex test_programs/uart_rx.asm
	@echo "✓ Assembly complete"

# Convert to MEM format
.PHONY: hex2mem
hex2mem: asm
	@echo "=== Converting to MEM format ==="
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py test_programs/uart_rx.hex test_programs/uart_rx.mem
	@echo "✓ Generated uart_rx.mem"

# Build everything (assemble program + synthesize FPGA)
.PHONY: project
project: asm hex2mem bitstream

# Full build and program workflow - does everything you need!
.PHONY: deploy
deploy: clean-proj hex2mem bitstream program
	@echo ""
	@echo "========================================="
	@echo "✓ FPGA programmed and ready!"
	@echo "✓ UART transceiver (TX + RX) loaded"
	@echo "✓ Connect FTDI to UART_TX and UART_RX pins"
	@echo "✓ Use minicom for bidirectional communication"
	@echo "========================================="
	@echo ""
	@echo "UART Configuration:"
	@echo "  Baud rate: 9600"
	@echo "  Data bits: 8"
	@echo "  Parity: None"
	@echo "  Stop bits: 1"
	@echo ""
	@echo "Expected Behavior:"
	@echo "  1. Transmits 'Hello, Terminal!'"
	@echo "  2. Waits for user input"
	@echo "  3. Echoes characters as typed"
	@echo "  4. When Enter pressed, responds with 'You said \"[input]\"'"
	@echo ""

# Clean project files
.PHONY: clean-proj
clean-proj: clean
	rm -f test_programs/uart_rx.hex test_programs/uart_rx.lst test_programs/uart_rx.mem
	rm -f build/*

.PHONY: help-proj
help-proj:
	@echo "UART RX Project - Makefile"
	@echo "============================================="
	@echo ""
	@echo "Build Flow:"
	@echo "  1. make asm         - Assemble uart_rx.asm"
	@echo "  2. make hex2mem     - Convert to mem format"
	@echo "  3. make bitstream   - Synthesize for FPGA"
	@echo "  4. make program     - Program FPGA SRAM"
	@echo "  5. make flash       - Program FPGA flash"
	@echo ""
	@echo "Quick Commands:"
	@echo "  make deploy         - Complete workflow: clean, build, and program FPGA"
	@echo "  make all            - Build everything (asm + synthesis)"
	@echo "  make sim            - Run testbench simulation"
	@echo "  make reports        - View timing/utilization"
	@echo "  make clean-proj     - Clean generated files"
	@echo ""
	@echo "Hardware Programming:"
	@echo "  make program        - Quick test (volatile SRAM)"
	@echo "  make flash          - Persistent (survives power cycle)"
	@echo ""
	@echo "Expected Behavior:"
	@echo "  - System transmits 'Hello, Terminal!\\r\\n'"
	@echo "  - Enters interactive mode with prompt '>'"
	@echo "  - Echoes characters as typed"
	@echo "  - When Enter pressed, responds: 'You said \"[input]\"'"
	@echo "  - Repeats with new prompt"
	@echo ""
	@echo "Reusable Components Used:"
	@echo "  - uart_tx.vhdl                    (Generic UART transmitter)"
	@echo "  - uart_rx.vhdl                    (NEW! Generic UART receiver)"
	@echo "  - s8008_uart.vhdl                 (8008-specific UART wrapper with TX+RX)"
	@echo "  - io_controller.vhdl              (Generic I/O)"
	@echo "  - memory_controller.vhdl          (ROM/RAM management)"
	@echo ""
	@echo "I/O Ports:"
	@echo "  IN 0:   UART TX status (bit 0 = tx_busy)"
	@echo "  IN 1:   UART RX data (read clears rx_ready)"
	@echo "  IN 2:   UART RX status (bit 0 = rx_ready)"
	@echo "  OUT 10: UART TX data register"
	@echo ""
	@echo "Minicom Setup:"
	@echo "  minicom -D /dev/tty.usbserial-XXXXXXXX -b 9600"
	@echo ""

# Target to verify constraint file exists
.PHONY: check-constraints
check-constraints:
	@if [ ! -f "$(LPF_FILE)" ]; then \
		echo "Warning: Constraint file not found: $(LPF_FILE)"; \
		echo "You may need to create it for hardware synthesis"; \
	else \
		echo "✓ Constraint file found: $(LPF_FILE)"; \
	fi

# Override bitstream target to check constraints and ensure clean GHDL cache
bitstream: check-constraints
	@echo "Cleaning GHDL cache to ensure fresh ROM data..."
	@rm -rf work/*.o work/*.cf 2>/dev/null || true
	@$(MAKE) hex2mem $(BITSTREAM_FILE)
