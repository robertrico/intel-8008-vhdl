# ============================================================================
# Blinky Project - b8008 LED Blink Demo
# ============================================================================
# Target: ECP5-5G Versa Development Kit
# Usage: make synth / make pnr / make bit / make prog
# ============================================================================

# Project settings
PROJECT := blinky_top
TOP := blinky_top
LPF := constraints/blinky.lpf
ASM := blinky.asm

# Only use blinky_top.vhdl from local src (no UART needed)
# Must be defined BEFORE including project.mk so ALL_SRCS picks it up
PROJECT_SRCS := ./src/blinky_top.vhdl

# Include common project rules
include ../project.mk
