#!/bin/bash

# ============================================================================
# MOV R,R TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive MOV register-to-register instruction test
#
# Program: mov_rr_test_as.asm
#
# Tests all MOV r,r combinations through:
#   - Forward chain: A -> B -> C -> D -> E -> H -> L
#   - Reverse chain: L -> H -> E -> D -> C -> B -> A
#   - Cross-register MOV A,X tests
#   - Register swap tests (B<->C, D<->E, H<->L)
#   - MOV X,X (NOP) preservation tests
#
# Checkpoint Results:
#   CP1:  Initial state - unique values in all registers
#   CP2:  MOV B,A - B=0xAA
#   CP3:  MOV C,B - C=0xAA
#   CP4:  MOV D,C - D=0xAA
#   CP5:  MOV E,D - E=0xAA
#   CP6:  MOV H,E - H=0xAA
#   CP7:  MOV L,H - L=0xAA (chain complete)
#   CP8:  Reverse chain - all regs=0x55
#   CP9:  MOV A,B - L=0xB2
#   CP10: MOV A,C - L=0xC3
#   CP11: MOV A,D - L=0xD4
#   CP12: MOV A,E - L=0xE5
#   CP13: MOV A,H - L=0x16
#   CP14: MOV A,L - B=0x16
#   CP15: B<->C swap - B=0xC0, C=0xB0
#   CP16: D<->E swap - D=0xE0, E=0xD0
#   CP17: H<->L swap - H=0x00, L=0xF0
#   CP18: MOV X,X - values preserved
#   CP19: Final success
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "mov_rr_test_as" "20ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Initial State ==="

# CP1: Initial unique values
assert_checkpoint 1 \
    "B=0xBB" \
    "C=0xCC" \
    "D=0xDD" \
    "E=0xEE" \
    "H=0x11" \
    "L=0x22"

echo ""
echo "=== Forward Chain (A -> B -> C -> D -> E -> H -> L) ==="

# CP2: MOV B,A - B now has 0xAA
assert_checkpoint 2 \
    "B=0xAA"

# CP3: MOV C,B - C now has 0xAA
assert_checkpoint 3 \
    "C=0xAA"

# CP4: MOV D,C - D now has 0xAA
assert_checkpoint 4 \
    "D=0xAA"

# CP5: MOV E,D - E now has 0xAA
assert_checkpoint 5 \
    "E=0xAA"

# CP6: MOV H,E - H now has 0xAA
assert_checkpoint 6 \
    "H=0xAA"

# CP7: MOV L,H - L now has 0xAA (chain complete)
assert_checkpoint 7 \
    "L=0xAA"

echo ""
echo "=== Reverse Chain (L -> ... -> A) ==="

# CP8: All registers now 0x55
assert_checkpoint 8 \
    "B=0x55" \
    "C=0x55" \
    "D=0x55" \
    "E=0x55" \
    "H=0x55" \
    "L=0x55"

echo ""
echo "=== MOV A,X Tests ==="

# CP9: MOV A,B - L saved as 0xB2
assert_checkpoint 9 \
    "L=0xB2"

# CP10: MOV A,C - L saved as 0xC3
assert_checkpoint 10 \
    "L=0xC3"

# CP11: MOV A,D - L saved as 0xD4
assert_checkpoint 11 \
    "L=0xD4"

# CP12: MOV A,E - L saved as 0xE5
assert_checkpoint 12 \
    "L=0xE5"

# CP13: MOV A,H - L saved as 0x16
assert_checkpoint 13 \
    "L=0x16"

# CP14: MOV A,L - B saved as 0x16
assert_checkpoint 14 \
    "B=0x16"

echo ""
echo "=== Register Swap Tests ==="

# CP15: B<->C swap
assert_checkpoint 15 \
    "B=0xC0" \
    "C=0xB0"

# CP16: D<->E swap
assert_checkpoint 16 \
    "D=0xE0" \
    "E=0xD0"

# CP17: H<->L swap
assert_checkpoint 17 \
    "H=0x00" \
    "L=0xF0"

echo ""
echo "=== MOV X,X (NOP) Preservation Tests ==="

# CP18: All MOV X,X preserved original values
assert_checkpoint 18 \
    "B=0x5B" \
    "C=0x5C" \
    "D=0x5D" \
    "E=0x5E" \
    "H=0x5F" \
    "L=0x50"

echo ""
echo "=== Final State ==="

# CP19: Final success
assert_checkpoint 19 \
    "A=0x13"

# Verify final state
assert_final_state \
    "A=0x00" \
    "B=0x5B" \
    "C=0x5C" \
    "D=0x5D" \
    "E=0x5E" \
    "H=0x5F" \
    "L=0x50"

# Print summary and exit
print_summary
exit $?
