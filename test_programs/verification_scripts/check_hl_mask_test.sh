#!/bin/bash

# ============================================================================
# H[7:6] DON'T-CARE MASK TEST VERIFICATION SCRIPT (VPLAN BUS-10, XP-13)
# ============================================================================
# Program: hl_mask_test_as.asm
#
# M address = {H[5:0], L}. All four H quadrants (0x10/0x50/0x90/0xD0)
# must alias physical 0x1080: write via one, read via another.
#
#   CP1: B=0xAA (wrote via H=0x10, read via H=0xD0)
#   CP2: C=0x55 (wrote via H=0x90, read via H=0x10)
#   CP3: D=0x55 (read via H=0x50)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "hl_mask_test_as" "10ms"

list_checkpoints

echo ""
echo "=== H[7:6] Mask Tests ==="

assert_checkpoint 1 \
    "B=0xAA"

assert_checkpoint 2 \
    "C=0x55"

assert_checkpoint 3 \
    "D=0x55"

assert_final_state \
    "A=0x00" \
    "B=0xAA" \
    "C=0x55" \
    "D=0x55"

print_summary
exit $?
