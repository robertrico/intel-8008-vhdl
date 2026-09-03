# ============================================================================
# B8008 Monitor Project - Interactive Console
# ============================================================================
# Interactive monitor/console for the b8008 CPU.
# Target: ECP5-5G Versa Development Kit
#
# Usage: make assemble  - Assemble b8008_monitor.asm
#        make synth     - Synthesize design
#        make bit       - Generate bitstream
#        make prog      - Program FPGA
#
# Serial (see 'make serial-help'):
#        make monitor                      - open minicom on the monitor UART
#        make kill-monitor                 - kill minicom (frees the port)
#        make send-hex HEX=pi_ram.hex      - kill minicom, stream HEX via 'L'
#        make send-hex HEX=pi_ram.hex GO=2040   - ...then 'G 2040'
# ============================================================================

# Project settings
PROJECT := b8008_monitor_top
TOP := b8008_monitor_top
LPF := constraints/b8008_monitor.lpf
ASM := b8008_monitor.asm
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
ROM_BAKED := src/rom_baked.mem

rom-freeze: assemble
	python3 $(ROOT_DIR)/hex_to_vhdl_rom.py $(basename $(ASM)).hex src/rom_4kx8_bram.vhdl \
	    --compat --sync --entity rom_4kx8_bram --random-fill $(ROM_SEED) --mem-out $(ROM_BAKED)
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

# ============================================================================
# Serial console
# ============================================================================
# One process owns the port: send-hex kills minicom first, then you reopen it
# with 'make monitor'. minicom's own menu is Ctrl-A Z (exit is Ctrl-A X); if
# that is hard to reach from a remote shell, 'make kill-monitor' from another
# terminal does the same job.
#
# HEX= is looked up as given, then under test_programs/samples/, then under the
# repo root - so 'HEX=pi_ram.hex' works from this directory.
# ============================================================================
SERIAL_PORT ?= /dev/tty.usbserial-AB0JK5WC
SERIAL_BAUD ?= 115200
MINICOM     ?= minicom
SEND_HEX    := $(ROOT_DIR)/send_hex.py
SAMPLES_DIR := $(ROOT_DIR)/test_programs/samples

serial-help:
	@echo "Serial console ($(SERIAL_PORT) @ $(SERIAL_BAUD) 8N1):"
	@echo "  make monitor                        - open minicom"
	@echo "  make kill-monitor                   - kill minicom, free the port"
	@echo "  make send-hex HEX=file.hex          - kill minicom, stream file via 'L'"
	@echo "  make send-hex HEX=file.hex GO=2040  - ...then 'G 2040'"
	@echo "  SERIAL_PORT=/dev/tty.xxx make monitor  - other port"
	@echo ""
	@echo "Samples (test_programs/samples): pi_ram.hex G=2040, calc_ram.hex G=2100,"
	@echo "  mandelbrot_ram.hex G=2040, hexspawn_ram.hex G=2100"

monitor:
	@test -e $(SERIAL_PORT) || { echo "ERROR: $(SERIAL_PORT) not present (ls /dev/tty.usbserial*)"; exit 1; }
	$(MINICOM) -D $(SERIAL_PORT) -b $(SERIAL_BAUD) -c on -w

# minicom does not die on the spot: on SIGTERM it "hangs up" (drops DTR,
# restores the tty) and only then exits. Opening the port during that window
# corrupts the first bytes of a send. So: wait for the process to actually be
# gone, then give the driver SERIAL_SETTLE seconds to release the device.
SERIAL_SETTLE ?= 2

kill-monitor:
	@if pkill -x minicom; then \
	    n=0; while pgrep -x minicom >/dev/null && [ $$n -lt 50 ]; do sleep 0.1; n=$$((n+1)); done; \
	    if pgrep -x minicom >/dev/null; then echo "minicom still running after 5 s - pkill -9 -x minicom"; exit 1; fi; \
	    echo "minicom killed; settling $(SERIAL_SETTLE)s for $(SERIAL_PORT)"; sleep $(SERIAL_SETTLE); \
	else \
	    echo "minicom not running"; \
	fi

send-hex: kill-monitor
	@test -n "$(HEX)" || { echo "usage: make send-hex HEX=file.hex [GO=addr]"; exit 1; }
	@hex="$(HEX)"; \
	if [ ! -f "$$hex" ]; then hex="$(SAMPLES_DIR)/$(HEX)"; fi; \
	if [ ! -f "$$hex" ]; then hex="$(ROOT_DIR)/$(HEX)"; fi; \
	if [ ! -f "$$hex" ]; then echo "ERROR: $(HEX) not found (tried ., $(SAMPLES_DIR), $(ROOT_DIR))"; exit 1; fi; \
	echo "=== Sending $$hex to $(SERIAL_PORT)$(if $(GO), then G $(GO),) ==="; \
	python3 $(SEND_HEX) "$$hex" --port $(SERIAL_PORT) --baud $(SERIAL_BAUD) $(if $(GO),--go $(GO),)
	@echo ""
	@echo "Done. Reattach with 'make monitor'."

.PHONY: serial-help monitor kill-monitor send-hex
