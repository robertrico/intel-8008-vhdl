#!/bin/bash

# ============================================================================
# ADDRESS-STACK WRAPAROUND VERIFICATION SCRIPT (spec-8008 semantics)
# ============================================================================
# The PC lives inside the 8 address-stack registers (PC-in-stack): 7
# nested returns fit, the 8th CALL wraps onto the oldest context, and
# the unwind's final RET lands on the WRAP pad past L8's RET (CP2).
# Returning to MAIN (CP3) would mean the stack is deeper than a real
# 8008 - the old split-PC deviation.
#
# Program: stackwrap_test_as.asm
#
# Checkpoint Results:
#   CP1: descent complete (inside L8), B=0x08
#   CP2: WRAP pad reached via the wrapped final RET, A=0x00
#   CP3: must NEVER fire (split-PC regression)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "stackwrap_test_as" "30ms"

list_checkpoints

echo ""
echo "=== Stack Wraparound Tests (PC-in-stack) ==="

# CP1: full 8-level descent happened
assert_checkpoint 1 \
    "B=0x08"

# CP2: the wrapped final RET landed on the WRAP pad
assert_checkpoint 2

# CP3 (return to MAIN) must not fire - that's the split-PC deviation
assert_checkpoint_absent 3

assert_final_state \
    "A=0x00" \
    "B=0x08"

# Print summary and exit
print_summary
exit $?
