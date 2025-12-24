#!/bin/bash

# ============================================================================
# CONDITIONAL CALL AND CARRY IMMEDIATE TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive conditional call test with checkpoint assertions
#
# Program: conditional_call_test_as.asm
#
# Tests conditional calls and carry-based immediate operations:
#   - ACI (Add immediate with carry)
#   - SBI (Subtract immediate with borrow)
#   - CNC (Call on no carry)
#   - CC (Call on carry)
#   - CNZ (Call on not zero)
#   - CZ (Call on zero)
#   - RZ (Return on zero)
#
# Checkpoint Results:
#   CP1:  After ACI with carry    - L=0x16 (0x10+0x05+1)
#   CP2:  After ACI no carry      - L=0x15 (0x10+0x05+0)
#   CP3:  After SBI with borrow   - L=0x1A (0x20-0x05-1)
#   CP4:  After SBI no borrow     - L=0x1B (0x20-0x05-0)
#   CP5:  After CC                - C=0xAA (called on carry)
#   CP6:  After CNC               - D=0xBB (called on no carry)
#   CP7:  After CNZ/CZ/RZ         - B=0x07
#   CP8:  Final                   - success
#
# Final Register State:
#   A: 0x00, B: 0x07, C: 0xAA, D: 0xBB
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "conditional_call_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== ACI (Add Immediate with Carry) Tests ==="

# CP1: ACI with carry (0x10 + 0x05 + 1 = 0x16)
assert_checkpoint 1 \
    "L=0x16"

# CP2: ACI without carry (0x10 + 0x05 + 0 = 0x15)
assert_checkpoint 2 \
    "L=0x15"

echo ""
echo "=== SBI (Subtract Immediate with Borrow) Tests ==="

# CP3: SBI with borrow (0x20 - 0x05 - 1 = 0x1A)
assert_checkpoint 3 \
    "L=0x1A"

# CP4: SBI without borrow (0x20 - 0x05 - 0 = 0x1B)
assert_checkpoint 4 \
    "L=0x1B"

echo ""
echo "=== Conditional Call Tests ==="

# CP5: CC called on carry (C = 0xAA)
assert_checkpoint 5 \
    "C=0xAA"

# CP6: CNC called on no carry (D = 0xBB)
assert_checkpoint 6 \
    "D=0xBB"

# CP7: CNZ/CZ/RZ all worked (B = 0x07)
assert_checkpoint 7 \
    "B=0x07"

echo ""
echo "=== Final State ==="

# CP8: Final success checkpoint
assert_checkpoint 8

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x07" \
    "C=0xAA" \
    "D=0xBB"

# Print summary and exit
print_summary
exit $?
