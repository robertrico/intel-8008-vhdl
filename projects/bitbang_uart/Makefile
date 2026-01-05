# ============================================================================
# Bitbang UART Project - b8008 Classic Bitbanged Serial I/O Demo
# ============================================================================
# Demonstrates 1970s-style bitbanged serial I/O at 2400 baud.
# Software toggles bits via OUT 8, reads bits via IN 0.
# Target: ECP5-5G Versa Development Kit
#
# Usage: make assemble  - Assemble bitbang_uart.asm
#        make synth     - Synthesize design
#        make bit       - Generate bitstream
#        make prog      - Program FPGA
# ============================================================================

# Project settings
PROJECT := bitbang_uart_top
TOP := bitbang_uart_top
LPF := constraints/bitbang_uart.lpf
ASM := bitbang_uart.asm

# Include common project rules
include ../project.mk

# Override ALL_SRCS to add bitbang_uart_adapter (which contains usart internally)
# usart.vhdl must be compiled before bitbang_uart_adapter.vhdl
ALL_SRCS := $(B8008_SRCS) $(COMP_DIR)/usart.vhdl $(COMP_DIR)/bitbang_uart_adapter.vhdl ./src/bitbang_uart_top.vhdl
