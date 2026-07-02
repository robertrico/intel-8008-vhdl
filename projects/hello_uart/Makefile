# ============================================================================
# Hello UART Project - b8008 UART Demo
# ============================================================================
# Demonstrates UART TX by sending "Hello, 8008!" via serial port.
# Target: ECP5-5G Versa Development Kit
#
# Usage: make assemble  - Assemble hello_uart.asm
#        make synth     - Synthesize design
#        make bit       - Generate bitstream
#        make prog      - Program FPGA
# ============================================================================

# Project settings
PROJECT := hello_uart_top
TOP := hello_uart_top
LPF := constraints/hello_uart.lpf
ASM := hello_uart.asm

# USART peripherals. Set BEFORE the include so they land in the build
# rules' dependency graph (a post-include ALL_SRCS override is parsed too
# late and edits to these files silently skip resynthesis).
EXTRA_PROJECT_SRCS := ../../src/components/usart.vhdl ../../src/components/b8008_usart.vhdl

# Include common project rules
include ../project.mk
