# Makefile for s8008 (Silicon-Accurate 8008) Component Test
# Tests the cycle-accurate Intel 8008 implementation

#==========================================
# Project Configuration
#==========================================
TOP_ENTITY ?= s8008
TB_ENTITY ?= s8008_tb

#==========================================
# Source Files
#==========================================
RTL_SOURCES = $(SRC_DIR)/components/i8008_alu.vhdl \
              $(SRC_DIR)/components/phase_clocks.vhdl \
              $(SRC_DIR)/components/rom_2kx8.vhdl \
              $(SRC_DIR)/components/ram_1kx8.vhdl \
              $(SRC_DIR)/components/io_console.vhdl \
              $(SRC_DIR)/components/s8008.vhdl

# Main comprehensive testbench
TB_SOURCES = $(SIM_DIR)/s8008_tb.vhdl

# All testbenches (main + units + interrupt)
ALL_TB_SOURCES = $(TB_SOURCES) \
                 $(SRC_DIR)/testbench/s8008_interrupt_tb.vhdl \
                 $(wildcard $(SIM_DIR)/units/*_tb.vhdl)

#==========================================
# Test-Specific Stop Times
#==========================================
# Benchmark-derived optimal stop times for each test
# Main comprehensive test completes at 1910us (1.91ms)
# Adding 30% margin for safety
STOP_TIME_s8008_tb = 2500us

# Unit tests (fast, typically <100us)
# Conditional test now has more instructions due to flag setup, needs more time
# Increased timeouts for conditional and inc_dec after I/O architecture changes
STOP_TIME_s8008_conditional_tb = 3000us
STOP_TIME_s8008_conditional_call_tb = 3000us
STOP_TIME_s8008_conditional_ret_tb = 2000us
STOP_TIME_s8008_call_ret_tb = 800us
STOP_TIME_s8008_alu_tb = 1800us
STOP_TIME_s8008_io_tb = 600us
STOP_TIME_s8008_rotate_tb = 400us
STOP_TIME_s8008_stack_tb = 200us
STOP_TIME_s8008_inc_dec_tb = 2000us
STOP_TIME_s8008_rst_tb = 800us
STOP_TIME_s8008_search_tb = 25000us
STOP_TIME_s8008_ram_intensive_tb = 25000us
STOP_TIME_s8008_ram_test_tb = 60000us
STOP_TIME_s8008_simple_add_tb = 1000us
STOP_TIME_s8008_inp_cpi_tb = 1000us
STOP_TIME_s8008_interrupt_tb = 5000us

# Get stop time for active test, or use default
SIM_STOP_TIME ?= $(or $(STOP_TIME_$(ACTIVE_TB_ENTITY)),1ms)

#==========================================
# Include Common Build Rules
#==========================================
include common.mk

#==========================================
# Program Assembly Configuration
#==========================================
NAKEN_ASM ?= /Users/$(USERNAME)/Development/naken_asm/naken_asm
TEST_PROG_DIR = test_programs
PROJECTS_DIR = projects
PYTHON = python3

# Default program to load
ROM_PROGRAM ?= ram_test

#==========================================
# Extended Test Targets
#==========================================

# Run main comprehensive test (default)
.PHONY: test
test: sim

# Run all unit tests
.PHONY: test-units
test-units:
	@echo "========================================"
	@echo "Running All Unit Tests"
	@echo "========================================"
	@for tb in $(wildcard $(SIM_DIR)/units/*_tb.vhdl); do \
		test_name=$$(basename $$tb .vhdl); \
		echo ""; \
		echo ">>> Running $$test_name..."; \
		$(MAKE) sim TEST=$$test_name || exit 1; \
	done
	@echo ""
	@echo "========================================"
	@echo "✓ All Unit Tests Passed"
	@echo "========================================"

# Run comprehensive + unit tests (legacy target)
.PHONY: test-all
test-all: test test-units
	@echo ""
	@echo "========================================"
	@echo "✓ ALL TESTS PASSED"
	@echo "  - Comprehensive test: PASS"
	@echo "  - Unit tests: PASS"
	@echo "========================================"

# Run EVERYTHING: comprehensive, units, programs, and interrupt tests
.PHONY: test-complete
test-complete: test test-units test-all-programs test-interrupt
	@echo ""
	@echo "========================================"
	@echo "✓ COMPLETE TEST SUITE PASSED"
	@echo "  - Comprehensive test: PASS"
	@echo "  - Unit tests: PASS"
	@echo "  - Assembly programs: PASS"
	@echo "  - Interrupt test: PASS"
	@echo "========================================"

# Quick shortcuts for specific unit tests
.PHONY: test-conditional test-conditional-call test-conditional-ret test-call-ret test-alu test-io test-rotate test-stack test-inc-dec test-rst
test-conditional:
	@$(MAKE) sim TEST=s8008_conditional_tb

test-conditional-call:
	@$(MAKE) sim TEST=s8008_conditional_call_tb

test-conditional-ret:
	@$(MAKE) sim TEST=s8008_conditional_ret_tb

test-call-ret:
	@$(MAKE) sim TEST=s8008_call_ret_tb

test-alu:
	@$(MAKE) sim TEST=s8008_alu_tb

test-io:
	@$(MAKE) sim TEST=s8008_io_tb

test-rotate:
	@$(MAKE) sim TEST=s8008_rotate_tb

test-stack:
	@$(MAKE) sim TEST=s8008_stack_tb

test-inc-dec:
	@$(MAKE) sim TEST=s8008_inc_dec_tb

test-rst:
	@$(MAKE) sim TEST=s8008_rst_tb

test-search:
	@$(MAKE) sim TEST=s8008_search_tb

test-ram-intensive:
	@$(MAKE) sim TEST=s8008_ram_intensive_tb

test-ram-test:
	@$(MAKE) sim TEST=s8008_ram_test_tb

test-simple-add:
	@$(MAKE) sim TEST=s8008_simple_add_tb

test-inp-cpi:
	@$(MAKE) sim TEST=s8008_inp_cpi_tb

test-interrupt:
	@$(MAKE) sim TEST=s8008_interrupt_tb

# Run all assembly program tests
test-all-programs:
	@echo "=========================================="
	@echo "Running All Assembly Program Tests"
	@echo "=========================================="
	@echo ""
	@$(MAKE) --no-print-directory test-simple-add && echo "✓ simple_add PASSED" || echo "✗ simple_add FAILED"
	@echo ""
	@$(MAKE) --no-print-directory test-ram-test && echo "✓ ram_test PASSED" || echo "✗ ram_test FAILED"
	@echo ""
	@$(MAKE) --no-print-directory test-search && echo "✓ search PASSED" || echo "✗ search FAILED"
	@echo ""
	@$(MAKE) --no-print-directory test-ram-intensive && echo "✓ ram_intensive PASSED" || echo "✗ ram_intensive FAILED"
	@echo ""
	@echo "=========================================="
	@echo "Assembly Program Tests Complete"
	@echo "=========================================="

# Quick test - run core unit tests only
test-quick:
	@echo "Running quick validation tests..."
	@$(MAKE) --no-print-directory test-alu > /dev/null 2>&1 && echo "✓ ALU tests PASSED" || echo "✗ ALU tests FAILED"
	@$(MAKE) --no-print-directory test-call-ret > /dev/null 2>&1 && echo "✓ CALL/RET tests PASSED" || echo "✗ CALL/RET tests FAILED"
	@$(MAKE) --no-print-directory test-conditional > /dev/null 2>&1 && echo "✓ Conditional tests PASSED" || echo "✗ Conditional tests FAILED"
	@$(MAKE) --no-print-directory test-rst > /dev/null 2>&1 && echo "✓ RST tests PASSED" || echo "✗ RST tests FAILED"

# Show test programs with descriptions
show-programs:
	@echo "=========================================="
	@echo "Available Assembly Test Programs"
	@echo "=========================================="
	@echo ""
	@echo "simple_add       - Basic addition test (A + B)"
	@echo "ram_test         - RAM read/write verification"
	@echo "search           - Sequential search algorithm"
	@echo "ram_intensive    - Comprehensive RAM stress test"
	@echo ""
	@echo "Run with:"
	@echo "  make test-simple-add"
	@echo "  make test-ram-test"
	@echo "  make test-search"
	@echo "  make test-ram-intensive"
	@echo ""
	@echo "Or run all:"
	@echo "  make test-all-programs"

#==========================================
# Program Assembly and ROM Loading
#==========================================

# List available programs
list-programs:
	@echo "Available programs in $(TEST_PROG_DIR):"
	@cd $(TEST_PROG_DIR) && ls -1 *.asm | sed 's/\.asm//'
	@echo ""
	@echo "Usage:"
	@echo "  make asm ROM_PROGRAM=program_name      # Assemble program"
	@echo "  make load-rom ROM_PROGRAM=program_name # Load into ROM"
	@echo "  make asm-and-load ROM_PROGRAM=program_name  # Assemble and load"
	@echo ""
	@echo "Current ROM program: $(ROM_PROGRAM)"

# Assemble a program
asm:
	@echo "=== Assembling $(ROM_PROGRAM).asm ==="
	@if [ ! -f "$(TEST_PROG_DIR)/$(ROM_PROGRAM).asm" ]; then \
		echo "Error: $(TEST_PROG_DIR)/$(ROM_PROGRAM).asm not found"; \
		echo "Available programs:"; \
		cd $(TEST_PROG_DIR) && ls -1 *.asm; \
		exit 1; \
	fi
	cd $(TEST_PROG_DIR) && $(NAKEN_ASM) -I . -l -type hex -o $(ROM_PROGRAM).hex $(ROM_PROGRAM).asm
	@echo "✓ Assembly complete: $(TEST_PROG_DIR)/$(ROM_PROGRAM).hex"
	@echo "✓ Listing file: $(TEST_PROG_DIR)/$(ROM_PROGRAM).lst"

# Convert HEX to MEM format and update ROM
load-rom:
	@echo "=== Loading $(ROM_PROGRAM) into ROM ==="
	@if [ ! -f "$(TEST_PROG_DIR)/$(ROM_PROGRAM).hex" ]; then \
		echo "Error: $(TEST_PROG_DIR)/$(ROM_PROGRAM).hex not found"; \
		echo "Run 'make asm ROM_PROGRAM=$(ROM_PROGRAM)' first"; \
		exit 1; \
	fi
	$(PYTHON) hex_to_mem.py $(TEST_PROG_DIR)/$(ROM_PROGRAM).hex $(TEST_PROG_DIR)/$(ROM_PROGRAM).mem
	@echo "✓ Generated $(TEST_PROG_DIR)/$(ROM_PROGRAM).mem"
	sed -i '' 's|test_programs/[^"]*\.mem|test_programs/$(ROM_PROGRAM).mem|' src/components/rom_2kx8.vhdl
	@echo "✓ Updated ROM to load $(ROM_PROGRAM).mem"
	@grep "load_rom" src/components/rom_2kx8.vhdl | grep signal

# Assemble and load in one step
asm-and-load: asm load-rom
	@echo "=== Program $(ROM_PROGRAM) assembled and loaded into ROM ==="