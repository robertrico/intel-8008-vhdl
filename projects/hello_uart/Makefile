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

# Include common project rules
include ../project.mk

# Override ALL_SRCS to add USART peripherals
# project.mk's PROJECT_SRCS only picks up ./src/*.vhdl, so we need to add usart components
# Note: b8008_usart wraps usart with 8008-specific handshaking
ALL_SRCS := $(B8008_SRCS) $(COMP_DIR)/usart.vhdl $(COMP_DIR)/b8008_usart.vhdl ./src/hello_uart_top.vhdl
