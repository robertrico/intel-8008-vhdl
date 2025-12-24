#!/bin/bash

# ============================================================================
# SIGN/PARITY CONDITIONAL CALL TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive sign/parity conditional call test with checkpoint assertions
#
# Program: sign_parity_call_test_as.asm
#
# Tests sign and parity flag-based conditional call instructions:
#   - CP  (Call on Positive / Sign=0)
#   - CM  (Call on Minus / Sign=1)
#   - CPO (Call on Parity Odd)
#   - CPE (Call on Parity Even)
#
# Checkpoint Results:
#   CP1:  After CP    - C=0xAA (called on positive)
#   CP2:  After CM    - D=0xBB (called on minus)
#   CP3:  After CPO   - E=0xCC (called on odd parity)
#   CP4:  After CPE   - H=0xDD (called on even parity)
#   CP5:  After CP!   - L=0x00 (did not call on negative)
#   CP6:  After CM!   - L=0x00 (did not call on positive)
#   CP7:  After CPE!  - L=0x00 (did not call on odd parity)
#   CP8:  After CPO!  - L=0x00 (did not call on even parity)
#   CP9:  Final       - success
#
# Final Register State:
#   A: 0x00, B: 0x04
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "sign_parity_call_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Conditional Call Tests (Should Call) ==="

# CP1: CP called on positive (C = 0xAA)
assert_checkpoint 1 \
    "C=0xAA"

# CP2: CM called on minus (D = 0xBB)
assert_checkpoint 2 \
    "D=0xBB"

# CP3: CPO called on odd parity (E = 0xCC)
assert_checkpoint 3 \
    "E=0xCC"

# CP4: CPE called on even parity (H = 0xDD)
assert_checkpoint 4 \
    "H=0xDD"

echo ""
echo "=== Conditional Call Tests (Should NOT Call) ==="

# CP5: CP did not call on negative (L = 0x00)
assert_checkpoint 5 \
    "L=0x00"

# CP6: CM did not call on positive (L = 0x00)
assert_checkpoint 6 \
    "L=0x00"

# CP7: CPE did not call on odd parity (L = 0x00)
assert_checkpoint 7 \
    "L=0x00"

# CP8: CPO did not call on even parity (L = 0x00)
assert_checkpoint 8 \
    "L=0x00"

echo ""
echo "=== Final State ==="

# CP9: Final success checkpoint
assert_checkpoint 9

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x04"

# Print summary and exit
print_summary
exit $?
