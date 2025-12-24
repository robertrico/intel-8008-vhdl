#!/bin/bash

# ============================================================================
# ALU FULL COVERAGE TEST VERIFICATION SCRIPT
# ============================================================================
# Fills gaps in ALU register coverage to reach 100%
#
# Program: alu_full_coverage_test_as.asm
#
# Covers operations NOT tested in alu_reg_comprehensive_test_as.asm:
#   - ANA A, ANA L
#   - ORA A, ORA H, ORA L
#   - XRA H, XRA L
#   - CMP A, CMP E, CMP H, CMP L
#   - ADC A, ADC C, ADC D, ADC E, ADC H, ADC L
#   - SBB A, SBB C, SBB D, SBB E, SBB H, SBB L
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "alu_full_coverage_test_as" "25ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== ANA Missing Tests ==="

# CP1: ANA L
assert_checkpoint 1 \
    "L=0x55"

# CP2: ANA A
assert_checkpoint 2 \
    "L=0xAA"

echo ""
echo "=== ORA Missing Tests ==="

# CP3: ORA H
assert_checkpoint 3 \
    "L=0xFF"

# CP4: ORA L
assert_checkpoint 4 \
    "L=0xFF"

# CP5: ORA A
assert_checkpoint 5 \
    "L=0x55"

echo ""
echo "=== XRA Missing Tests ==="

# CP6: XRA H
assert_checkpoint 6 \
    "L=0x0F"

# CP7: XRA L
assert_checkpoint 7 \
    "L=0xAA"

echo ""
echo "=== CMP Missing Tests ==="

# CP8: CMP E (equal)
assert_checkpoint 8 \
    "ZF=1"

# CP9: CMP H (A < H)
assert_checkpoint 9 \
    "CF=1"

# CP10: CMP L (A > L)
assert_checkpoint 10 \
    "CF=0"

# CP11: CMP A (equal)
assert_checkpoint 11 \
    "ZF=1"

echo ""
echo "=== ADC Missing Tests ==="

# CP12: ADC C
assert_checkpoint 12 \
    "L=0x12"

# CP13: ADC D
assert_checkpoint 13 \
    "L=0x13"

# CP14: ADC E
assert_checkpoint 14 \
    "L=0x14"

# CP15: ADC H
assert_checkpoint 15 \
    "L=0x15"

# CP16: ADC L
assert_checkpoint 16 \
    "L=0x26"

# CP17: ADC A
assert_checkpoint 17 \
    "L=0x21"

echo ""
echo "=== SBB Missing Tests ==="

# CP18: SBB C
assert_checkpoint 18 \
    "L=0x1E"

# CP19: SBB D
assert_checkpoint 19 \
    "L=0x1D"

# CP20: SBB E
assert_checkpoint 20 \
    "L=0x1C"

# CP21: SBB H
assert_checkpoint 21 \
    "L=0x1B"

# CP22: SBB L
assert_checkpoint 22 \
    "L=0x14"

# CP23: SBB A
assert_checkpoint 23 \
    "L=0xFF"

echo ""
echo "=== Final State ==="

# CP24: Final success
assert_checkpoint 24 \
    "A=0x18"

# Verify final state
assert_final_state \
    "A=0x00"

# Print summary and exit
print_summary
exit $?
