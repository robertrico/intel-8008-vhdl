#!/bin/bash

# ============================================================================
# SEARCH PROGRAM TEST VERIFICATION SCRIPT
# ============================================================================
# Searches memory for a period character ('.')
#
# Program: search_as.asm
#
# Test data: "Hello, world. 8008!!" stored starting at location 200 (0xC8)
# Period is at position 212 (0xD4)
#
# Checkpoint Results:
#   CP1: Found period - E=0xD4 (position 212)
#
# Final Register State:
#   A: 0x2E (period character '.')
#   H: 0x2E (copied from A)
#   L: 0xD4 (position 212)
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "search_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Search Result ==="

# CP1: Found the period at position 212 (0xD4)
assert_checkpoint 1 \
    "E=0xD4"

echo ""
echo "=== Final State ==="

# Verify final state via traditional method
assert_final_state \
    "A=0x2E" \
    "H=0x2E" \
    "L=0xD4"

# Print summary and exit
print_summary
exit $?
