#!/bin/bash

# ============================================================================
# INR/DCR TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive INR and DCR instruction test for all register variants
#
# Program: inr_dcr_test_as.asm
#
# Tests:
#   - INR B, C, D, E, H, L (6 variants - no INR A exists)
#   - DCR B, C, D, E, H, L (6 variants - no DCR A exists)
#   - Boundary: 0xFF + 1 -> 0x00 with Zero flag
#   - Boundary: 0x00 - 1 -> 0xFF
#   - Sign flag: 0x7F + 1 = 0x80 (negative)
#
# Note: INR/DCR do NOT affect the Carry flag per Intel 8008 spec!
#
# Checkpoint Results:
#   CP1:  INR B test    - B=0x06 (5+1=6)
#   CP2:  INR C test    - C=0x0B (10+1=11)
#   CP3:  INR D test    - D=0x15 (20+1=21)
#   CP4:  INR E test    - E=0x2B (42+1=43)
#   CP5:  INR H test    - H=0x65 (100+1=101)
#   CP6:  INR L test    - L=0xC9 (200+1=201)
#   CP7:  DCR B test    - B=0x05 (6-1=5)
#   CP8:  DCR C test    - C=0x0A (11-1=10)
#   CP9:  DCR D test    - D=0x14 (21-1=20)
#   CP10: DCR E test    - E=0x2A (43-1=42)
#   CP11: DCR H test    - H=0x64 (101-1=100)
#   CP12: DCR L test    - L=0xC8 (201-1=200)
#   CP13: Boundary test - B=0x00 (0xFF+1 wraps to 0, Z=1)
#   CP14: Boundary test - B=0xFF (0x00-1 wraps to 0xFF)
#   CP15: Sign test     - C=0x80 (0x7F+1=0x80, S=1)
#   CP16: Final         - success
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "inr_dcr_test_as" "15ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== INR Tests (Increment Register) ==="

# CP1: INR B (5+1=6)
assert_checkpoint 1 \
    "B=0x06"

# CP2: INR C (10+1=11)
assert_checkpoint 2 \
    "C=0x0B"

# CP3: INR D (20+1=21)
assert_checkpoint 3 \
    "D=0x15"

# CP4: INR E (42+1=43)
assert_checkpoint 4 \
    "E=0x2B"

# CP5: INR H (100+1=101)
assert_checkpoint 5 \
    "H=0x65"

# CP6: INR L (200+1=201)
assert_checkpoint 6 \
    "L=0xC9"

echo ""
echo "=== DCR Tests (Decrement Register) ==="

# CP7: DCR B (6-1=5)
assert_checkpoint 7 \
    "B=0x05"

# CP8: DCR C (11-1=10)
assert_checkpoint 8 \
    "C=0x0A"

# CP9: DCR D (21-1=20)
assert_checkpoint 9 \
    "D=0x14"

# CP10: DCR E (43-1=42)
assert_checkpoint 10 \
    "E=0x2A"

# CP11: DCR H (101-1=100)
assert_checkpoint 11 \
    "H=0x64"

# CP12: DCR L (201-1=200)
assert_checkpoint 12 \
    "L=0xC8"

echo ""
echo "=== Boundary Tests ==="

# CP13: 0xFF + 1 = 0x00 with Zero flag
assert_checkpoint 13 \
    "B=0x00" \
    "ZF=1"

# CP14: 0x00 - 1 = 0xFF
assert_checkpoint 14 \
    "B=0xFF"

echo ""
echo "=== Sign Flag Test ==="

# CP15: 0x7F + 1 = 0x80 (Sign flag set)
assert_checkpoint 15 \
    "C=0x80" \
    "SF=1"

echo ""
echo "=== Final State ==="

# CP16: Final success checkpoint
assert_checkpoint 16 \
    "A=0x10"

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0xFF" \
    "C=0x80" \
    "D=0x14" \
    "E=0x2A" \
    "H=0x64" \
    "L=0xC8"

# Print summary and exit
print_summary
exit $?
