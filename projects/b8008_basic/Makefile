# ============================================================================
# B8008 BASIC Project - boot-to-BASIC tiny OS (SCELBAL + monitor in ROM)
# ============================================================================
# Interactive monitor/console for the b8008 CPU.
# Target: ECP5-5G Versa Development Kit
#
# Usage: make assemble  - Assemble b8008_monitor.asm
#        make synth     - Synthesize design
#        make bit       - Generate bitstream
#        make prog      - Program FPGA
# ============================================================================

# Project settings
PROJECT := b8008_basic_top
TOP := b8008_basic_top
LPF := constraints/b8008_basic.lpf
ASM := basic_monitor.asm
ROM_PATCH_FLOW := 1   # firmware reaches the bitstream via 'make rom-update', not synthesis

# USART peripherals + debug controller. Set BEFORE the include so they land
# in the build rules' dependency graph (a post-include ALL_SRCS override is
# parsed too late and edits to these files silently skip resynthesis).
# ./src/*.vhdl (rom_4kx8_bram, b8008_monitor_top) come in via PROJECT_SRCS.
EXTRA_PROJECT_SRCS := ../../src/b8008/int_button.vhdl ../../src/components/usart.vhdl ../../src/components/b8008_usart.vhdl ../../src/components/debouncer.vhdl ../../src/b8008/debug_clock_control.vhdl

# Include common project rules
include ../project.mk

# ============================================================================
# Internal-ROM firmware patching (ecpbram flow)
# ============================================================================
# The on-chip ROM (rom_4kx8_bram) is block RAM, so its contents can be swapped
# in the post-PnR config without resynthesis:
#
#   make rom-freeze  - regenerate src/rom_4kx8_bram.vhdl + src/rom_baked.mem
#                      from the current firmware (random bytes in unused space
#                      give ecpbram a unique match pattern). Requires a full
#                      'make build' afterwards. Only needed when you WANT the
#                      simulation sources refreshed; otherwise never.
#   make rom-update  - patch the current firmware (.mem) into the existing
#                      config with ecpbram and re-pack the bitstream. Seconds.
#                      Falls back to a full build automatically if the RTL
#                      changed (config dependency). Then 'make prog-flash'.
# ============================================================================
ECPBRAM ?= $(OSS_CAD_SUITE)/ecpbram
ROM_SEED := 32008
ROM_BAKED := src/rom_combined_baked.mem

ASL_BIN := ~/Development/asl-current/asl
ASL_INC := ~/Development/asl-current/include
P2HEX_BIN := ~/Development/asl-current/p2hex

firmware:
	$(ASL_BIN) -cpu 8008new -i $(ASL_INC) -L basic_monitor.asm
	$(P2HEX_BIN) basic_monitor.p basic_monitor.hex -r 0-16383
	$(ASL_BIN) -cpu 8008new -i $(ASL_INC) -L scelbal_rom.asm
	$(P2HEX_BIN) scelbal_rom.p scelbal_rom.hex -r 0-16383
	python3 merge_rom.py

rom-freeze: firmware
	python3 $(ROOT_DIR)/hex_to_vhdl_rom.py rom_combined.hex src/rom_12kx8_bram.vhdl \
	    --size 12288 --compat --sync --entity rom_12kx8_bram --random-fill $(ROM_SEED) --mem-out $(ROM_BAKED)
	@echo ""
	@echo "ROM frozen from $(ASM). Run 'make build' to bake it into a new config."

rom-update: $(CONFIG) $(MEM_FILE)
	python3 -c "fw=[l.strip() for l in open('$(MEM_FILE)') if l.strip()]; \
	baked=[l.strip() for l in open('$(ROM_BAKED)') if l.strip()]; \
	assert len(fw)<=len(baked), 'firmware larger than ROM'; \
	open('build/rom_new.mem','w').write('\n'.join(fw+baked[len(fw):])+'\n')"
	$(ECPBRAM) -i $(CONFIG) -o build/rom_patched.config -f $(ROM_BAKED) -t build/rom_new.mem
	$(ECPPACK) --input build/rom_patched.config --bit $(BIT) --svf $(SVF)
	@echo ""
	@echo "ROM patched into $(BIT) ($(ASM)) - run 'make prog-flash'"

.PHONY: rom-freeze rom-update

# ECP5 PLL primitive wrapper — read by Yosys, not GHDL.
# GHDL sees only the component declaration in b8008_monitor_top.vhdl and emits
# a black-box module reference; Yosys binds the real cell from this Verilog.
EXTRA_V_SRCS += $(COMP_DIR)/pll_25mhz.v
