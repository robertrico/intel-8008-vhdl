#!/bin/bash

# ============================================================================
# SIGN AND PARITY TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive sign and parity flag test with checkpoint assertions
#
# Program: sign_parity_test_as.asm
#
# Tests sign and parity flag-based conditional instructions:
#   - JP  (Jump on Positive - sign flag clear)
#   - JM  (Jump on Minus - sign flag set)
#   - JPE (Jump on Parity Even)
#   - JPO (Jump on Parity Odd)
#   - RP  (Return on Positive)
#   - RM  (Return on Minus)
#   - RPE (Return on Parity Even)
#   - RPO (Return on Parity Odd)
#
# Checkpoint Results:
#   CP1:  After JP     - B=0x01 (jumped on positive)
#   CP2:  After JM     - C=0x02 (jumped on minus)
#   CP3:  After JP!    - did not jump on negative (correct)
#   CP4:  After JM!    - did not jump on positive (correct)
#   CP5:  After JPE    - D=0x03 (jumped on even parity)
#   CP6:  After JPO    - E=0x04 (jumped on odd parity)
#   CP7:  After JPE!   - did not jump on odd parity (correct)
#   CP8:  After JPO!   - did not jump on even parity (correct)
#   CP9:  After RP     - L=0xAA (returned on positive)
#   CP10: After RM     - L=0xBB (returned on minus)
#   CP11: After RPE    - L=0xCC (returned on even parity)
#   CP12: After RPO    - L=0xDD (returned on odd parity)
#   CP13: Final        - success
#
# Final Register State:
#   A: 0x00, B: 0x01, C: 0x02, D: 0x03, E: 0x04, H: 0x10, L: 0x08
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "sign_parity_test_as" "30ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Sign Flag Jump Tests ==="

# CP1: JP worked (jumped on positive)
assert_checkpoint 1 \
    "B=0x01" \
    "SF=0"

# CP2: JM worked (jumped on minus)
assert_checkpoint 2 \
    "C=0x02" \
    "SF=1"

# CP3: JP correctly did not jump on negative
assert_checkpoint 3 \
    "SF=1"

# CP4: JM correctly did not jump on positive
assert_checkpoint 4 \
    "SF=0"

echo ""
echo "=== Parity Flag Jump Tests ==="

# CP5: JPE worked (jumped on even parity)
assert_checkpoint 5 \
    "D=0x03" \
    "PF=1"

# CP6: JPO worked (jumped on odd parity)
assert_checkpoint 6 \
    "E=0x04" \
    "PF=0"

# CP7: JPE correctly did not jump on odd parity
assert_checkpoint 7 \
    "PF=0"

# CP8: JPO correctly did not jump on even parity
assert_checkpoint 8 \
    "PF=1"

echo ""
echo "=== Conditional Return Tests ==="

# CP9: RP returned correctly (A=0xAA saved to L)
assert_checkpoint 9 \
    "L=0xAA"

# CP10: RM returned correctly (A=0xBB saved to L)
assert_checkpoint 10 \
    "L=0xBB"

# CP11: RPE returned correctly (A=0xCC saved to L)
assert_checkpoint 11 \
    "L=0xCC"

# CP12: RPO returned correctly (A=0xDD saved to L)
assert_checkpoint 12 \
    "L=0xDD"

echo ""
echo "=== Final State ==="

# CP13: Final success checkpoint
assert_checkpoint 13

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x01" \
    "C=0x02" \
    "D=0x03" \
    "E=0x04" \
    "H=0x10" \
    "L=0x08"

# Print summary and exit
print_summary
exit $?
