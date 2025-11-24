# ============================================================================
# b8008 - Block-based Intel 8008 Implementation
# ============================================================================
# Simple, modular build system for block-based 8008 design
# ============================================================================

# Tools
GHDL = ~/oss-cad-suite/bin/ghdl
GHDL_FLAGS = --std=08 --work=work

# Directories
SRC_DIR = ./src/b8008
TEST_DIR = ./sim/b8008
BUILD_DIR = ./build/b8008

.PHONY: all clean test-pc test-phase-clocks test-state-timing test-machine-cycle test-instr-decoder test-reg-alu-control help

all: help

help:
	@echo "============================================"
	@echo "b8008 - Block-based Intel 8008"
	@echo "============================================"
	@echo ""
	@echo "Targets:"
	@echo "  make test-pc              - Test program counter"
	@echo "  make test-phase-clocks    - Test phase clocks with SYNC"
	@echo "  make test-state-timing    - Test state timing generator"
	@echo "  make test-machine-cycle   - Test machine cycle control"
	@echo "  make test-instr-decoder   - Test instruction decoder"
	@echo "  make test-reg-alu-control - Test register and ALU control"
	@echo "  make clean                - Remove build files"
	@echo ""

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

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

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f *.cf *.o work-obj*.cf
