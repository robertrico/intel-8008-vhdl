#!/bin/bash

# ============================================================================
# UNDEFINED OPCODE CHARACTERIZATION (SPEC SQ-12, VPLAN DC-05 residual)
# ============================================================================
# Program: undef_opcode_test_as.asm
#
# 0x38/0x39 (would-be INR M / DCR M) are excluded from every datasheet
# definition; the only derivable constraint is that memory must not be
# written. This pins b8008's implementation-defined behavior:
#   registers unchanged, memory unchanged, flags update as INR/DCR of
#   a dummy zero operand, carry preserved.
#
#   CP1: C=0x11 D=0x22 E=0x33, flags C=1 Z=0 S=0 P=0  (after 0x38)
#   CP2: C=0x11 D=0x22 E=0x33, flags C=0 Z=0 S=1 P=1  (after 0x39)
#   CP3: B=0x5A (memory canary untouched)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "undef_opcode_test_as" "5ms"

list_checkpoints

echo ""
echo "=== Undefined Opcode Characterization ==="

assert_checkpoint 1 \
    "C=0x11" "D=0x22" "E=0x33"

assert_checkpoint 2 \
    "C=0x11" "D=0x22" "E=0x33"

assert_checkpoint 3 \
    "B=0x5A"

assert_final_state \
    "A=0x00" \
    "B=0x5A" \
    "C=0x11" \
    "D=0x22" \
    "E=0x33"

print_summary
exit $?
