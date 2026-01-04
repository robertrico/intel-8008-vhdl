# ============================================================================
# Blinky Project - b8008 LED Blink Demo (Project Template)
# ============================================================================
# Copy this folder and customize for your project.
# Target: ECP5-5G Versa Development Kit
#
# To create a new project:
#   1. cp -r projects/blinky projects/my_project
#   2. Rename files (blinky.asm -> my_project.asm, etc.)
#   3. Update the settings below to match your filenames
#   4. Update ROM_FILE in src/my_project_top.vhdl
# ============================================================================

# Project settings - CUSTOMIZE THESE:
#   1. Change PROJECT/TOP to your top entity name
#   2. Change LPF to your constraints file
#   3. Change ASM to your assembly file name
#   4. Update ROM_FILE in src/*.vhdl to match your .mem filename
PROJECT := blinky_top
TOP := blinky_top
LPF := constraints/blinky.lpf
ASM := blinky.asm

# Project sources - just the top level wrapper
PROJECT_SRCS := ./src/blinky_top.vhdl

# Include common project rules (must be AFTER PROJECT_SRCS)
include ../project.mk
