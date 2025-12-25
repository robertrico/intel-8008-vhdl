# ============================================================================
# Common Project Rules for b8008 FPGA Projects
# ============================================================================
# Include this from project-specific Makefiles
#
# Required variables (set before include):
#   PROJECT  - Project name (e.g., blinky_top)
#   TOP      - Top-level entity name
#   LPF      - Constraints file path (relative to project dir)
#   ASM      - Assembly source file (optional)
#
# Provides targets: help, assemble, synth, pnr, bit, prog, clean
# ============================================================================

# Tools (inherit from environment or use defaults)
OSS_CAD_SUITE ?= $(HOME)/oss-cad-suite/bin
GHDL     ?= $(OSS_CAD_SUITE)/ghdl
YOSYS    ?= $(OSS_CAD_SUITE)/yosys
NEXTPNR  ?= $(OSS_CAD_SUITE)/nextpnr-ecp5
ECPPACK  ?= $(OSS_CAD_SUITE)/ecppack
LOADER   ?= $(OSS_CAD_SUITE)/openFPGALoader
GHDL_FLAGS ?= --std=08 --work=work

# Assembler
ASL ?= ~/Development/asl-current/asl
P2HEX ?= ~/Development/asl-current/p2hex
HEX2MEM ?= ../../hex_to_mem.py

# FPGA settings (ECP5-5G Versa)
DEVICE   ?= 85k
PACKAGE  ?= CABGA381
SPEED    ?= 8

# Directories (relative to project directory)
BUILD_DIR := ./build
ROOT_DIR := ../..
SRC_DIR := $(ROOT_DIR)/src/b8008
COMP_DIR := $(ROOT_DIR)/src/components

# b8008 core sources (order matters)
B8008_SRCS := \
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
	$(COMP_DIR)/phase_clocks.vhdl \
	$(SRC_DIR)/state_timing_generator.vhdl \
	$(SRC_DIR)/machine_cycle_control.vhdl \
	$(SRC_DIR)/memory_io_control.vhdl \
	$(SRC_DIR)/register_alu_control.vhdl \
	$(SRC_DIR)/interrupt_ready_ff.vhdl \
	$(SRC_DIR)/b8008.vhdl \
	$(COMP_DIR)/rom_4kx8.vhdl \
	$(COMP_DIR)/legacy/ram_1kx8.vhdl \
	$(SRC_DIR)/b8008_top.vhdl

# Project sources (top-level wrapper)
PROJECT_SRCS := $(wildcard ./src/*.vhdl)

# All sources
ALL_SRCS := $(B8008_SRCS) $(PROJECT_SRCS)

# Output files
VERILOG := $(BUILD_DIR)/$(PROJECT).v
JSON := $(BUILD_DIR)/$(PROJECT).json
CONFIG := $(BUILD_DIR)/$(PROJECT).config
BIT := $(BUILD_DIR)/$(PROJECT).bit
SVF := $(BUILD_DIR)/$(PROJECT).svf

# Testbench sources
TB_SRCS := $(wildcard ./sim/*.vhdl)

.PHONY: help all assemble sim synth pnr bit prog prog-flash clean

help:
	@echo "============================================"
	@echo "$(PROJECT) - b8008 FPGA Project"
	@echo "============================================"
	@echo ""
	@echo "Targets:"
	@echo "  make assemble  - Assemble $(ASM) to .mem file"
	@echo "  make sim       - Run simulation testbench"
	@echo "  make synth     - Synthesize with GHDL+Yosys"
	@echo "  make pnr       - Place and route with nextpnr"
	@echo "  make bit       - Generate bitstream"
	@echo "  make prog      - Program FPGA via JTAG (volatile)"
	@echo "  make prog-flash - Program SPI flash (persistent)"
	@echo "  make all       - Full build (assemble + synth + pnr + bit)"
	@echo "  make clean     - Remove build artifacts"
	@echo ""

all: assemble synth pnr bit
	@echo "=== Build complete: $(BIT) ==="

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# ============================================================================
# ASSEMBLE
# ============================================================================
assemble:
ifdef ASM
	@echo "=== Assembling $(ASM) ==="
	$(ASL) -cpu 8008new -L $(ASM)
	$(P2HEX) $(basename $(ASM)).p $(basename $(ASM)).hex -r 0-4095
	python3 $(HEX2MEM) $(basename $(ASM)).hex $(basename $(ASM)).mem
	@echo "Output: $(basename $(ASM)).mem"
else
	@echo "No ASM file specified, skipping assembly"
endif

# ============================================================================
# SIMULATE
# ============================================================================
SIM_TIME ?= 100ms

sim: assemble | $(BUILD_DIR)
	@echo "=== Running simulation ==="
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ALL_SRCS) $(TB_SRCS)
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(PROJECT)_tb
	$(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(PROJECT)_tb --stop-time=$(SIM_TIME) 2>&1 | tee $(BUILD_DIR)/sim.log
	@echo ""
	@echo "=== Simulation complete ==="

# ============================================================================
# SYNTHESIZE
# ============================================================================
synth: $(JSON)

$(VERILOG): $(ALL_SRCS) | $(BUILD_DIR)
	@echo "=== Synthesizing $(TOP) with GHDL ==="
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ALL_SRCS)
	$(GHDL) --synth $(GHDL_FLAGS) --workdir=$(BUILD_DIR) --out=verilog $(TOP) > $@
	@echo "Verilog: $@ ($$(wc -l < $@) lines)"

$(JSON): $(VERILOG)
	@echo "=== Running Yosys synthesis for ECP5 ==="
	$(YOSYS) -p "read_verilog $(ROOT_DIR)/src/synth/ghdl_gates.v $<; synth_ecp5 -top $(TOP) -json $@" 2>&1 | tee $(BUILD_DIR)/synth.log
	@echo ""
	@grep -E "Number of cells|LUT|DFF|CARRY" $(BUILD_DIR)/synth.log || true

# ============================================================================
# PLACE AND ROUTE
# ============================================================================
pnr: $(CONFIG)

$(CONFIG): $(JSON)
	@echo "=== Place & Route with nextpnr-ecp5 ==="
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --speed $(SPEED) \
		--json $(JSON) --lpf $(LPF) --textcfg $@ \
		--timing-allow-fail
	@echo "Place & route complete: $@"

# ============================================================================
# BITSTREAM
# ============================================================================
bit: $(BIT)

$(BIT): $(CONFIG)
	@echo "=== Generating Bitstream ==="
	$(ECPPACK) --input $< --bit $@ --svf $(SVF)
	@echo "Bitstream ready: $@"

# ============================================================================
# PROGRAM
# ============================================================================
prog: $(BIT)
	@echo "=== Programming via JTAG (SRAM) ==="
	$(LOADER) $(BIT)

prog-flash: $(BIT)
	@echo "=== Programming SPI Flash ==="
	$(LOADER) -f $(BIT)

# ============================================================================
# CLEAN
# ============================================================================
clean:
	@rm -rf $(BUILD_DIR)
	@rm -f *.cf *.o work-obj*.cf
	@rm -f $(basename $(ASM)).p $(basename $(ASM)).hex $(basename $(ASM)).lst
	@echo "Cleaned $(PROJECT)"
