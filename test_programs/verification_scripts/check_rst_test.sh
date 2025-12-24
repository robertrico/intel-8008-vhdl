#!/bin/bash

# ============================================================================
# RST (RESTART) INSTRUCTION TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive RST instruction test with checkpoint assertions
#
# Program: rst_test_as.asm
#
# Tests RST instruction (software interrupt/subroutine call):
#   - RST 1 (jump to 0x0008)
#   - RST 2 (jump to 0x0010)
#   - RST 3 (jump to 0x0018)
#   - RST 4 (jump to 0x0020)
#
# RST is a 1-cycle instruction that:
#   - Pushes return address to stack
#   - Jumps to address AAA * 8 (RST vector)
#
# Checkpoint Results:
#   CP1:  After RST 1 - C=0x01, B=0x01
#   CP2:  After RST 2 - D=0x02, B=0x02
#   CP3:  After RST 3 - E=0x03, B=0x03
#   CP4:  After RST 4 - H=0x04, B=0x04
#   CP5:  Final       - success
#
# Final Register State:
#   A: 0x00, B: 0x04
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "rst_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== RST Instruction Tests ==="

# CP1: RST 1 worked (C=0x01, B=0x01)
assert_checkpoint 1 \
    "C=0x01" \
    "B=0x01"

# CP2: RST 2 worked (D=0x02, B=0x02)
assert_checkpoint 2 \
    "D=0x02" \
    "B=0x02"

# CP3: RST 3 worked (E=0x03, B=0x03)
assert_checkpoint 3 \
    "E=0x03" \
    "B=0x03"

# CP4: RST 4 worked (H=0x04, B=0x04)
assert_checkpoint 4 \
    "H=0x04" \
    "B=0x04"

echo ""
echo "=== Final State ==="

# CP5: Final success checkpoint
assert_checkpoint 5

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x04"

# Print summary and exit
print_summary
exit $?
