#!/bin/bash

# ============================================================================
# RST-AT-STACK-WRAP TEST VERIFICATION SCRIPT
# ============================================================================
# VPLAN XP-06 residual: stackwrap_test covers the 8th nested CALL; this
# covers the same wrap when the 8th push is an RST.
#
# Program: rst_wrap_test_as.asm
#
# Checkpoint Results:
#   CP1: descent complete (inside L7, before RST) - B=0x07
#   CP2: RST 1 vector reached                     - B=0x07
#   CP3: RWRAP pad reached via wrapped final RET
#   CP4: must be ABSENT (clean return to MAIN = split-PC regression)
#
# Final Register State:
#   A: 0x00, B: 0x07
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "rst_wrap_test_as" "30ms"

list_checkpoints

echo ""
echo "=== RST Wrap Tests ==="

# CP1: descent complete before the RST
assert_checkpoint 1 \
    "B=0x07"

# CP2: the RST vector executed (the 8th push happened)
assert_checkpoint 2 \
    "B=0x07"

# CP3: final RET landed on the wrapped slot's frozen address
assert_checkpoint 3 \
    "B=0x07"

# CP4: a clean return to MAIN means the stack held 8 return contexts -
# the split-PC deviation this architecture removed. Regression check.
assert_checkpoint_absent 4

assert_final_state \
    "A=0x00" \
    "B=0x07"

print_summary
exit $?
