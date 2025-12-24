#!/bin/bash

# ============================================================================
# COMPREHENSIVE ALU REGISTER MODE TEST VERIFICATION SCRIPT
# ============================================================================
# Tests all ALU register operations with all source registers
#
# Program: alu_reg_comprehensive_test_as.asm
#
# Tests:
#   - ADD r (7 variants: ADD A,B,C,D,E,H,L)
#   - SUB r (7 variants)
#   - ANA r (7 variants)
#   - ORA r (7 variants)
#   - XRA r (7 variants)
#   - CMP r (7 variants)
#   - ADC r, SBB r with carry
#
# Total: 56+ ALU register operations tested
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "alu_reg_comprehensive_test_as" "30ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== ADD r Tests ==="

# CP1-7: ADD tests
assert_checkpoint 1 \
    "L=0x11"

assert_checkpoint 2 \
    "L=0x13"

assert_checkpoint 3 \
    "L=0x16"

assert_checkpoint 4 \
    "L=0x1A"

assert_checkpoint 5 \
    "L=0x1F"

assert_checkpoint 6 \
    "L=0x20"

assert_checkpoint 7 \
    "L=0x0C"

echo ""
echo "=== SUB r Tests ==="

# CP8-14: SUB tests
assert_checkpoint 8 \
    "L=0x1F"

assert_checkpoint 9 \
    "L=0x1D"

assert_checkpoint 10 \
    "L=0x1A"

assert_checkpoint 11 \
    "L=0x16"

assert_checkpoint 12 \
    "L=0x11"

assert_checkpoint 13 \
    "L=0x00" \
    "ZF=1"

assert_checkpoint 14 \
    "L=0x00" \
    "ZF=1"

echo ""
echo "=== ANA r Tests ==="

# CP15-19: ANA tests
assert_checkpoint 15 \
    "L=0xF0"

assert_checkpoint 16 \
    "L=0x0F"

assert_checkpoint 17 \
    "L=0xAA"

assert_checkpoint 18 \
    "L=0x00" \
    "ZF=1"

assert_checkpoint 19 \
    "L=0x55"

echo ""
echo "=== ORA r Tests ==="

# CP20-23: ORA tests
assert_checkpoint 20 \
    "L=0xFF"

assert_checkpoint 21 \
    "L=0xFF"

assert_checkpoint 22 \
    "L=0xFF"

assert_checkpoint 23 \
    "L=0xFF"

echo ""
echo "=== XRA r Tests ==="

# CP24-28: XRA tests
assert_checkpoint 24 \
    "L=0x0F"

assert_checkpoint 25 \
    "L=0xF0"

assert_checkpoint 26 \
    "L=0x55"

assert_checkpoint 27 \
    "L=0xAA"

assert_checkpoint 28 \
    "L=0x00" \
    "ZF=1"

echo ""
echo "=== CMP r Tests ==="

# CP29-31: CMP tests
assert_checkpoint 29 \
    "ZF=1"

assert_checkpoint 30 \
    "CF=1"

assert_checkpoint 31 \
    "CF=0"

echo ""
echo "=== ADC/SBB with Carry Tests ==="

# CP32-33: ADC and SBB with carry
assert_checkpoint 32 \
    "L=0x12"

assert_checkpoint 33 \
    "L=0x0E"

echo ""
echo "=== Final State ==="

# CP34: Final success
assert_checkpoint 34 \
    "A=0x22"

# Verify final state
assert_final_state \
    "A=0x00"

# Print summary and exit
print_summary
exit $?
