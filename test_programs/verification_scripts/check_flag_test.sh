#!/bin/bash

# ============================================================================
# FLAG VERIFICATION TEST SCRIPT
# ============================================================================
# Comprehensive flag test with checkpoint assertions
#
# Program: flag_test_as.asm
#
# Tests all four condition flags:
#   - Carry flag (C)
#   - Zero flag (Z)
#   - Sign flag (S) - bit 7 of result
#   - Parity flag (P) - even parity = 1
#
# Checkpoint Results:
#   CP1:  After Z=1 test    - ZF=1 (zero result)
#   CP2:  After Z=0 test    - ZF=0 (non-zero result)
#   CP3:  After S=1 test    - SF=1 (sign bit set)
#   CP4:  After S=0 test    - SF=0 (sign bit clear)
#   CP5:  After C=1 test    - CF=1, ZF=1 (0xFF+1=0x00)
#   CP6:  After C=0 test    - CF=0 (no carry)
#   CP7:  After P=0 test    - PF=0 (odd parity)
#   CP8:  After P=1 test    - PF=1 (even parity)
#   CP9:  Final             - success
#
# Final Register State:
#   A: 0x00, B: 0x08
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "flag_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Zero Flag Tests ==="

# CP1: Zero flag set (Z=1)
assert_checkpoint 1 \
    "ZF=1"

# CP2: Zero flag clear (Z=0)
assert_checkpoint 2 \
    "ZF=0"

echo ""
echo "=== Sign Flag Tests ==="

# CP3: Sign flag set (S=1)
assert_checkpoint 3 \
    "SF=1"

# CP4: Sign flag clear (S=0)
assert_checkpoint 4 \
    "SF=0"

echo ""
echo "=== Carry Flag Tests ==="

# CP5: Carry flag set (C=1, also Z=1 from overflow)
assert_checkpoint 5 \
    "CF=1" \
    "ZF=1"

# CP6: Carry flag clear (C=0)
assert_checkpoint 6 \
    "CF=0"

echo ""
echo "=== Parity Flag Tests ==="

# CP7: Parity odd (P=0)
assert_checkpoint 7 \
    "PF=0"

# CP8: Parity even (P=1)
assert_checkpoint 8 \
    "PF=1"

echo ""
echo "=== Final State ==="

# CP9: Final success checkpoint
assert_checkpoint 9

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x08"

# Print summary and exit
print_summary
exit $?
