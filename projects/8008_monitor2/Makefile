# Makefile for Intel 8008 Monitor Project
# Comprehensive monitor with UART, interrupts, and debugging tools

#==========================================
# Project Configuration
#==========================================
PROJECT_NAME = 8008_monitor2
TOP_ENTITY = monitor_top
TB_ENTITY = monitor_tb

# Project root directory
PROJECT_ROOT = ../..
WORK_DIR = work

#==========================================
# Simulation Configuration
#==========================================
# Run simulation for 1000ms (longer to observe interactive echo with CPU polling)
SIM_STOP_TIME = 1000ms

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
              $(PROJECT_ROOT)/src/components/rom_4kx8.vhdl \
              $(PROJECT_ROOT)/src/components/ram_1kx8.vhdl \
              src/monitor_top.vhdl

TB_SOURCES = monitor_tb.vhdl

#==========================================
# Constraint File Override
#==========================================
# Use project-specific constraint file instead of default
LPF_FILE = $(PROJECT_ROOT)/projects/8008_monitor2/constraints/monitor.lpf

#==========================================
# Program Assembly Configuration
#==========================================
# Import assembler paths from root Makefile
AS_ASM ?= /Users/${USERNAME}/Development/as_assembler/asl
P2HEX ?= /Users/${USERNAME}/Development/as_assembler/p2hex
P2BIN ?= /Users/${USERNAME}/Development/as_assembler/p2bin
AS_INCLUDE ?= /Users/${USERNAME}/Development/as_assembler/include
PYTHON = python3

#==========================================
# Include Common Build Rules
#==========================================
include $(PROJECT_ROOT)/common.mk

#==========================================
# Project-Specific Targets
#==========================================

# Assemble the monitor program with AS assembler
.PHONY: asm
asm:
	@echo "=== Assembling monitor.asm with AS ==="
	cd test_programs && $(AS_ASM) -cpu 8008new -i $(AS_INCLUDE) -o monitor.p -L monitor.asm
	@echo "=== Converting to Intel HEX ==="
	cd test_programs && $(P2HEX) monitor.p monitor.hex -F Intel
	@echo "✓ Assembly complete"

# Assemble simple UART test (keeping for compatibility, but AS is now default)
.PHONY: asm-test
asm-test:
	@echo "=== Assembling simple_uart_test.asm with AS ==="
	cd test_programs && $(AS_ASM) -cpu 8008new -i $(AS_INCLUDE) -o simple_uart_test.p -L simple_uart_test.asm
	@echo "=== Converting to Intel HEX ==="
	cd test_programs && $(P2HEX) simple_uart_test.p simple_uart_test.hex -F Intel
	@echo "✓ Test assembly complete"

# Convert monitor to MEM format
.PHONY: hex2mem
hex2mem: asm
	@echo "=== Converting monitor to MEM format ==="
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py test_programs/monitor.hex test_programs/monitor.mem
	@echo "✓ Generated monitor.mem"

# Convert simple test to MEM format
.PHONY: hex2mem-test
hex2mem-test: asm-test
	@echo "=== Converting simple test to MEM format ==="
	$(PYTHON) $(PROJECT_ROOT)/hex_to_mem.py test_programs/simple_uart_test.hex test_programs/simple_uart_test.mem
	@echo "✓ Generated simple_uart_test.mem"

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
	rm -f test_programs/monitor.hex test_programs/monitor.lst test_programs/monitor.mem test_programs/monitor.p
	rm -f test_programs/simple_uart_test.hex test_programs/simple_uart_test.lst test_programs/simple_uart_test.mem test_programs/simple_uart_test.p
	rm -f build/*

.PHONY: help-proj
help-proj:
	@echo "Intel 8008 Monitor Project - Makefile"
	@echo "============================================="
	@echo ""
	@echo "Build Flow:"
	@echo "  1. make asm         - Assemble monitor.asm"
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
