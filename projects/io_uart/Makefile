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

# Include common project rules
include ../project.mk

# Override ALL_SRCS to add USART peripheral
# project.mk's PROJECT_SRCS only picks up ./src/*.vhdl, so we need to add usart.vhdl
ALL_SRCS := $(B8008_SRCS) $(COMP_DIR)/usart.vhdl ./src/io_uart_top.vhdl
