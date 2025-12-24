#!/bin/bash

# ============================================================================
# RAM INTENSIVE PROGRAM TEST VERIFICATION
# ============================================================================
# Comprehensive RAM testing with multiple operations
#
# Program: ram_intensive_as.asm
#
# Test Phases:
#   1. Fill RAM with ascending pattern (0-15)
#   2. Read back and accumulate sum
#   3. Write inverted pattern
#   4. Verify first and last values
#
# Checkpoint Results:
#   CP1: After FILL_RAM  - L=0x10 (filled 16 bytes)
#   CP2: After CALC_SUM  - L=0x78 (sum = 120)
#   CP3: After INVERT    - L=0x10 (inverted 16 bytes)
#   CP4: After VERIFY    - L=0xFF (first inverted value)
#
# Final Register State:
#   A: 0xF0 (last inverted value)
#   B: 0xFF (first inverted value)
#   H: 0x10 (RAM base high)
#   L: 0x0F (last array index)
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "ram_intensive_as" "30ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== RAM Fill Phase ==="

# CP1: After FILL_RAM (L = 0x10, loop counter)
assert_checkpoint 1 \
    "L=0x10"

echo ""
echo "=== Sum Calculation Phase ==="

# CP2: After CALC_SUM (L = 0x78 = 120 = sum of 0-15)
assert_checkpoint 2 \
    "L=0x78"

echo ""
echo "=== Inversion Phase ==="

# CP3: After INVERT_RAM (L = 0x10, loop counter)
assert_checkpoint 3 \
    "L=0x10"

echo ""
echo "=== Verification Phase ==="

# CP4: After VERIFY (D = A = 0xF0, last inverted value)
assert_checkpoint 4 \
    "D=0xF0"

echo ""
echo "=== Final State ==="

# Verify final state via traditional method
assert_final_state \
    "A=0xF0" \
    "B=0xFF" \
    "H=0x10" \
    "L=0x0F"

# Print summary and exit
print_summary
exit $?
