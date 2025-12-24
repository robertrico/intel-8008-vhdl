#!/bin/bash

# ============================================================================
# STACK DEPTH TEST VERIFICATION SCRIPT
# ============================================================================
# Tests the 8-level internal stack of the Intel 8008
#
# Program: stack_depth_test_as.asm
#
# The 8008 has an 8-level hardware stack for CALL/RET/RST
# This test verifies:
#   1. 6 nested CALLs work correctly (using stack levels 0-5)
#   2. All 6 RETurns work correctly
#   3. Each level preserves the return address correctly
#
# Checkpoint Results:
#   CP1: Entry SUB1 - L=0x01 (B counter)
#   CP2: Entry SUB2 - L=0x02
#   CP3: Entry SUB3 - L=0x03
#   CP4: Entry SUB4 - L=0x04
#   CP5: Entry SUB5 - L=0x05
#   CP6: Entry SUB6 - L=0x06 (deepest)
#   CP7: Final      - L=0x06
#
# Final Register State:
#   A: 0x00, B: 0x06, C: 0x06
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "stack_depth_test_as" "30ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Stack Descent Tests ==="

# CP1: Entry SUB1 (B = 1)
assert_checkpoint 1 \
    "L=0x01"

# CP2: Entry SUB2 (B = 2)
assert_checkpoint 2 \
    "L=0x02"

# CP3: Entry SUB3 (B = 3)
assert_checkpoint 3 \
    "L=0x03"

# CP4: Entry SUB4 (B = 4)
assert_checkpoint 4 \
    "L=0x04"

# CP5: Entry SUB5 (B = 5)
assert_checkpoint 5 \
    "L=0x05"

# CP6: Entry SUB6 - deepest level (B = 6)
assert_checkpoint 6 \
    "L=0x06"

echo ""
echo "=== Final State ==="

# CP7: Final success checkpoint (B = 6, C = 6)
assert_checkpoint 7 \
    "L=0x06"

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x06" \
    "C=0x06"

# Print summary and exit
print_summary
exit $?
