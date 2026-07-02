#!/bin/bash

# ============================================================================
# ROTATE FLAG-PRESERVATION TEST VERIFICATION SCRIPT
# ============================================================================
# Rotates (RLC/RRC/RAL/RAR) must update CARRY ONLY - Z/S/P hold their
# pre-rotate values per the 8008 datasheet.
#
# Program: rotate_flags_test_as.asm
#
# Checkpoint Results:
#   CP1: XRA A then RLC(0x80)     - CF=1, ZF=1, SF=0, PF=1
#   CP2: ADI-carry then RAR(0x01) - CF=1, ZF=1, SF=0, PF=1
#   CP3: ANA(0x55) then RRC(0x01) - CF=1, ZF=0, SF=0, PF=1
#   CP4: ANA(0xFF) then RAL(0x80) - CF=1, ZF=0, SF=1, PF=1
#   CP5: final - success
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "rotate_flags_test_as" "30ms"

list_checkpoints

echo ""
echo "=== Rotate Flag-Preservation Tests ==="

# CP1: RLC preserves Z=1 S=0 P=1 from XRA A
assert_checkpoint 1 \
    "CF=1" \
    "ZF=1" \
    "SF=0" \
    "PF=1"

# CP2: RAR preserves Z=1 S=0 P=1 from ADI carry-out
assert_checkpoint 2 \
    "CF=1" \
    "ZF=1" \
    "SF=0" \
    "PF=1"

# CP3: RRC preserves Z=0 S=0 P=1 from ANA 0x55
assert_checkpoint 3 \
    "CF=1" \
    "ZF=0" \
    "SF=0" \
    "PF=1"

# CP4: RAL result is 0x00 but ZF must STAY 0 (from ANA 0xFF)
assert_checkpoint 4 \
    "CF=1" \
    "ZF=0" \
    "SF=1" \
    "PF=1"

# CP5: reached the end
assert_checkpoint 5

assert_final_state \
    "A=0x00"

# Print summary and exit
print_summary
exit $?
