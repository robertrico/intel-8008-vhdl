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
# ============================================================================

# Project settings
PROJECT := b8008_monitor_top
TOP := b8008_monitor_top
LPF := constraints/b8008_monitor.lpf
ASM := b8008_monitor.asm

# Include common project rules
include ../project.mk

# Override ALL_SRCS to add USART peripherals
# project.mk's PROJECT_SRCS only picks up ./src/*.vhdl, so we need to add usart components
# Note: b8008_usart wraps usart with 8008-specific handshaking
ALL_SRCS := $(B8008_SRCS) $(COMP_DIR)/usart.vhdl $(COMP_DIR)/b8008_usart.vhdl $(COMP_DIR)/debouncer.vhdl $(SRC_DIR)/debug_clock_control.vhdl ./src/rom_4kx8.vhdl ./src/b8008_monitor_top.vhdl

# ECP5 PLL primitive wrapper — read by Yosys, not GHDL.
# GHDL sees only the component declaration in b8008_monitor_top.vhdl and emits
# a black-box module reference; Yosys binds the real cell from this Verilog.
EXTRA_V_SRCS += $(COMP_DIR)/pll_25mhz.v
