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

# Use generated ROM to avoid Yosys synthesis bugs with file-based ROM initialization
# The generated rom_4kx8.vhdl in ./src/ has explicit array initialization
USE_GENERATED_ROM := 1

# Include common project rules
include ../project.mk

# Override ALL_SRCS to add USART peripherals and generated ROM
# project.mk's PROJECT_SRCS only picks up ./src/*.vhdl, so we need to add usart components
# Note: b8008_usart wraps usart with 8008-specific handshaking
# Note: ./src/rom_4kx8.vhdl is the generated ROM (USE_GENERATED_ROM excludes shared version)
ALL_SRCS := $(B8008_SRCS) $(COMP_DIR)/usart.vhdl $(COMP_DIR)/b8008_usart.vhdl ./src/rom_4kx8.vhdl ./src/b8008_monitor_top.vhdl
