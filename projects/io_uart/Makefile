# ============================================================================
# IO UART Project - b8008 UART I/O Demo
# ============================================================================
# Demonstrates UART TX/RX via serial port.
# Target: ECP5-5G Versa Development Kit
#
# Usage: make assemble  - Assemble io_uart.asm
#        make synth     - Synthesize design
#        make bit       - Generate bitstream
#        make prog      - Program FPGA
# ============================================================================

# Project settings
PROJECT := io_uart_top
TOP := io_uart_top
LPF := constraints/io_uart.lpf
ASM := io_uart.asm

# USART peripherals. Set BEFORE the include so they land in the build
# rules' dependency graph (a post-include ALL_SRCS override is parsed too
# late and edits to these files silently skip resynthesis).
EXTRA_PROJECT_SRCS := ../../src/components/usart.vhdl ../../src/components/b8008_usart.vhdl

# Include common project rules
include ../project.mk
