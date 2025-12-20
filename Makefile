# ============================================================================
# b8008 - Block-based Intel 8008 Implementation
# ============================================================================
# Simple, modular build system for block-based 8008 design
# ============================================================================

# Tools
GHDL = ~/oss-cad-suite/bin/ghdl
GHDL_FLAGS = --std=08 --work=work
ASL = ~/Development/asl-current/asl
P2HEX = ~/Development/asl-current/p2hex
HEX2MEM = ./hex_to_mem.py

# Directories
SRC_DIR = ./src/b8008
TEST_DIR = ./sim/b8008
BUILD_DIR = ./build/b8008
PROG_DIR = ./test_programs

.PHONY: all clean assemble test-b8008 test-pc test-phase-clocks test-state-timing test-machine-cycle test-instr-decoder test-reg-alu-control test-temp-regs test-carry-lookahead test-alu test-condition-flags test-interrupt-ready test-instr-reg test-io-buffer test-memory-io-control test-ahl-pointer test-scratchpad-decoder test-register-file test-sss-ddd-selector test-stack-pointer test-stack-addr-decoder test-stack-memory help

all: help

help:
	@echo "============================================"
	@echo "b8008 - Block-based Intel 8008"
	@echo "============================================"
	@echo ""
	@echo "Assembler:"
	@echo "  make assemble PROG=file.asm  - Assemble program and create .hex/.mem files"
	@echo "  make assemble file.asm       - Alternative syntax"
	@echo ""
	@echo "Integration Tests:"
	@echo "  make test-b8008           - Test b8008 top-level (progressive integration)"
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

test-b8008: $(BUILD_DIR)
	@echo "========================================="
	@echo "Testing b8008 Top-Level Integration"
	@echo "========================================="
	@echo "Phase 2: Clock and Timing"
	@echo "Phase 3: Control and Decode"
	@echo "Phase 4: Program Counter and Addressing"
	@echo "Phase 5: Stack System"
	@echo "Phase 6: Register File System"
	@echo "Phase 7: Temp Registers"
	@echo "Phase 8: ALU and Flags"
	@echo "Phase 9: External Interface"
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
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/simple_rom.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/b8008_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_tb --stop-time=50us

test-b8008-top: $(BUILD_DIR)
	@echo "========================================="
	@echo "Testing b8008_top - Complete System"
	@echo "Running search program test"
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
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) b8008_top_tb --stop-time=60ms

# ============================================================================
# INDIVIDUAL MODULE TESTS
# ============================================================================

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

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f *.cf *.o work-obj*.cf
