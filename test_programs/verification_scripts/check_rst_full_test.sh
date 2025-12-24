#!/bin/bash

# ============================================================================
# FULL RST (0-7) TEST VERIFICATION SCRIPT
# ============================================================================
# Tests ALL 8 RST vectors (0-7)
#
# Program: rst_full_test_as.asm
#
# RST n jumps to address n*8:
#   RST 0 -> 0x0000 (special: also bootstrap vector)
#   RST 1 -> 0x0008
#   RST 2 -> 0x0010
#   RST 3 -> 0x0018
#   RST 4 -> 0x0020
#   RST 5 -> 0x0028
#   RST 6 -> 0x0030
#   RST 7 -> 0x0038
#
# Checkpoint Results:
#   CP1: After RST 1 - L=0x11 (C marker)
#   CP2: After RST 2 - L=0x22 (C marker)
#   CP3: After RST 3 - L=0x33 (C marker)
#   CP4: After RST 4 - L=0x44 (C marker)
#   CP5: After RST 5 - L=0x55 (C marker)
#   CP6: After RST 6 - L=0x66 (C marker)
#   CP7: After RST 7 - L=0x77 (C marker)
#   CP8: Final       - L=0x07 (B counter)
#
# Final Register State:
#   A: 0x00, B: 0x07 (7 RST calls completed)
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "rst_full_test_as" "30ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== RST Vector Tests ==="

# CP1: RST 1 executed (C = 0x11)
assert_checkpoint 1 \
    "L=0x11"

# CP2: RST 2 executed (C = 0x22)
assert_checkpoint 2 \
    "L=0x22"

# CP3: RST 3 executed (C = 0x33)
assert_checkpoint 3 \
    "L=0x33"

# CP4: RST 4 executed (C = 0x44)
assert_checkpoint 4 \
    "L=0x44"

# CP5: RST 5 executed (C = 0x55)
assert_checkpoint 5 \
    "L=0x55"

# CP6: RST 6 executed (C = 0x66)
assert_checkpoint 6 \
    "L=0x66"

# CP7: RST 7 executed (C = 0x77)
assert_checkpoint 7 \
    "L=0x77"

echo ""
echo "=== Final State ==="

# CP8: Final success checkpoint (B = 0x07)
assert_checkpoint 8 \
    "L=0x07"

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x07"

# Print summary and exit
print_summary
exit $?
