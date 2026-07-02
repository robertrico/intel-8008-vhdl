#!/bin/bash

# ============================================================================
# INR/DCR CARRY-PRESERVATION TEST VERIFICATION SCRIPT
# ============================================================================
# Verifies that INR/DCR do NOT touch the Carry flag (Intel 8008 spec:
# increment/decrement affect Z/S/P only).
#
# Program: inr_carry_test_as.asm
#
# Load-bearing for multi-byte arithmetic: SCELBAL's ADDER interleaves
# "ADC M" with "INR L", and its rotate loops interleave "RAL" with "DCR B".
# Regression for the bug where every INR/DCR wrote the internal adder's
# carry into the flag, corrupting all chained FP math (RAM-loaded
# mandelbrot printed solid asterisks - the escape test never fired).
#
# Checkpoint Results:
#   CP1: INR with carry=1         - B=0x06, CF=1
#   CP2: INR 0xFF wrap, carry=0   - B=0x00, CF=0
#   CP3: DCR 0x00 borrow, carry=1 - C=0xFF, CF=1
#   CP4: ADC/INR/ADC 16-bit chain - B=0x00, C=0x01
#   CP5: RAL/DCR/RAL 16-bit chain - B=0x00, C=0x01
#   CP16: Final                   - A=0x10
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "inr_carry_test_as" "15ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== INR/DCR Carry Preservation ==="

# CP1: carry=1 survives INR
assert_checkpoint 1 \
    "B=0x06" \
    "CF=1"

# CP2: INR wrap does not leak a carry
assert_checkpoint 2 \
    "B=0x00" \
    "CF=0"

# CP3: DCR borrow does not clobber carry
assert_checkpoint 3 \
    "C=0xFF" \
    "CF=1"

echo ""
echo "=== SCELBAL Multi-Byte Patterns ==="

# CP4: ADC / INR / ADC chain -> 0x00FF + 0x0001 = 0x0100
assert_checkpoint 4 \
    "B=0x00" \
    "C=0x01"

# CP5: RAL / DCR / RAL chain -> 0x0080 rotated left = 0x0100
assert_checkpoint 5 \
    "B=0x00" \
    "C=0x01"

echo ""
echo "=== Final State ==="

# CP16: Final success checkpoint (checkpoint ID = value in A = 0x10)
assert_checkpoint 16 \
    "A=0x10"

# Print summary and exit
print_summary
exit $?
