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
# Provides targets: help, assemble, build, synth, pnr, bit, prog, prog-flash, clean
# ============================================================================

# Fail recipes when any pipeline stage fails (yosys | tee must not mask errors)
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

# Tools (inherit from environment or use defaults)
OSS_CAD_SUITE ?= $(HOME)/oss-cad-suite/bin
GHDL     ?= $(OSS_CAD_SUITE)/ghdl
YOSYS    ?= $(OSS_CAD_SUITE)/yosys
NEXTPNR  ?= $(OSS_CAD_SUITE)/nextpnr-ecp5
ECPPACK  ?= $(OSS_CAD_SUITE)/ecppack
LOADER   ?= $(OSS_CAD_SUITE)/openFPGALoader
# GTKWAVE  ?= $(OSS_CAD_SUITE)/gtkwave  # Removed from build - run manually if needed
GHDL_FLAGS ?= --std=08 --work=work

# Yosys synthesis flags (can be overridden for debugging)
# Common options to try: -abc9, -nosrl, -nodram, -nowidelut
# Usage: make synth YOSYS_ECP5_FLAGS="-abc9 -nosrl"
YOSYS_ECP5_FLAGS ?=

# Extra Verilog sources to read alongside the GHDL output (e.g. ECP5 PLL wrappers).
# Project Makefiles can append: EXTRA_V_SRCS += $(COMP_DIR)/pll_25mhz.v
EXTRA_V_SRCS ?=

# Assembler and ROM generation
ASL ?= ~/Development/asl-current/asl
P2HEX ?= ~/Development/asl-current/p2hex
P2BIN ?= ~/Development/asl-current/p2bin
HEX2MEM ?= ../../hex_to_mem.py
HEX2VHDL ?= ../../hex_to_vhdl_rom.py

# EEPROM programmer settings (minipro)
CHIP ?= AT28C64B
ROM_SIZE ?= 8192

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
# ROM is external (physical EEPROM) - no synthesized ROM
B8008_SRCS := \
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
	$(COMP_DIR)/phase_clocks.vhdl \
	$(SRC_DIR)/state_timing_generator.vhdl \
	$(SRC_DIR)/machine_cycle_control.vhdl \
	$(SRC_DIR)/memory_io_control.vhdl \
	$(SRC_DIR)/register_alu_control.vhdl \
	$(SRC_DIR)/interrupt_ready_ff.vhdl \
	$(SRC_DIR)/b8008.vhdl \
	$(SRC_DIR)/ram_sync.vhdl \
	$(SRC_DIR)/address_decoder.vhdl \
	$(SRC_DIR)/b8008_top.vhdl

# Project sources (top-level wrapper)
# Use ?= so individual projects can override before include
PROJECT_SRCS ?= $(wildcard ./src/*.vhdl)

# All sources. Projects add peripherals via EXTRA_PROJECT_SRCS, set BEFORE
# the include (use literal ../../src/... paths - COMP_DIR/SRC_DIR are not
# defined yet at that point). Do NOT override ALL_SRCS after the include:
# make expands rule prerequisites at parse time, so a post-include override
# never reaches the build rules - edits to the extra files then silently
# skip resynthesis and the bitstream goes stale.
ALL_SRCS := $(B8008_SRCS) $(PROJECT_SRCS) $(EXTRA_PROJECT_SRCS)

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

# Memory file (for .bin generation / EEPROM flashing)
MEM_FILE := $(basename $(ASM)).mem

# Output files
VERILOG := $(BUILD_DIR)/$(PROJECT).v
JSON := $(BUILD_DIR)/$(PROJECT).json
CONFIG := $(BUILD_DIR)/$(PROJECT).config
BIT := $(BUILD_DIR)/$(PROJECT).bit
SVF := $(BUILD_DIR)/$(PROJECT).svf

# Waveform files
# WAVE=0 disables waveform dumping. Needed for long interactive sims: GHDL's
# GHW writer fails (exit 255, no message) once the file crosses 2 GiB.
WAVE ?= 1
WAVE_FILE := ./sim/$(ACTIVE_TB).ghw
GTKW_FILE := ./sim/$(ACTIVE_TB).gtkw
ifeq ($(WAVE),0)
GHDL_WAVE_OPT :=
else
GHDL_WAVE_OPT := --wave=$(WAVE_FILE)
endif

# Report files
SYNTH_REPORT := $(REPORTS_DIR)/synthesis.txt
PNR_REPORT := $(REPORTS_DIR)/pnr.txt
TIMING_REPORT := $(REPORTS_DIR)/timing.txt
UTIL_REPORT := $(REPORTS_DIR)/utilization.txt
SIM_REPORT := $(REPORTS_DIR)/simulation.txt

.PHONY: help all build assemble rom-bin sim synth pnr bit prog prog-flash clean clean-all reports list-tests

help:
	@echo "============================================"
	@echo "$(PROJECT) - b8008 FPGA Project"
	@echo "============================================"
	@echo ""
	@echo "Build Targets:"
	@echo "  make build      - Full build (assemble + synth + pnr + bit)"
	@echo "  make assemble   - Assemble $(ASM) to .mem file"
	@echo "  make synth      - GHDL to Verilog, then Yosys to JSON"
	@echo "  make pnr        - Place and route with nextpnr"
	@echo "  make bit        - Generate bitstream from config"
	@echo ""
	@echo "Programming:"
	@echo "  make prog       - Program FPGA (just programs, no build)"
	@echo "  make prog-flash - Program SPI flash (persistent)"
	@echo "  make rom-bin    - Generate .bin and flash EEPROM ($(CHIP))"
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

# 'all' and 'build' are synonyms - full build from scratch
all: build

build: assemble $(BIT)
	@echo "=== Build complete: $(BIT) ==="

# Directory creation - these are phony to always check/create
.PHONY: create-build-dir create-reports-dir
create-build-dir:
	@mkdir -p $(BUILD_DIR)

create-reports-dir:
	@mkdir -p $(REPORTS_DIR)

# ============================================================================
# ASSEMBLE - Convert .asm to .mem and .hex (for EEPROM flashing)
# ============================================================================
# ROM is external (physical EEPROM) - no VHDL generation needed
ifdef ASM
$(MEM_FILE): $(ASM)
	@echo "=== Assembling $(ASM) ==="
	$(ASL) -cpu 8008new -L $(ASM)
	$(P2HEX) $(basename $(ASM)).p $(basename $(ASM)).hex -r 0-$(shell echo $$(($(ROM_SIZE)-1)))
	python3 $(HEX2MEM) $(basename $(ASM)).hex $(basename $(ASM)).mem
	@echo "Output: $(MEM_FILE)"

assemble: $(MEM_FILE)
else
assemble:
	@echo "No ASM file specified, skipping assembly"
endif

# ============================================================================
# ROM-BIN - Generate binary and flash EEPROM with minipro
# ============================================================================
ifdef ASM
BIN_FILE := $(basename $(ASM)).bin

rom-bin: $(MEM_FILE)
	@echo "=== Generating binary ROM for $(CHIP) ==="
	$(P2BIN) $(basename $(ASM)).p $(BIN_FILE) -r 0-$$(($(ROM_SIZE)-1)) -l $(ROM_SIZE)
	@echo "Output: $(BIN_FILE) ($(ROM_SIZE) bytes, padded with 0xFF)"
	@echo ""
	@echo "=== Programming $(CHIP) ==="
	minipro -p $(CHIP) -w $(BIN_FILE)
else
rom-bin:
	@echo "No ASM file specified for this project"
	@exit 1
endif

# ============================================================================
# SYNTHESIZE - GHDL to Verilog, Yosys to JSON
# ============================================================================
# Verilog depends on VHDL sources AND the .mem file (ROM contents baked in)
# Projects using the ecpbram patch flow (ROM_PATCH_FLOW=1) do not bake the
# .mem into synthesis - firmware reaches the bitstream via 'make rom-update',
# so a firmware change must NOT trigger resynthesis.
ifeq ($(if $(ASM),$(if $(ROM_PATCH_FLOW),,asm)),asm)
$(VERILOG): $(ALL_SRCS) $(MEM_FILE) | create-build-dir
else
$(VERILOG): $(ALL_SRCS) | create-build-dir
endif
	@echo "=== GHDL: Synthesizing $(TOP) to Verilog ==="
	$(GHDL) -a $(GHDL_FLAGS) $(ALL_SRCS)
	$(GHDL) --synth $(GHDL_FLAGS) --out=verilog $(TOP) > $@
	@echo "Verilog: $@ ($$(wc -l < $@) lines)"

$(JSON): $(VERILOG) | create-build-dir create-reports-dir
	@echo "=== Yosys: Synthesizing for ECP5 ==="
	@if [ -n "$(YOSYS_ECP5_FLAGS)" ]; then echo "  Extra flags: $(YOSYS_ECP5_FLAGS)"; fi
	$(YOSYS) -p "read_verilog -lib +/ecp5/cells_bb.v; read_verilog $(ROOT_DIR)/src/synth/ghdl_gates.v $(EXTRA_V_SRCS) $<; hierarchy -check -top $(TOP); tribuf -logic; proc; opt -nodffe; synth_ecp5 -top $(TOP) $(YOSYS_ECP5_FLAGS) -json $@" 2>&1 | tee $(SYNTH_REPORT)
	@echo ""
	@grep -E "Number of cells|LUT|DFF|CARRY" $(SYNTH_REPORT) || true

synth: $(JSON)

# ============================================================================
# PLACE AND ROUTE
# ============================================================================
$(CONFIG): $(JSON) | create-reports-dir
	@echo "=== Place & Route with nextpnr-ecp5 ==="
	$(NEXTPNR) --$(DEVICE) --package $(PACKAGE) --speed $(SPEED) \
		--json $(JSON) --lpf $(LPF) --textcfg $@ \
		2>&1 | tee $(PNR_REPORT)
	@grep -A 50 "Critical path report" $(PNR_REPORT) > $(TIMING_REPORT) 2>/dev/null || true
	@grep -E "Max frequency|Max delay|Slack" $(PNR_REPORT) >> $(TIMING_REPORT) 2>/dev/null || true
	@grep -B 2 -A 30 "Device utilisation" $(PNR_REPORT) > $(UTIL_REPORT) 2>/dev/null || true

pnr: $(CONFIG)

# ============================================================================
# BITSTREAM
# ============================================================================
$(BIT): $(CONFIG)
	@echo "=== Generating Bitstream ==="
	$(ECPPACK) --input $< --bit $@ --svf $(SVF)
	@echo "Bitstream ready: $@"

bit: $(BIT)

# ============================================================================
# PROGRAM - Just programs, doesn't build
# ============================================================================
prog:
	@if [ ! -f "$(BIT)" ]; then \
		echo "ERROR: No bitstream found at $(BIT)"; \
		echo "Run 'make build' first."; \
		exit 1; \
	fi
ifdef ASM
	@if [ ! -f "$(MEM_FILE)" ]; then \
		echo "WARNING: No .mem file found. Run 'make assemble' first."; \
	elif [ "$(MEM_FILE)" -nt "$(BIT)" ]; then \
		echo "WARNING: $(MEM_FILE) is newer than $(BIT)"; \
		echo "         ROM contents may be stale. Consider 'make build'."; \
	fi
endif
	@echo "=== Programming via JTAG (SRAM) ==="
	$(LOADER) -c ft2232 -m $(BIT)

prog-flash:
	@if [ ! -f "$(BIT)" ]; then \
		echo "ERROR: No bitstream found at $(BIT)"; \
		echo "Run 'make build' first."; \
		exit 1; \
	fi
	@echo "=== Programming SPI Flash ==="
	$(LOADER) -c ft2232 -f $(BIT)

# ============================================================================
# SIMULATE
# ============================================================================
SIM_TIME ?= 100ms

sim: assemble | create-build-dir create-reports-dir
	@echo "=== Running simulation: $(ACTIVE_TB) ==="
	@echo "==========================================" > $(SIM_REPORT)
	@echo "Simulation Report - $$(date)" >> $(SIM_REPORT)
	@echo "Testbench: $(ACTIVE_TB)" >> $(SIM_REPORT)
	@echo "Duration: $(SIM_TIME)" >> $(SIM_REPORT)
	@echo "==========================================" >> $(SIM_REPORT)
	$(GHDL) -a $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ALL_SRCS) $(ACTIVE_TB_SRC)
	$(GHDL) -e $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ACTIVE_TB)
	@set -o pipefail; $(GHDL) -r $(GHDL_FLAGS) --workdir=$(BUILD_DIR) $(ACTIVE_TB) \
		--stop-time=$(SIM_TIME) \
		$(GHDL_WAVE_OPT) \
		--assert-level=error \
		--ieee-asserts=disable-at-0 \
		2>&1 | tee -a $(SIM_REPORT); \
	SIM_EXIT=$$?; \
	if [ $$SIM_EXIT -eq 0 ]; then \
		echo "SIMULATION PASSED" | tee -a $(SIM_REPORT); \
	else \
		echo "SIMULATION FAILED" | tee -a $(SIM_REPORT); \
		exit $$SIM_EXIT; \
	fi
	@if [ "$(WAVE)" != "0" ]; then echo "Waveform saved to: $(WAVE_FILE)"; fi

list-tests:
	@echo "Available testbenches:"
	@ls -1 ./sim/*.vhdl 2>/dev/null | xargs -I {} basename {} .vhdl | sed 's/^/  /' || echo "  (none)"
	@echo ""
	@echo "Usage: make sim TEST=<testbench_name>"

# ============================================================================
# REPORTS
# ============================================================================
reports:
	@if [ ! -d "$(REPORTS_DIR)" ]; then \
		echo "No reports found. Run 'make build' first."; \
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

# ============================================================================
# CLEAN
# ============================================================================
clean:
	@rm -rf $(BUILD_DIR)
	@rm -f *.cf *.o work-obj*.cf
ifdef ASM
	@rm -f $(basename $(ASM)).p $(basename $(ASM)).hex $(basename $(ASM)).lst 2>/dev/null || true
endif
	@echo "Cleaned $(PROJECT)"

clean-all: clean
	@rm -rf $(REPORTS_DIR)
	@rm -f ./sim/*.ghw ./sim/*.vcd
ifdef ASM
	@rm -f $(MEM_FILE) 2>/dev/null || true
endif
	@echo "Cleaned all generated files"
