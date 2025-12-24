#!/bin/bash

# ============================================================================
# MEMORY ALU OPERATIONS TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive memory-based ALU operations test with checkpoint assertions
#
# Program: memory_alu_test_as.asm
#
# Tests all memory-based ALU operations:
#   - ADC M (Add memory with carry)
#   - SBB M (Subtract memory with borrow)
#   - ANA M (AND memory)
#   - XRA M (XOR memory)
#   - ORA M (OR memory)
#   - CMP M (Compare memory)
#
# Checkpoint Results:
#   CP1:  After ADC M with carry   - E=0x16 (0x05+0x10+1)
#   CP2:  After ADC M no carry     - E=0x15 (0x05+0x10+0)
#   CP3:  After SBB M with borrow  - E=0x0C (0x10-0x03-1)
#   CP4:  After SBB M no borrow    - E=0x0D (0x10-0x03-0)
#   CP5:  After ANA M              - E=0x0B (0xAB AND 0x0F)
#   CP6:  After XRA M              - E=0x55 (0xAA XOR 0xFF)
#   CP7:  After ORA M              - E=0xAF (0xA0 OR 0x0F)
#   CP8:  After CMP M (equal)      - ZF=1
#   CP9:  After CMP M (greater)    - ZF=0, CF=0
#   CP10: After CMP M (less)       - ZF=0, CF=1
#   CP11: Final                    - success
#
# Final Register State:
#   A: 0x00, B: 0x01, H: 0x00, L: 0xF0
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "memory_alu_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== ADC M Tests ==="

# CP1: ADC M with carry (0x05 + 0x10 + 1 = 0x16)
assert_checkpoint 1 \
    "E=0x16"

# CP2: ADC M without carry (0x05 + 0x10 + 0 = 0x15)
assert_checkpoint 2 \
    "E=0x15"

echo ""
echo "=== SBB M Tests ==="

# CP3: SBB M with borrow (0x10 - 0x03 - 1 = 0x0C)
assert_checkpoint 3 \
    "E=0x0C"

# CP4: SBB M without borrow (0x10 - 0x03 - 0 = 0x0D)
assert_checkpoint 4 \
    "E=0x0D"

echo ""
echo "=== Logical Memory Tests ==="

# CP5: ANA M (0xAB AND 0x0F = 0x0B)
assert_checkpoint 5 \
    "E=0x0B"

# CP6: XRA M (0xAA XOR 0xFF = 0x55)
assert_checkpoint 6 \
    "E=0x55"

# CP7: ORA M (0xA0 OR 0x0F = 0xAF)
assert_checkpoint 7 \
    "E=0xAF"

echo ""
echo "=== CMP M Tests ==="

# CP8: CMP M equal (A == M, ZF=1)
assert_checkpoint 8 \
    "ZF=1" \
    "CF=0"

# CP9: CMP M greater (A > M, ZF=0, CF=0)
assert_checkpoint 9 \
    "ZF=0" \
    "CF=0"

# CP10: CMP M less (A < M, ZF=0, CF=1)
assert_checkpoint 10 \
    "ZF=0" \
    "CF=1"

echo ""
echo "=== Final State ==="

# CP11: Final success checkpoint
assert_checkpoint 11

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x01" \
    "H=0x00" \
    "L=0xF0"

# Print summary and exit
print_summary
exit $?
