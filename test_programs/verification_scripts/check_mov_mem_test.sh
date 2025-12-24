#!/bin/bash

# ============================================================================
# MOV r,M / MOV M,r TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive MOV memory instruction test with checkpoint assertions
#
# Program: mov_mem_test_as.asm
#
# Tests all 14 MOV memory instruction combinations:
#   7 MOV r,M tests (read from memory)
#   7 MOV M,r tests (write to memory)
#
# Checkpoint Results:
#   CP1-CP7:  MOV r,M tests (read from memory)
#   CP8-CP14: MOV M,r tests (write to memory)
#   CP15:     Final success
#
# Final Register State:
#   A: 0x00, B: 0x0E (14 tests)
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "mov_mem_test_as" "30ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== MOV r,M Tests (Read from Memory) ==="

# CP1: MOV A,M
assert_checkpoint 1 \
    "L=0x11"

# CP2: MOV B,M
assert_checkpoint 2 \
    "L=0x22"

# CP3: MOV C,M
assert_checkpoint 3 \
    "L=0x33"

# CP4: MOV D,M
assert_checkpoint 4 \
    "L=0x44"

# CP5: MOV E,M
assert_checkpoint 5 \
    "L=0x55"

# CP6: MOV H,M (tricky - H changes!)
assert_checkpoint 6 \
    "L=0x66"

# CP7: MOV L,M (tricky - L changes!)
assert_checkpoint 7 \
    "E=0x77"

echo ""
echo "=== MOV M,r Tests (Write to Memory) ==="

# CP8: MOV M,A
assert_checkpoint 8 \
    "L=0xAA"

# CP9: MOV M,B
assert_checkpoint 9 \
    "L=0x08"

# CP10: MOV M,C
assert_checkpoint 10 \
    "L=0xBB"

# CP11: MOV M,D
assert_checkpoint 11 \
    "L=0xCC"

# CP12: MOV M,E
assert_checkpoint 12 \
    "L=0xDD"

# CP13: MOV M,H
assert_checkpoint 13 \
    "L=0x10"

# CP14: MOV M,L
assert_checkpoint 14 \
    "L=0x0E"

echo ""
echo "=== Final State ==="

# CP15: Final success checkpoint
assert_checkpoint 15

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x0E"

# Print summary and exit
print_summary
exit $?
