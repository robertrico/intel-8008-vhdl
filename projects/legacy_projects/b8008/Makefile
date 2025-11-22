# ============================================================================
# b8008 - Block-based Intel 8008 Implementation
# ============================================================================
# A modular, block-diagram based implementation of the Intel 8008
# Each component (PC, ALU, registers, etc.) is a separate, simple module
# ============================================================================

# Tools
GHDL = ~/oss-cad-suite/bin/ghdl
GHDL_FLAGS = --std=08 --work=work

# Directories
SRC_DIR = ../../src/b8008
TEST_DIR = ./test

# Source files (in compilation order)
SOURCES = \
	$(SRC_DIR)/b8008_types.vhdl \
	$(SRC_DIR)/program_counter.vhdl

# Test files
TESTS = \
	$(TEST_DIR)/program_counter_tb.vhdl

# Build directory
BUILD_DIR = ./build

.PHONY: all clean test help

# Default target
all: help

# ============================================================================
# Help
# ============================================================================
help:
	@echo "============================================"
	@echo "b8008 - Block-based Intel 8008"
	@echo "============================================"
	@echo ""
	@echo "Targets:"
	@echo "  make pc          - Build program counter module"
	@echo "  make test-pc     - Test program counter"
	@echo "  make clean       - Remove build files"
	@echo "  make help        - Show this help"
	@echo ""

# ============================================================================
# Build targets
# ============================================================================

# Create build directory
$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# Analyze (compile) program counter
pc: $(BUILD_DIR)
	@echo "Building program counter..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/b8008_types.vhdl
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(SRC_DIR)/program_counter.vhdl
	@echo "✓ Program counter built"

# ============================================================================
# Test targets
# ============================================================================

test-pc: pc
	@echo "Testing program counter..."
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(TEST_DIR)/program_counter_tb.vhdl
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) program_counter_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) program_counter_tb --stop-time=1us
	@echo ""

# ============================================================================
# Clean
# ============================================================================

clean:
	@echo "Cleaning build files..."
	@rm -rf $(BUILD_DIR)
	@rm -f *.cf *.o work-obj*.cf
	@echo "✓ Clean complete"
