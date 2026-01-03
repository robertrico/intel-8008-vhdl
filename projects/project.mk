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
# Optional overrides:
#   TEST         - Specify which testbench to run (e.g., make sim TEST=mytest)
#   SIM_TIME     - Simulation duration (default: 100ms)
#
# Provides targets: help, assemble, sim, synth, pnr, bit, prog, prog-flash, clean
# ============================================================================

# Tools (inherit from environment or use defaults)
OSS_CAD_SUITE ?= $(HOME)/oss-cad-suite/bin
GHDL     ?= $(OSS_CAD_SUITE)/ghdl
YOSYS    ?= $(OSS_CAD_SUITE)/yosys
NEXTPNR  ?= $(OSS_CAD_SUITE)/nextpnr-ecp5
ECPPACK  ?= $(OSS_CAD_SUITE)/ecppack
LOADER   ?= $(OSS_CAD_SUITE)/openFPGALoader
GTKWAVE  ?= $(OSS_CAD_SUITE)/gtkwave
GHDL_FLAGS ?= --std=08 --work=work

# Assembler
ASL ?= ~/Development/asl-current/asl
P2HEX ?= ~/Development/asl-current/p2hex
HEX2MEM ?= ../../hex_to_mem.py

# FPGA settings (ECP5-5G Versa LFE5UM5G-45F)
DEVICE   ?= um5g-45k
PACKAGE  ?= CABGA381
SPEED    ?= 8

# Directories (relative to project directory)
BUILD_DIR := ./build
REPORTS_DIR := ./reports
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

# Testbench sources
TB_SRCS := $(wildcard ./sim/*.vhdl)

# Test selection: make sim TEST=mytestbench
ifdef TEST
    ACTIVE_TB := $(TEST)
    ACTIVE_TB_SRC := ./sim/$(TEST).vhdl
else
    ACTIVE_TB := $(PROJECT)_tb
    ACTIVE_TB_SRC := $(TB_SRCS)
endif

# Output files
VERILOG := $(BUILD_DIR)/$(PROJECT).v
JSON := $(BUILD_DIR)/$(PROJECT).json
CONFIG := $(BUILD_DIR)/$(PROJECT).config
BIT := $(BUILD_DIR)/$(PROJECT).bit
SVF := $(BUILD_DIR)/$(PROJECT).svf

# Waveform files
WAVE_FILE := ./sim/$(ACTIVE_TB).ghw
GTKW_FILE := ./sim/$(ACTIVE_TB).gtkw

# Report files
SYNTH_REPORT := $(REPORTS_DIR)/synthesis.txt
PNR_REPORT := $(REPORTS_DIR)/pnr.txt
TIMING_REPORT := $(REPORTS_DIR)/timing.txt
UTIL_REPORT := $(REPORTS_DIR)/utilization.txt
SIM_REPORT := $(REPORTS_DIR)/simulation.txt

.PHONY: help all assemble sim synth pnr bit prog prog-flash clean clean-all reports list-tests

help:
	@echo "============================================"
	@echo "$(PROJECT) - b8008 FPGA Project"
	@echo "============================================"
	@echo ""
	@echo "Build Targets:"
	@echo "  make all        - Full build (assemble + synth + pnr + bit)"
	@echo "  make assemble   - Assemble $(ASM) to .mem file"
	@echo "  make synth      - Synthesize with GHDL+Yosys"
	@echo "  make pnr        - Place and route with nextpnr"
	@echo "  make bit        - Generate bitstream"
	@echo ""
	@echo "Programming:"
	@echo "  make prog       - Program FPGA via JTAG (volatile)"
	@echo "  make prog-flash - Program SPI flash (persistent)"
	@echo ""
	@echo "Simulation:"
	@echo "  make sim        - Run simulation and open GTKWave"
	@echo "  make sim TEST=x - Run specific testbench"
	@echo "  make list-tests - List available testbenches"
	@echo ""
	@echo "Reports:"
	@echo "  make reports    - View timing/utilization reports"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean      - Remove build artifacts"
	@echo "  make clean-all  - Remove all generated files"
	@echo ""
	@echo "Options:"
	@echo "  SIM_TIME=<time> - Simulation duration (default: 100ms)"
	@echo "  TEST=<name>     - Testbench to run"
	@echo ""

all: assemble synth pnr bit
	@echo "=== Build complete: $(BIT) ==="

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

.PHONY: create-reports-dir
create-reports-dir:
	@mkdir -p $(REPORTS_DIR)

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

sim: assemble create-reports-dir | $(BUILD_DIR)
	@echo "=== Running simulation: $(ACTIVE_TB) ==="
	@echo "==========================================" > $(SIM_REPORT)
	@echo "Simulation Report - $$(date)" >> $(SIM_REPORT)
	@echo "Testbench: $(ACTIVE_TB)" >> $(SIM_REPORT)
	@echo "Duration: $(SIM_TIME)" >> $(SIM_REPORT)
	@echo "==========================================" >> $(SIM_REPORT)
	@echo "" >> $(SIM_REPORT)
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ALL_SRCS) $(ACTIVE_TB_SRC)
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ACTIVE_TB)
	@set -o pipefail; $(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ACTIVE_TB) \
		--stop-time=$(SIM_TIME) \
		--wave=$(WAVE_FILE) \
		--assert-level=error \
		--ieee-asserts=disable-at-0 \
		2>&1 | tee -a $(SIM_REPORT); \
	SIM_EXIT=$$?; \
	echo "" >> $(SIM_REPORT); \
	if [ $$SIM_EXIT -eq 0 ]; then \
		echo "SIMULATION PASSED" | tee -a $(SIM_REPORT); \
		echo "Waveform: $(WAVE_FILE)"; \
		echo "Report: $(SIM_REPORT)"; \
		echo "Opening GTKWave..."; \
		if [ -f "$(GTKW_FILE)" ]; then \
			nohup $(GTKWAVE) $(GTKW_FILE) > /dev/null 2>&1 & \
		else \
			nohup $(GTKWAVE) $(WAVE_FILE) > /dev/null 2>&1 & \
		fi; \
	else \
		echo "SIMULATION FAILED" | tee -a $(SIM_REPORT); \
		echo "Opening GTKWave to inspect..."; \
		if [ -f "$(GTKW_FILE)" ]; then \
			nohup $(GTKWAVE) $(GTKW_FILE) > /dev/null 2>&1 & \
		else \
			nohup $(GTKWAVE) $(WAVE_FILE) > /dev/null 2>&1 & \
		fi; \
		exit $$SIM_EXIT; \
	fi

list-tests:
	@echo "Available testbenches:"
	@ls -1 ./sim/*.vhdl 2>/dev/null | xargs -I {} basename {} .vhdl | sed 's/^/  /' || echo "  (none)"
	@echo ""
	@echo "Usage: make sim TEST=<testbench_name>"

# ============================================================================
# SYNTHESIZE
# ============================================================================
synth: $(JSON)

$(VERILOG): $(ALL_SRCS) | $(BUILD_DIR)
	@echo "=== Synthesizing $(TOP) with GHDL ==="
	@# Don't use --workdir for synthesis - it breaks file_open for ROM loading
	$(GHDL) -a $(GHDL_FLAGS) $(ALL_SRCS)
	$(GHDL) --synth $(GHDL_FLAGS) --out=verilog $(TOP) > $@
	@echo "Verilog: $@ ($$(wc -l < $@) lines)"

$(JSON): $(VERILOG) create-reports-dir | $(BUILD_DIR)
	@echo "=== Running Yosys synthesis for ECP5 ==="
	@# tribuf -logic converts internal tri-state to mux logic
	@# hierarchy -keep_portwidths prevents port optimization that breaks connections
	@# opt -nodffe prevents DFF optimization that can break design
	$(YOSYS) -p "read_verilog $(ROOT_DIR)/src/synth/ghdl_gates.v $<; hierarchy -check -top $(TOP); tribuf -logic; proc; opt -nodffe; synth_ecp5 -top $(TOP) -json $@" 2>&1 | tee $(SYNTH_REPORT)
	@echo ""
	@echo "Synthesis report: $(SYNTH_REPORT)"
	@grep -E "Number of cells|LUT|DFF|CARRY" $(SYNTH_REPORT) || true

# ============================================================================
# PLACE AND ROUTE
# ============================================================================
pnr: $(CONFIG)

$(CONFIG): $(JSON) create-reports-dir
	@echo "=== Place & Route with nextpnr-ecp5 ==="
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --speed $(SPEED) \
		--json $(JSON) --lpf $(LPF) --textcfg $@ \
		--timing-allow-fail 2>&1 | tee $(PNR_REPORT)
	@echo ""
	@echo "Extracting timing report..."
	@grep -A 50 "Critical path report" $(PNR_REPORT) > $(TIMING_REPORT) 2>/dev/null || true
	@grep -E "Max frequency|Max delay|Slack" $(PNR_REPORT) >> $(TIMING_REPORT) 2>/dev/null || true
	@echo ""
	@echo "Extracting utilization report..."
	@grep -B 2 -A 30 "Device utilisation" $(PNR_REPORT) > $(UTIL_REPORT) 2>/dev/null || true
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
	$(LOADER) -c ft2232 -m $(BIT)

# Quick program - just program existing bitstream, no rebuild check
prog-quick:
	@if [ ! -f "$(BIT)" ]; then \
		echo "No bitstream found. Run 'make bit' first."; \
		exit 1; \
	fi
	@echo "=== Quick Programming via JTAG (SRAM) ==="
	$(LOADER) -c ft2232 -m $(BIT)

prog-flash: $(BIT)
	@echo "=== Programming SPI Flash ==="
	$(LOADER) -b versa_ecp5 $(BIT)

# ============================================================================
# REPORTS
# ============================================================================
reports:
	@if [ ! -d "$(REPORTS_DIR)" ]; then \
		echo "No reports found. Run 'make all' first."; \
		exit 1; \
	fi
	@echo "=========================================="
	@echo "FPGA Build Reports"
	@echo "=========================================="
	@echo ""
	@if [ -f "$(UTIL_REPORT)" ]; then \
		echo "--- Resource Utilization ---"; \
		cat $(UTIL_REPORT); \
		echo ""; \
	fi
	@if [ -f "$(TIMING_REPORT)" ]; then \
		echo "--- Timing Summary ---"; \
		head -20 $(TIMING_REPORT); \
		echo ""; \
	fi
	@echo "Full reports:"
	@echo "  Simulation:   $(SIM_REPORT)"
	@echo "  Synthesis:    $(SYNTH_REPORT)"
	@echo "  PnR:          $(PNR_REPORT)"
	@echo "  Timing:       $(TIMING_REPORT)"
	@echo "  Utilization:  $(UTIL_REPORT)"

# ============================================================================
# CLEAN
# ============================================================================
clean:
	@rm -rf $(BUILD_DIR)
	@rm -f *.cf *.o work-obj*.cf
	@rm -f $(basename $(ASM)).p $(basename $(ASM)).hex $(basename $(ASM)).lst 2>/dev/null || true
	@echo "Cleaned $(PROJECT)"

clean-all: clean
	@rm -rf $(REPORTS_DIR)
	@rm -f ./sim/*.ghw ./sim/*.vcd
	@echo "Cleaned all generated files"
