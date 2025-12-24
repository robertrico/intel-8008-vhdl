#!/bin/bash

# ============================================================================
# MVI M (MEMORY IMMEDIATE) TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive MVI M instruction test with checkpoint assertions
#
# Program: mvi_m_test_as.asm
#
# Tests MVI M instruction (Move Immediate to Memory)
#   - MVI M,data (opcode 00111110 = 0x3E)
#
# MVI M is a 3-cycle instruction:
#   - Cycle 1: Fetch opcode
#   - Cycle 2: Fetch immediate data
#   - Cycle 3: Write data to memory at address H:L
#
# Checkpoint Results:
#   CP1:  After MVI M,0xAA - L=0xAA (read back from memory)
#   CP2:  After MVI M,0x55 - L=0x55 (read back from memory)
#   CP3:  Verify first write - L=0xAA (still intact)
#   CP4:  After MVI M,0x00 - L=0x00 (can write zero)
#   CP5:  After MVI M,0xFF - L=0xFF (can write 0xFF)
#   CP6:  Final            - success
#
# Final Register State:
#   A: 0x00, B: 0x04
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "mvi_m_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== MVI M Write Tests ==="

# CP1: MVI M wrote 0xAA
assert_checkpoint 1 \
    "L=0xAA"

# CP2: MVI M wrote 0x55
assert_checkpoint 2 \
    "L=0x55"

# CP3: First write still intact
assert_checkpoint 3 \
    "L=0xAA"

echo ""
echo "=== Edge Case Tests ==="

# CP4: MVI M wrote 0x00 (zero edge case)
assert_checkpoint 4 \
    "L=0x00"

# CP5: MVI M wrote 0xFF
assert_checkpoint 5 \
    "L=0xFF"

echo ""
echo "=== Final State ==="

# CP6: Final success checkpoint
assert_checkpoint 6

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x04"

# Print summary and exit
print_summary
exit $?
