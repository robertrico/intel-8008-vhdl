#!/bin/bash

# ============================================================================
# 14-BIT PC WRAP TEST VERIFICATION SCRIPT (VPLAN STK-07, XP-12)
# ============================================================================
# Program: pc_wrap_test_as.asm
#
# Plants NOPs at 0x3FFC-0x3FFF (RAM), jumps there, and requires the
# fetch stream to wrap 0x3FFF -> 0x0000. Register E carries a sentinel
# so the wrapped pass reaches CP2.
#
#   CP1: E=0xA5 (setup, about to jump to the top of memory)
#   CP2: E=0xA5 (reached ONLY via the wrap)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "pc_wrap_test_as" "10ms"

list_checkpoints

echo ""
echo "=== PC Wrap Tests ==="

assert_checkpoint 1 \
    "E=0xA5"

assert_checkpoint 2 \
    "E=0xA5" \
    "H=0x3F" \
    "L=0xFF"

assert_final_state \
    "A=0x00" \
    "E=0xA5"

print_summary
exit $?
