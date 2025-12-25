# ============================================================================
# b8008 - Block-based Intel 8008 Implementation
# ============================================================================
# Simple, modular build system for block-based 8008 design
# ============================================================================

# Tools (use oss-cad-suite)
OSS_CAD_SUITE := $(HOME)/oss-cad-suite/bin
GHDL     = $(OSS_CAD_SUITE)/ghdl
YOSYS    = $(OSS_CAD_SUITE)/yosys
NEXTPNR  = $(OSS_CAD_SUITE)/nextpnr-ecp5
ECPPACK  = $(OSS_CAD_SUITE)/ecppack
LOADER   = $(OSS_CAD_SUITE)/openFPGALoader
GHDL_FLAGS = --std=08 --work=work
ASL = ~/Development/asl-current/asl
P2HEX = ~/Development/asl-current/p2hex
HEX2MEM = ./hex_to_mem.py

# FPGA settings (ECP5 - adjust for your board)
DEVICE   := 85k
PACKAGE  := CABGA381
SPEED    := 8

# Directories
SRC_DIR = ./src/b8008
TEST_DIR = ./sim/b8008
BUILD_DIR = ./build/b8008
SYNTH_DIR = ./build/synth
PROG_DIR = ./test_programs

# Synthesis output files
JSON := $(SYNTH_DIR)/b8008.json
CFG  := $(SYNTH_DIR)/b8008.config
BIT  := $(SYNTH_DIR)/b8008.bit
SVF  := $(SYNTH_DIR)/b8008.svf

# All b8008 VHDL source files (order matters for GHDL)
B8008_SRCS = \
	$(SRC_DIR)/b8008_types.vhdl \
	$(SRC_DIR)/program_counter.vhdl \
	$(SRC_DIR)/stack_pointer.vhdl \
	$(SRC_DIR)/stack_memory.vhdl \
	$(SRC_DIR)/stack_addr_mux.vhdl \
	$(SRC_DIR)/stack_addr_decoder.vhdl \
	$(SRC_DIR)/instruction_register.vhdl \
	$(SRC_DIR)/instruction_decoder.vhdl \
	$(SRC_DIR)/condition_flags.vhdl \
	$(SRC_DIR)/register_file.vhdl \
	$(SRC_DIR)/scratchpad_decoder.vhdl \
	$(SRC_DIR)/scratchpad_addr_mux.vhdl \
	$(SRC_DIR)/sss_ddd_selector.vhdl \
	$(SRC_DIR)/ahl_pointer.vhdl \
	$(SRC_DIR)/temp_registers.vhdl \
	$(SRC_DIR)/alu.vhdl \
	$(SRC_DIR)/carry_lookahead.vhdl \
	$(SRC_DIR)/io_buffer.vhdl \
	$(SRC_DIR)/mem_mux_refresh.vhdl \
	./src/components/phase_clocks.vhdl \
	$(SRC_DIR)/state_timing_generator.vhdl \
	$(SRC_DIR)/machine_cycle_control.vhdl \
	$(SRC_DIR)/memory_io_control.vhdl \
	$(SRC_DIR)/register_alu_control.vhdl \
	$(SRC_DIR)/interrupt_ready_ff.vhdl \
	$(SRC_DIR)/b8008.vhdl

.PHONY: all clean assemble assemble-sample test-b8008 test-b8008-top test-serial test-interrupt test-pc test-phase-clocks test-state-timing test-machine-cycle test-instr-decoder test-reg-alu-control test-temp-regs test-carry-lookahead test-alu test-condition-flags test-interrupt-ready test-instr-reg test-io-buffer test-memory-io-control test-ahl-pointer test-scratchpad-decoder test-register-file test-sss-ddd-selector test-stack-pointer test-stack-addr-decoder test-stack-memory help show-programs synth pnr bit prog prog-flash

all: help

help:
	@echo "============================================"
	@echo "b8008 - Block-based Intel 8008"
	@echo "============================================"
	@echo ""
	@echo "FPGA Synthesis:"
	@echo "  make synth                - Synthesize with GHDL+Yosys"
	@echo "  make pnr                  - Place and route (nextpnr-ecp5)"
	@echo "  make bit                  - Generate bitstream"
	@echo "  make prog                 - Program via JTAG (volatile)"
	@echo "  make prog-flash           - Program SPI flash (persistent)"
	@echo ""
	@echo "Assembler:"
	@echo "  make assemble PROG=file.asm      - Assemble test program (in test_programs/)"
	@echo "  make assemble-sample PROG=name   - Assemble sample program (in test_programs/samples/)"
	@echo "  make show-programs               - List available programs"
	@echo ""
	@echo "Integration Tests:"
	@echo "  make test-b8008           - Test b8008 top-level (progressive integration)"
	@echo "  make test-serial PROG=x   - Test serial I/O programs (bitbang UART capture)"
	@echo ""
	@echo "Module Tests:"
	@echo "  make test-pc              - Test program counter"
	@echo "  make test-phase-clocks    - Test phase clocks with SYNC"
	@echo "  make test-state-timing    - Test state timing generator"
	@echo "  make test-machine-cycle   - Test machine cycle control"
	@echo "  make test-instr-decoder   - Test instruction decoder"
	@echo "  make test-reg-alu-control - Test register and ALU control"
	@echo "  make test-temp-regs       - Test temporary registers"
	@echo "  make test-carry-lookahead - Test carry look-ahead logic"
	@echo "  make test-alu             - Test ALU"
	@echo "  make test-condition-flags - Test condition flags and logic"
	@echo "  make test-interrupt-ready - Test interrupt and ready flip-flops"
	@echo "  make test-instr-reg       - Test instruction register"
	@echo "  make test-io-buffer       - Test I/O data buffer"
	@echo "  make test-memory-io-control - Test memory and I/O control"
	@echo "  make test-ahl-pointer     - Test AHL address pointer"
	@echo "  make test-scratchpad-decoder - Test scratchpad decoder"
	@echo "  make test-register-file   - Test register file"
	@echo "  make test-sss-ddd-selector - Test SSS/DDD register selector"
	@echo "  make test-stack-pointer   - Test stack pointer"
	@echo "  make test-stack-addr-decoder - Test stack address decoder"
	@echo "  make test-stack-memory    - Test stack memory"
	@echo "  make clean                - Remove build files"
	@echo ""

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# ============================================================================
# TOP-LEVEL INTEGRATION TEST
# ============================================================================

# Default test program (can be overridden with PROG=name)
PROG ?= alu_test_as
ROM_FILE = test_programs/$(PROG).mem
SIM_TIME ?= 60ms

# CLAUDE - These are the main tests
# Usage:
#   make test-b8008-top                    - Run with default program (alu_test_as)
#   make test-b8008-top PROG=search_as     - Run with search program
#   make test-b8008-top PROG=ram_intensive_as - Run with RAM intensive test
#   make test-b8008-top PROG=search_as SIM_TIME=30ms - Custom simulation time
test-b8008-top: $(BUILD_DIR)
	@echo "========================================="
	@echo "Testing b8008_top - Complete System"
	@echo "Program: $(ROM_FILE)"
	@echo "Sim time: $(SIM_TIME)"
	@echo "========================================="
	@echo ""
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/phase_clocks.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/state_timing_generator.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/interrupt_ready_ff.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/machine_cycle_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/memory_io_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/program_counter.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/ahl_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/mem_mux_refresh.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_addr_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_memory.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/scratchpad_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_file.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/temp_registers.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_alu_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/alu.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/condition_flags.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_register.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/io_buffer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/rom_4kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/legacy/ram_1kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_top.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/b8008_top_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_top_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_top_tb -gROM_FILE=$(ROM_FILE) --stop-time=$(SIM_TIME)

# List available test programs
show-programs:
	@echo "Available test programs:"
	@ls -1 $(PROG_DIR)/*.mem 2>/dev/null | xargs -I {} basename {} .mem | sed 's/^/  /'
	@echo ""
	@echo "Sample programs (serial I/O):"
	@ls -1 $(PROG_DIR)/samples/*.mem 2>/dev/null | xargs -I {} basename {} .mem | sed 's/^/  /' || echo "  (none assembled yet)"
	@echo ""
	@echo "Usage: make test-b8008-top PROG=<program_name>"
	@echo "       make test-serial PROG=<sample_name>"

# ============================================================================
# SERIAL I/O TEST (for sample programs with bitbanged UART)
# ============================================================================
# Runs sample programs that output serial data via bitbanged I/O
# Captures and decodes the serial output in simulation
#
# Usage:
#   make test-serial SERIAL_PROG=mandelbrot                     - Run mandelbrot (30min default)
#   make test-serial SERIAL_PROG=pi SERIAL_TIME_MS=60000        - Run pi for 1 minute
#   make test-serial SERIAL_PROG=mandelbrot SERIAL_TIME_MS=500  - Run mandelbrot for 500ms
#
SERIAL_PROG ?= mandelbrot
SERIAL_ROM = test_programs/samples/$(SERIAL_PROG).mem
SERIAL_TIME_MS ?= 1800000
START_ADDR ?= 64

test-serial: $(BUILD_DIR)
	@echo "========================================="
	@echo "Testing Serial I/O Program"
	@echo "Program: $(SERIAL_ROM)"
	@echo "Sim time: $(SERIAL_TIME_MS)ms"
	@echo "========================================="
	@echo ""
	@if [ ! -f "$(SERIAL_ROM)" ]; then \
		echo "ERROR: $(SERIAL_ROM) not found!"; \
		echo "First assemble the program:"; \
		echo "  make assemble-sample PROG=$(SERIAL_PROG)"; \
		exit 1; \
	fi
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/phase_clocks.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/state_timing_generator.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/interrupt_ready_ff.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/machine_cycle_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/memory_io_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/program_counter.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/ahl_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/mem_mux_refresh.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_addr_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_memory.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/scratchpad_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_file.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/temp_registers.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_alu_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/alu.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/condition_flags.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_register.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/io_buffer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/rom_4kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/ram_4kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/serial_capture.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/b8008_serial_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_serial_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_serial_tb -gROM_FILE=$(SERIAL_ROM) -gSTART_ADDR=$(START_ADDR) -gRUN_TIME_MS=$(SERIAL_TIME_MS)

# ============================================================================
# INDIVIDUAL MODULE TESTS
# ============================================================================

# CLAUDE - When testing instructions, we should have make file commands to help us test specific files
# NOT run the whole suite everytime.

# Interrupt test with dedicated testbench
test-interrupt: $(BUILD_DIR)
	@echo "========================================="
	@echo "Testing Interrupt Handling"
	@echo "Program: test_programs/interrupt_test_as.mem"
	@echo "========================================="
	@echo ""
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/phase_clocks.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/state_timing_generator.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/interrupt_ready_ff.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/machine_cycle_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/memory_io_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/program_counter.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/ahl_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/mem_mux_refresh.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_addr_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_memory.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/scratchpad_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_file.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/temp_registers.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_alu_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/alu.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/condition_flags.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_register.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/io_buffer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/rom_4kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/legacy/ram_1kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_top.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/interrupt_test_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) interrupt_test_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) interrupt_test_tb --stop-time=10ms

test-pc: $(BUILD_DIR)
	@echo "Testing program counter..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/program_counter.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/program_counter_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) program_counter_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) program_counter_tb --stop-time=1us

test-phase-clocks: $(BUILD_DIR)
	@echo "Testing phase clocks with SYNC..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/phase_clocks.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./sim/units/phase_clocks_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) phase_clocks_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) phase_clocks_tb --stop-time=30us

test-state-timing: $(BUILD_DIR)
	@echo "Testing state timing generator..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/state_timing_generator.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/state_timing_generator_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) state_timing_generator_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) state_timing_generator_tb --stop-time=10us

test-machine-cycle: $(BUILD_DIR)
	@echo "Testing machine cycle control..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/machine_cycle_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/machine_cycle_control_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) machine_cycle_control_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) machine_cycle_control_tb --stop-time=10us

test-instr-decoder: $(BUILD_DIR)
	@echo "Testing instruction decoder..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/instruction_decoder_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) instruction_decoder_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) instruction_decoder_tb --stop-time=10us

test-reg-alu-control: $(BUILD_DIR)
	@echo "Testing register and ALU control..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_alu_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/register_alu_control_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) register_alu_control_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) register_alu_control_tb --stop-time=10us

test-temp-regs: $(BUILD_DIR)
	@echo "Testing temporary registers..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/temp_registers.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/temp_registers_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) temp_registers_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) temp_registers_tb --stop-time=10us

test-carry-lookahead: $(BUILD_DIR)
	@echo "Testing carry look-ahead..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/carry_lookahead.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/carry_lookahead_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) carry_lookahead_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) carry_lookahead_tb --stop-time=10us

test-alu: $(BUILD_DIR)
	@echo "Testing ALU..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/alu.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/alu_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) alu_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) alu_tb --stop-time=10us

test-condition-flags: $(BUILD_DIR)
	@echo "Testing condition flags..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/condition_flags.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/condition_flags_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) condition_flags_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) condition_flags_tb --stop-time=10us

test-interrupt-ready: $(BUILD_DIR)
	@echo "Testing interrupt and ready flip-flops..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/interrupt_ready_ff.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/interrupt_ready_ff_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) interrupt_ready_ff_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) interrupt_ready_ff_tb --stop-time=10us

test-instr-reg: $(BUILD_DIR)
	@echo "Testing instruction register..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_register.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/instruction_register_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) instruction_register_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) instruction_register_tb --stop-time=10us

test-io-buffer: $(BUILD_DIR)
	@echo "Testing I/O buffer..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/io_buffer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/io_buffer_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) io_buffer_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) io_buffer_tb --stop-time=10us

test-memory-io-control: $(BUILD_DIR)
	@echo "Testing memory and I/O control..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/memory_io_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/memory_io_control_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) memory_io_control_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) memory_io_control_tb --stop-time=10us

test-ahl-pointer: $(BUILD_DIR)
	@echo "Testing AHL address pointer..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/ahl_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/ahl_pointer_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ahl_pointer_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ahl_pointer_tb --stop-time=10us

test-scratchpad-decoder: $(BUILD_DIR)
	@echo "Testing scratchpad decoder..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/scratchpad_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/scratchpad_decoder_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) scratchpad_decoder_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) scratchpad_decoder_tb --stop-time=10us

test-register-file: $(BUILD_DIR)
	@echo "Testing register file..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_file.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/register_file_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) register_file_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) register_file_tb --stop-time=10us

test-stack-pointer: $(BUILD_DIR)
	@echo "Testing stack pointer..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/stack_pointer_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) stack_pointer_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) stack_pointer_tb --stop-time=20us

test-stack-addr-decoder: $(BUILD_DIR)
	@echo "Testing stack address decoder..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_addr_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/stack_addr_decoder_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) stack_addr_decoder_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) stack_addr_decoder_tb --stop-time=10us

test-stack-memory: $(BUILD_DIR)
	@echo "Testing stack memory..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_memory.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/stack_memory_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) stack_memory_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) stack_memory_tb --stop-time=10us

test-sss-ddd-selector: $(BUILD_DIR)
	@echo "Testing SSS/DDD selector..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/sss_ddd_selector.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/sss_ddd_selector_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) sss_ddd_selector_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) sss_ddd_selector_tb --stop-time=10us

# ============================================================================
# ASSEMBLER
# ============================================================================

# Assemble a program and generate .hex and .mem files
# Usage: make assemble PROG=search_as.asm
#    or: make assemble search_as.asm
assemble:
	@if [ -z "$(PROG)" ]; then \
		if [ -n "$(filter %.asm,$(MAKECMDGOALS))" ]; then \
			PROG_FILE="$(filter %.asm,$(MAKECMDGOALS))"; \
		else \
			echo "Error: Please specify a program file"; \
			echo "Usage: make assemble PROG=filename.asm"; \
			echo "   or: make assemble filename.asm"; \
			exit 1; \
		fi; \
	else \
		PROG_FILE="$(PROG)"; \
	fi; \
	BASENAME=$$(basename $$PROG_FILE .asm); \
	echo "========================================="; \
	echo "Assembling $$PROG_FILE"; \
	echo "========================================="; \
	cd $(PROG_DIR) && \
	$(ASL) -cpu 8008new -L $$BASENAME.asm && \
	$(P2HEX) $$BASENAME.p $$BASENAME.hex -r 0-4095 && \
	python3 ../$(HEX2MEM) $$BASENAME.hex $$BASENAME.mem && \
	echo "" && \
	echo "Output files created:" && \
	echo "  $(PROG_DIR)/$$BASENAME.lst - Assembly listing" && \
	echo "  $(PROG_DIR)/$$BASENAME.hex - Intel HEX format" && \
	echo "  $(PROG_DIR)/$$BASENAME.mem - Memory initialization file"

# Allow using the .asm filename as a target
%.asm:
	@:

# ============================================================================
# SAMPLE PROGRAM ASSEMBLER
# ============================================================================
# Assemble sample programs (in test_programs/samples/) that may need includes
# Usage: make assemble-sample PROG=mandelbrot
#        make assemble-sample PROG=pi
#        make assemble-sample PROG=stars
#
# These programs use bitbanged serial I/O and may require ASL include files
ASL_INCLUDE = ~/Development/asl-current/include
SAMPLE_DIR = $(PROG_DIR)/samples

assemble-sample:
	@if [ -z "$(PROG)" ]; then \
		echo "Error: Please specify a sample program"; \
		echo "Usage: make assemble-sample PROG=mandelbrot"; \
		echo ""; \
		echo "Available samples:"; \
		ls -1 $(SAMPLE_DIR)/*.asm 2>/dev/null | xargs -I {} basename {} .asm | sed 's/^/  /' || echo "  (none)"; \
		exit 1; \
	fi; \
	BASENAME=$(PROG); \
	echo "========================================="; \
	echo "Assembling sample: $$BASENAME.asm"; \
	echo "========================================="; \
	cd $(SAMPLE_DIR) && \
	$(ASL) -cpu 8008new -i $(ASL_INCLUDE) -L $$BASENAME.asm && \
	$(P2HEX) $$BASENAME.p $$BASENAME.hex -r 0-4095 && \
	python3 ../../$(HEX2MEM) $$BASENAME.hex $$BASENAME.mem && \
	echo "" && \
	echo "Output files created:" && \
	echo "  $(SAMPLE_DIR)/$$BASENAME.lst - Assembly listing" && \
	echo "  $(SAMPLE_DIR)/$$BASENAME.hex - Intel HEX format" && \
	echo "  $(SAMPLE_DIR)/$$BASENAME.mem - Memory initialization file"

# ============================================================================
# FPGA SYNTHESIS
# ============================================================================
# Uses GHDL to synthesize VHDL -> Verilog, then Yosys for ECP5 synthesis
# This avoids the broken GHDL-Yosys plugin on macOS

$(SYNTH_DIR):
	@mkdir -p $(SYNTH_DIR)

# Synthesize with GHDL+Yosys
synth: $(JSON)

# Step 1: Analyze all VHDL sources
.PHONY: analyze
analyze: | $(SYNTH_DIR)
	@echo "=== Analyzing VHDL sources ==="
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(SYNTH_DIR) $(B8008_SRCS)

# Step 2: GHDL synth to Verilog (the key: --out=verilog)
$(SYNTH_DIR)/b8008.v: $(B8008_SRCS) | $(SYNTH_DIR)
	@echo "=== Synthesizing b8008 with GHDL ==="
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(SYNTH_DIR) $(B8008_SRCS)
	$(GHDL) --synth $(GHDL_FLAGS) --workdir=$(SYNTH_DIR) --out=verilog b8008 > $@
	@echo "Verilog output: $@"
	@wc -l $@

# Step 3: Yosys synthesis for ECP5 (reads Verilog, no plugin needed)
# Note: GHDL generates gate_mdff/gate_midff primitives for multi-edge detection
#       Include the gate primitive definitions from src/synth/ghdl_gates.v
$(JSON): $(SYNTH_DIR)/b8008.v
	@echo "=== Running Yosys synthesis for ECP5 ==="
	$(YOSYS) -p "read_verilog ./src/synth/ghdl_gates.v $<; synth_ecp5 -top b8008 -json $@" 2>&1 | tee $(SYNTH_DIR)/synth.log
	@echo ""
	@echo "Synthesis complete: $@"
	@grep -E "Number of cells|LUT|DFF|CARRY|MULT" $(SYNTH_DIR)/synth.log || true

# Place and route with nextpnr
pnr: $(CFG)

$(CFG): $(JSON)
	@echo "=== Place & Route with nextpnr-ecp5 ==="
	@if [ ! -f "$(JSON)" ]; then \
		echo "ERROR: $(JSON) not found. Run 'make synth' first."; \
		exit 1; \
	fi
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --speed $(SPEED) \
		--json $(JSON) --textcfg $@ \
		--timing-allow-fail
	@echo "Place & route complete: $@"

# Generate bitstream
bit: $(BIT)

$(BIT): $(CFG)
	@echo "=== Generating Bitstream ==="
	$(ECPPACK) --input $< --bit $@ --svf $(SVF)
	@echo "Bitstream ready: $@"

# Program via JTAG (volatile - lost on power cycle)
prog: $(BIT)
	@echo "=== Programming via JTAG (SRAM) ==="
	$(LOADER) $(BIT)

# Program SPI flash (persistent)
prog-flash: $(BIT)
	@echo "=== Programming SPI Flash ==="
	$(LOADER) -f $(BIT)

# ============================================================================
# CLEANUP
# ============================================================================

clean:
	@rm -rf $(BUILD_DIR) $(SYNTH_DIR)
	@rm -f *.cf *.o work-obj*.cf
