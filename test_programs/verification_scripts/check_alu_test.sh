#!/bin/bash

# ============================================================================
# ALU TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive ALU instruction test with checkpoint assertions
#
# Program: alu_test_as.asm
#
# Tests all ALU operations at the instruction level using checkpoints.
#
# Checkpoint Results:
#   CP1:  After ADD   - B=0x08 (5+3=8)
#   CP2:  After SUB   - C=0x02 (5-3=2)
#   CP3:  After ANA   - D=0x01 (0x05 AND 0x03)
#   CP4:  After XRA   - E=0x06 (0x05 XOR 0x03)
#   CP5:  After ORA   - H=0x07 (0x05 OR 0x03)
#   CP6:  After ADI   - L=0x0F (10+5=15)
#   CP7:  After SUI   - L=0x0A (15-5=10)
#   CP8:  After ANI   - L=0x0A (0x0A AND 0x0F)
#   CP9:  After ORI   - L=0xFA (0x0A OR 0xF0)
#   CP10: After XRI   - L=0x05 (0xFA XOR 0xFF)
#   CP11: After DCR   - L=0x00 (decremented from 5)
#   CP12: After CMP   - (verify didn't jump to FAIL)
#   CP13: After ADC   - L=0x0E (5+8+carry=14)
#   CP14: After SBB   - L=0x0D (16-2-borrow=13)
#   CP15: Final       - success
#
# Final Register State:
#   A: 0x00 (success indicator)
#   B: 0x08 (ADD result)
#   C: 0x02 (SUB result)
#   D: 0x01 (ANA result)
#   E: 0x06 (XRA result)
#   H: 0x07 (ORA result)
#   L: 0x0D (SBB result - final L value)
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "alu_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Register ALU Tests ==="

# CP1: ADD B (5+3=8)
assert_checkpoint 1 \
    "B=0x08"

# CP2: SUB C (5-3=2)
assert_checkpoint 2 \
    "B=0x08" \
    "C=0x02"

# CP3: ANA D (0x05 AND 0x03 = 0x01)
assert_checkpoint 3 \
    "D=0x01"

# CP4: XRA E (0x05 XOR 0x03 = 0x06)
assert_checkpoint 4 \
    "E=0x06"

# CP5: ORA H (0x05 OR 0x03 = 0x07)
assert_checkpoint 5 \
    "H=0x07"

echo ""
echo "=== Immediate ALU Tests ==="

# CP6: ADI (10+5=15)
assert_checkpoint 6 \
    "L=0x0F"

# CP7: SUI (15-5=10)
assert_checkpoint 7 \
    "L=0x0A"

# CP8: ANI (0x0A AND 0x0F = 0x0A)
assert_checkpoint 8 \
    "L=0x0A"

# CP9: ORI (0x0A OR 0xF0 = 0xFA)
assert_checkpoint 9 \
    "L=0xFA"

# CP10: XRI (0xFA XOR 0xFF = 0x05)
assert_checkpoint 10 \
    "L=0x05"

echo ""
echo "=== Control Flow Tests ==="

# CP11: DCR loop complete (L decremented from 5 to 0)
assert_checkpoint 11 \
    "L=0x00" \
    "ZF=1"

# CP12: CMP passed (didn't jump to FAIL)
assert_checkpoint 12 \
    "A=0x0C"

echo ""
echo "=== Carry/Borrow Tests ==="

# CP13: ADC (5 + 8 + carry = 14)
assert_checkpoint 13 \
    "L=0x0E"

# CP14: SBB (16 - 2 - borrow = 13)
assert_checkpoint 14 \
    "L=0x0D"

echo ""
echo "=== Final State ==="

# CP15: Final success checkpoint
assert_checkpoint 15 \
    "A=0x0F"

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x08" \
    "C=0x02" \
    "D=0x01" \
    "E=0x06" \
    "H=0x07"

# Print summary and exit
print_summary
exit $?
