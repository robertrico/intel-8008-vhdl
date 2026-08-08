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
# Overridable so CI can point at its own build (see .github/actions/setup-asl)
ASL ?= ~/Development/asl-current/asl
P2HEX ?= ~/Development/asl-current/p2hex
HEX2MEM = ./hex_to_mem.py

# FPGA settings (ECP5-5G Versa LFE5UM5G-45F)
DEVICE   := um5g-45k
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
	$(SRC_DIR)/stack_pointer.vhdl \
	$(SRC_DIR)/stack_memory.vhdl \
	$(SRC_DIR)/stack_addr_mux.vhdl \
	$(SRC_DIR)/instruction_register.vhdl \
	$(SRC_DIR)/instruction_decoder.vhdl \
	$(SRC_DIR)/condition_flags.vhdl \
	$(SRC_DIR)/register_file.vhdl \
	$(SRC_DIR)/scratchpad_decoder.vhdl \
	$(SRC_DIR)/scratchpad_addr_mux.vhdl \
	$(SRC_DIR)/sss_ddd_selector.vhdl \
	$(SRC_DIR)/ahl_pointer.vhdl \
	$(SRC_DIR)/temp_registers.vhdl \
	$(SRC_DIR)/carry_lookahead.vhdl \
	$(SRC_DIR)/alu.vhdl \
	$(SRC_DIR)/io_buffer.vhdl \
	$(SRC_DIR)/mem_mux_refresh.vhdl \
	./src/components/phase_clocks.vhdl \
	$(SRC_DIR)/state_timing_generator.vhdl \
	$(SRC_DIR)/machine_cycle_control.vhdl \
	$(SRC_DIR)/memory_io_control.vhdl \
	$(SRC_DIR)/register_alu_control.vhdl \
	$(SRC_DIR)/interrupt_ready_ff.vhdl \
	$(SRC_DIR)/b8008.vhdl

# Core selector for simulation: rtl (default) analyzes the b8008 sources,
# netlist analyzes the write_vhdl round-trip instead (issue #235 validation).
# Propagates from the environment, so verification scripts work unchanged:
#   B8008_CORE=netlist ./test_programs/verification_scripts/run_all_tests.sh
B8008_CORE ?= rtl

# READY/WAIT stress mode for test-b8008-top (b8008_top_tb generic):
# repeated READY drops + one long park; used by check_ready_wait_test.sh.
READY_STRESS ?= false
ifeq ($(B8008_CORE),netlist)
# b8008_types must be analyzed explicitly: b8008_top's use clause needs it,
# and the netlist branch doesn't pull in B8008_SRCS (a warm build/ dir from
# a prior rtl run masks this; a cold checkout - CI - fails without it).
CORE_SIM_SRCS = $(SRC_DIR)/b8008_types.vhdl $(NETLIST_VHDL) $(TEST_DIR)/b8008_netlist_shim.vhdl
else
CORE_SIM_SRCS = $(B8008_SRCS)
endif

# Unit-test targets are declared phony via $(UNIT_TESTS) below.
.PHONY: all clean assemble assemble-sample test-b8008 test-b8008-top test-b8008-extram test-serial test-interrupt test-bitbang-uart help show-programs synth pnr bit prog prog-flash

all: help

help:
	@echo "============================================"
	@echo "b8008 - Block-based Intel 8008"
	@echo "============================================"
	@echo ""
	@echo "FPGA Projects:"
	@echo "  make project P=blinky     - Build FPGA project (in projects/blinky/)"
	@echo "  make project P=blinky T=synth  - Run specific target"
	@echo "  (Available targets: assemble, synth, pnr, bit, prog, clean)"
	@echo ""
	@echo "Core Synthesis (CPU only):"
	@echo "  make synth                - Synthesize with GHDL+Yosys"
	@echo "  make pnr                  - Place and route (nextpnr-ecp5)"
	@echo "  make bit                  - Generate bitstream"
	@echo "  make prog                 - Program via JTAG (volatile)"
	@echo "  make prog-flash           - Program SPI flash (persistent)"
	@echo "  make netlist-top          - FuseSoC generator: b8008_top Verilog netlist"
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
	@echo "  make test-phase-clocks    - Test phase clocks with SYNC"
	@echo "  make test-state-timing    - Test state timing generator"
	@echo "  make test-machine-cycle   - Test machine cycle control"
	@echo "  make test-instr-decoder   - Test instruction decoder"
	@echo "  make test-reg-alu-control - Test register and ALU control"
	@echo "  make test-temp-regs       - Test temporary registers"
	@echo "  make test-carry-lookahead - Test carry look-ahead logic"
	@echo "  make test-alu             - Test ALU"
	@echo "  make test-alu-exhaustive  - ALU arithmetic vs reference model (656,384 cases)"
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
	@echo "  make test-stack-memory    - Test stack memory"
	@echo "  make test-int-button      - Test front-panel interrupt button"
	@echo "  make test-address-decoder - Test address decoder"
	@echo "  make test-ram-sync        - Test parameterized synchronous RAM"
	@echo "  make test-debug-clock-control - Test debug clock control"
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

# ----------------------------------------------------------------------------
# Auto-assemble: %.mem rebuilds from %.asm when .asm is newer.
# Prevents the stale-artifact class of failure where a test runs against an
# out-of-date .mem (the class that silently broke check_io_test.sh and
# check_ram_test.sh after the RAM relocation).
# ----------------------------------------------------------------------------
$(PROG_DIR)/%.mem: $(PROG_DIR)/%.asm
	@echo "=== Auto-assembling $*.asm (.mem is stale) ==="
	@cd $(PROG_DIR) && \
	$(ASL) -cpu 8008new -L $*.asm && \
	$(P2HEX) $*.p $*.hex -r 0-8191 && \
	python3 ../$(HEX2MEM) $*.hex $*.mem

# CLAUDE - These are the main tests
# Usage:
#   make test-b8008-top                    - Run with default program (alu_test_as)
#   make test-b8008-top PROG=search_as     - Run with search program
#   make test-b8008-top PROG=ram_intensive_as - Run with RAM intensive test
#   make test-b8008-top PROG=search_as SIM_TIME=30ms - Custom simulation time
ifeq ($(B8008_CORE),netlist)
test-b8008-top: netlist-vhdl
endif
test-b8008-top: $(BUILD_DIR) $(ROM_FILE)
	@echo "========================================="
	@echo "Testing b8008_top - Complete System"
	@echo "Program: $(ROM_FILE)"
	@echo "Sim time: $(SIM_TIME)"
	@echo "========================================="
	@echo ""
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(CORE_SIM_SRCS)
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/b8008/ram_sync.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/address_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_top.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/rom_8kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/b8008_top_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_top_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_top_tb -gROM_FILE=$(ROM_FILE) -gREADY_STRESS=$(READY_STRESS) --stop-time=$(SIM_TIME)

# ============================================================================
# EXTERNAL_RAM EQUIVALENCE TEST
# ============================================================================
# Runs two b8008_top instances side by side (internal ram_sync vs
# EXTERNAL_RAM => true) on the same RAM-exercising program and asserts they
# stay bit-identical. Proves EXTERNAL_RAM is a no-op on CPU behavior before
# a LiteX SoC is trusted to own the RAM.
#
# Usage:
#   make test-b8008-extram
EXTRAM_PROG ?= ram_intensive_as
EXTRAM_ROM_FILE = test_programs/$(EXTRAM_PROG).mem
EXTRAM_SIM_TIME ?= 31ms
test-b8008-extram: $(BUILD_DIR) $(EXTRAM_ROM_FILE)
	@echo "========================================="
	@echo "Testing b8008_top - EXTERNAL_RAM equivalence"
	@echo "Program: $(EXTRAM_ROM_FILE)"
	@echo "Sim time: $(EXTRAM_SIM_TIME)"
	@echo "========================================="
	@echo ""
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/phase_clocks.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/state_timing_generator.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/interrupt_ready_ff.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/machine_cycle_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/memory_io_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/ahl_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/mem_mux_refresh.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_pointer.vhdl
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
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/b8008/ram_sync.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/address_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_top.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/rom_8kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/b8008_top_extram_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_top_extram_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_top_extram_tb -gROM_FILE=$(EXTRAM_ROM_FILE) --stop-time=$(EXTRAM_SIM_TIME)

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
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/ahl_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/mem_mux_refresh.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_memory.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/scratchpad_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_file.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/temp_registers.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_alu_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/carry_lookahead.vhdl
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
test-interrupt: $(BUILD_DIR) $(PROG_DIR)/interrupt_test_as.mem
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
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/ahl_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/mem_mux_refresh.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_pointer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/stack_memory.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/scratchpad_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_file.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/temp_registers.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/register_alu_control.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/carry_lookahead.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/alu.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/condition_flags.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/instruction_register.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/io_buffer.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/components/rom_4kx8.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) ./src/b8008/ram_sync.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/address_decoder.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_top.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/interrupt_test_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) interrupt_test_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) interrupt_test_tb --stop-time=25ms

# ============================================================================
# INDIVIDUAL MODULE TESTS (consolidated)
# ============================================================================
# One static pattern rule covers every unit test. GHDL computes the VHDL
# compile order itself via import (-i) + make (-m), so there are no
# hand-maintained analyze lists.
#
# Defaults per target (stem = target name minus "test-"):
#   testbench unit: <stem with - replaced by _>_tb
#   testbench file: $(TEST_DIR)/<unit>.vhdl
#   stop time:      10us
# Exceptions are declared in the tables below, keyed by full target name.

UNIT_TESTS := \
	test-address-decoder \
	test-ahl-pointer \
	test-alu \
	test-alu-exhaustive \
	test-carry-lookahead \
	test-condition-flags \
	test-debug-clock-control \
	test-instr-decoder \
	test-instr-reg \
	test-int-button \
	test-interrupt-ready \
	test-io-buffer \
	test-machine-cycle \
	test-memory-io-control \
	test-phase-clocks \
	test-ram-sync \
	test-reg-alu-control \
	test-register-file \
	test-scratchpad-decoder \
	test-sss-ddd-selector \
	test-stack-memory \
	test-stack-pointer \
	test-state-timing \
	test-temp-regs

.PHONY: $(UNIT_TESTS)

# All unit testbenches except test-machine-cycle (stale tb, red at HEAD:
# unbound state_half/instr_is_mem_indirect ports; the module's contract
# is covered by formal/machine_cycle_control instead). CI runs this.
.PHONY: test-units
test-units: $(filter-out test-machine-cycle,$(UNIT_TESTS))

# Testbench-name exceptions (target name abbreviates the module name)
TB_test-instr-decoder   := instruction_decoder_tb
TB_test-instr-reg       := instruction_register_tb
TB_test-interrupt-ready := interrupt_ready_ff_tb
TB_test-machine-cycle   := machine_cycle_control_tb
TB_test-reg-alu-control := register_alu_control_tb
TB_test-state-timing    := state_timing_generator_tb
TB_test-temp-regs       := temp_registers_tb

# Testbench-location exceptions (testbench lives outside $(TEST_DIR))
TBFILE_test-phase-clocks := ./sim/units/phase_clocks_tb.vhdl

# Stop-time exceptions (default 10us)
STOP_test-address-decoder     := 1us
STOP_test-alu-exhaustive      := 100ms
STOP_test-debug-clock-control := 100us
STOP_test-int-button          := 20ms
STOP_test-phase-clocks        := 30us
STOP_test-stack-pointer       := 20us
STOP_test-state-timing        := 20us

# Resolved per-target values (expanded at recipe time)
UNIT_TB      = $(or $(TB_$@),$(subst -,_,$*)_tb)
UNIT_TB_FILE = $(or $(TBFILE_$@),$(TEST_DIR)/$(UNIT_TB).vhdl)
UNIT_STOP    = $(or $(STOP_$@),10us)

# Import set: current b8008 sources, the shared phase-clock generator, and
# the one testbench. Never import legacy code (src/s8008, src/v8008,
# src/components/legacy, projects/legacy_projects).
UNIT_IMPORT  = $(wildcard $(SRC_DIR)/*.vhdl) ./src/components/phase_clocks.vhdl $(UNIT_TB_FILE)

$(UNIT_TESTS): test-%: | $(BUILD_DIR)
	@echo "Testing $* ($(UNIT_TB))..."
	$(GHDL) -i $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(UNIT_IMPORT)
	$(GHDL) -m $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(UNIT_TB)
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(UNIT_TB) --stop-time=$(UNIT_STOP)

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
	$(P2HEX) $$BASENAME.p $$BASENAME.hex -r 0-16383 && \
	python3 ../../$(HEX2MEM) $$BASENAME.hex $$BASENAME.mem && \
	echo "" && \
	echo "Output files created:" && \
	echo "  $(SAMPLE_DIR)/$$BASENAME.lst - Assembly listing" && \
	echo "  $(SAMPLE_DIR)/$$BASENAME.hex - Intel HEX format" && \
	echo "  $(SAMPLE_DIR)/$$BASENAME.mem - Memory initialization file"

# ============================================================================
# FPGA SYNTHESIS
# ============================================================================
# Default path: GHDL synthesizes VHDL -> Verilog, then Yosys for ECP5.
# The ghdl-yosys plugin works on macOS as of oss-cad-suite 20260807; the
# direct plugin path is available as 'make synth-plugin' (needs GHDL_PREFIX
# because the suite's bin/yosys wrapper does not set it).

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

# Direct plugin synthesis: VHDL -> RTLIL via ghdl-yosys plugin, no Verilog
# intermediate and no ghdl_gates.v shim. Output kept separate from $(JSON)
# so the two paths can be diffed.
JSON_PLUGIN := $(SYNTH_DIR)/b8008_plugin.json
.PHONY: synth-plugin
synth-plugin: | $(SYNTH_DIR)
	@echo "=== Running Yosys synthesis for ECP5 (ghdl plugin) ==="
	GHDL_PREFIX=$(HOME)/oss-cad-suite/lib/ghdl \
	$(YOSYS) -m ghdl -p "ghdl $(GHDL_FLAGS) --workdir=$(SYNTH_DIR) $(B8008_SRCS) -e b8008; synth_ecp5 -top b8008 -json $(JSON_PLUGIN)" 2>&1 | tee $(SYNTH_DIR)/synth_plugin.log
	@echo ""
	@echo "Synthesis complete: $(JSON_PLUGIN)"

# write_vhdl round-trip netlist of the b8008 core (generic synth, no ECP5
# mapping) for validating the ghdl-yosys-plugin write_vhdl backend
# (upstream issue #235). Simulatable with plain GHDL.
NETLIST_VHDL := $(SYNTH_DIR)/b8008_netlist.vhdl
.PHONY: netlist-vhdl
netlist-vhdl: | $(SYNTH_DIR)
	@echo "=== write_vhdl netlist of b8008 core (generic synth) ==="
	GHDL_PREFIX=$(HOME)/oss-cad-suite/lib/ghdl \
	$(YOSYS) -m ghdl -p "ghdl $(GHDL_FLAGS) --workdir=$(SYNTH_DIR) $(B8008_SRCS) -e b8008; synth -top b8008; rename b8008 b8008_netlist_core; write_vhdl $(NETLIST_VHDL)" 2>&1 | tee $(SYNTH_DIR)/netlist_vhdl.log
	@echo ""
	@echo "Netlist written: $(NETLIST_VHDL)"

# ----------------------------------------------------------------------------
# Formal verification runners (SBY / EQY). One pattern rule per tool;
# per-module configs live in formal/. See docs on issue #235 validation.
# ----------------------------------------------------------------------------
FORMAL_ENV = GHDL_PREFIX=$(HOME)/oss-cad-suite/lib/ghdl PATH="$(OSS_CAD_SUITE):$$PATH"

# Run one module's sby config: make formal-stack_pointer [SBY_TASK=bmc]
formal-%:
	cd formal/$* && $(FORMAL_ENV) $(OSS_CAD_SUITE)/sby -f $*.sby $(SBY_TASK)

# Per-module write_vhdl round trip: make netlist-vhdl-stack_pointer
# emits build/synth/<module>_netlist.vhdl (entity name preserved).
# Modules with submodule dependencies list them in NETLIST_DEPS_<module>.
NETLIST_DEPS_alu := $(SRC_DIR)/carry_lookahead.vhdl

netlist-vhdl-%: | $(SYNTH_DIR)
	GHDL_PREFIX=$(HOME)/oss-cad-suite/lib/ghdl \
	$(YOSYS) -m ghdl -p "ghdl $(GHDL_FLAGS) --workdir=$(SYNTH_DIR) $(SRC_DIR)/b8008_types.vhdl $(NETLIST_DEPS_$*) $(SRC_DIR)/$*.vhdl -e $*; synth -top $*; write_vhdl $(SYNTH_DIR)/$*_netlist.vhdl"

# EQY equivalence: original module vs its write_vhdl round trip.
# Config in formal/eqy/<module>.eqy, workdir build/eqy/<module>.
eqy-%: netlist-vhdl-%
	$(FORMAL_ENV) $(OSS_CAD_SUITE)/eqy -f -d build/eqy/$* formal/eqy/$*.eqy

# Gate-named per-module netlist for hand-built SBY miters: yosys renames
# the module before write_vhdl, so entity <module>_gate can share the work
# library with the RTL original. No text munging of generated files.
# (Named netlist-gate-%, not netlist-vhdl-gate-%: this make is GNU 3.81,
# where the first matching pattern rule wins and netlist-vhdl-% would
# swallow the target with stem "gate-<module>".)
netlist-gate-%: | $(SYNTH_DIR)
	GHDL_PREFIX=$(HOME)/oss-cad-suite/lib/ghdl \
	$(YOSYS) -m ghdl -p "ghdl $(GHDL_FLAGS) --workdir=$(SYNTH_DIR) $(SRC_DIR)/b8008_types.vhdl $(NETLIST_DEPS_$*) $(SRC_DIR)/$*.vhdl -e $*; synth -top $*; rename $* $*_gate; write_vhdl $(SYNTH_DIR)/$*_gate.vhdl"

# cocotb python testbench for one module: make cocotb-stack_pointer
# [DUT_VARIANT=rtl|netlist]. Test code in sim/cocotb/test_<module>.py.
cocotb-%:
	PATH="$(OSS_CAD_SUITE):$$PATH" $(MAKE) -C sim/cocotb TOPLEVEL=$* DUT_VARIANT=$(DUT_VARIANT)

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
# FUSESOC GENERATOR (b8008_top netlist, direct invocation)
# ============================================================================
# FuseSoC-generated b8008_top netlist (distinct from build/synth/b8008.v,
# which is entity b8008 without the top-level memories).
NETLIST_TOP_DIR := build/netlist-top
# Needs pyyaml; point PYTHON at an interpreter that has it if system
# python3 does not (e.g. the fusesoc venv's python)
PYTHON ?= python3
.PHONY: netlist-top
netlist-top:
	@mkdir -p $(NETLIST_TOP_DIR)
	@printf 'gapi: "1.0"\nfiles_root: .\nvlnv: "greygiant:retro:b8008-top-netlist:0"\nparameters:\n  top: b8008_top\n  output: b8008_top.v\n' > $(NETLIST_TOP_DIR)/input.yml
	cd $(NETLIST_TOP_DIR) && $(PYTHON) ../../scripts/fusesoc/ghdl_synth_verilog.py input.yml

# ============================================================================
# FPGA PROJECTS (Delegation to project-specific Makefiles)
# ============================================================================
# Usage: make project P=<project_name> [T=<target>]
# Examples:
#   make project P=blinky           - Build blinky (default: all)
#   make project P=blinky T=synth   - Just synthesize
#   make project P=blinky T=prog    - Program FPGA

P ?= blinky
T ?= all

.PHONY: project list-projects

project:
	@if [ ! -d "projects/$(P)" ]; then \
		echo "ERROR: Project '$(P)' not found in projects/"; \
		echo "Available projects:"; \
		ls -1 projects/ | grep -v "\.mk$$" | grep -v legacy | sed 's/^/  /'; \
		exit 1; \
	fi
	$(MAKE) -C projects/$(P) $(T)

list-projects:
	@echo "Available FPGA projects:"
	@ls -1 projects/ | grep -v "\.mk$$" | grep -v legacy | sed 's/^/  /'

# ============================================================================
# CLEANUP
# ============================================================================

clean:
	@rm -rf $(BUILD_DIR) $(SYNTH_DIR)
	@rm -f *.cf *.o work-obj*.cf *_tb
