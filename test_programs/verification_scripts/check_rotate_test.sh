#!/bin/bash

# ============================================================================
# ROTATE AND CARRY TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive rotate and carry instruction test with checkpoint assertions
#
# Program: rotate_carry_test_as.asm
#
# Tests rotate operations and carry-based conditionals:
#   - RLC (rotate left circular)
#   - RRC (rotate right circular)
#   - RAL (rotate left through accumulator)
#   - RAR (rotate right through accumulator)
#   - JC/JNC (jump on carry/no carry)
#   - RC/RNC (return on carry/no carry)
#   - ADD M, SUB M (memory operations)
#
# Checkpoint Results:
#   CP1:  After RLC   - B=0x03, CF=1
#   CP2:  After JC    - passed
#   CP3:  After RRC   - C=0xC0, CF=1
#   CP4:  After JNC   - did not jump (correct)
#   CP5:  After RAL   - D=0x03, CF=1
#   CP6:  After RAR   - E=0xC0, CF=1
#   CP7:  After JNC   - passed (carry was 0)
#   CP8:  After JC    - passed (carry was 1)
#   CP9:  After RC    - L=0xAA
#   CP10: After RNC   - L=0xBB
#   CP11: After ADD M - L=0x08
#   CP12: After SUB M - L=0x05
#   CP13: Final       - success
#
# Final Register State:
#   A: 0x00 (success indicator)
#   B: 0x03 (RLC result)
#   C: 0xC0 (RRC result)
#   D: 0x03 (RAL result)
#   E: 0xC0 (RAR result)
#   H: 0x10 (RAM pointer high)
#   L: 0x05 (test marker)
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "rotate_carry_test_as" "30ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Rotate Instruction Tests ==="

# CP1: RLC (Rotate Left Circular)
# 0x81 = 10000001 -> 00000011 = 0x03, Carry=1
assert_checkpoint 1 \
    "B=0x03" \
    "CF=1"

# CP2: JC passed (jumped when carry was set)
assert_checkpoint 2

# CP3: RRC (Rotate Right Circular)
# 0x81 = 10000001 -> 11000000 = 0xC0, Carry=1
assert_checkpoint 3 \
    "C=0xC0" \
    "CF=1"

# CP4: JNC correctly did not jump (carry was set)
assert_checkpoint 4 \
    "CF=1"

# CP5: RAL (Rotate Left through Accumulator)
# Old carry=1 goes to bit0: 0x81 -> 0x03
assert_checkpoint 5 \
    "D=0x03" \
    "CF=1"

# CP6: RAR (Rotate Right through Accumulator)
# Old carry=1 goes to bit7: 0x81 -> 0xC0
assert_checkpoint 6 \
    "E=0xC0" \
    "CF=1"

echo ""
echo "=== Carry Conditional Jump Tests ==="

# CP7: JNC passed (carry was 0 after ADI 0)
assert_checkpoint 7 \
    "CF=0"

# CP8: JC passed (carry was 1 after 0xFF+1)
assert_checkpoint 8 \
    "CF=1"

echo ""
echo "=== Conditional Return Tests ==="

# CP9: RC returned correctly (A=0xAA saved to L)
assert_checkpoint 9 \
    "L=0xAA"

# CP10: RNC returned correctly (A=0xBB saved to L)
assert_checkpoint 10 \
    "L=0xBB"

echo ""
echo "=== Memory ALU Tests ==="

# CP11: ADD M (3 + 5 = 8)
assert_checkpoint 11 \
    "L=0x08"

# CP12: SUB M (10 - 5 = 5)
assert_checkpoint 12 \
    "L=0x05"

echo ""
echo "=== Final State ==="

# CP13: Final success checkpoint
assert_checkpoint 13

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x03" \
    "C=0xC0" \
    "D=0x03" \
    "E=0xC0" \
    "H=0x10" \
    "L=0x05"

# Print summary and exit
print_summary
exit $?
