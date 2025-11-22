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

.PHONY: all clean test-pc test-phase-clocks help

all: help

help:
	@echo "============================================"
	@echo "b8008 - Block-based Intel 8008"
	@echo "============================================"
	@echo ""
	@echo "Targets:"
	@echo "  make test-pc           - Test program counter"
	@echo "  make test-phase-clocks - Test phase clocks with SYNC"
	@echo "  make clean             - Remove build files"
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

clean:
	@rm -rf $(BUILD_DIR)
	@rm -f *.cf *.o work-obj*.cf
