#!/bin/bash

# ============================================================================
# INP/OUT I/O INSTRUCTION TEST VERIFICATION SCRIPT
# ============================================================================
# Comprehensive I/O instruction test with checkpoint assertions
#
# Program: io_test_as.asm
#
# Tests I/O instructions:
#   - INP (IN): Read from input port to accumulator
#   - OUT: Write accumulator to output port
#
# Port allocation (simulated in b8008_top.vhdl):
#   Input ports 0-7: Return test values
#     Port 0: 0x55, Port 1: 0xAA, Port 2: 0x42
#   Output ports 8-31: Latch values for verification
#
# Checkpoint Results:
#   CP1:  After IN 0  - L=0x55
#   CP2:  After OUT 8 - port 8 written
#   CP3:  After IN 1  - L=0xAA
#   CP4:  After OUT 9 - port 9 written
#   CP5:  After IN 2  - L=0x42
#   CP6:  Final       - success
#
# Final Register State:
#   A: 0x00, B: 0x03
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "io_test_as" "10ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Input Port Tests ==="

# CP1: IN 0 (expect 0x55)
assert_checkpoint 1 \
    "L=0x55"

# CP2: OUT 8 executed
assert_checkpoint 2

# CP3: IN 1 (expect 0xAA)
assert_checkpoint 3 \
    "L=0xAA"

# CP4: OUT 9 executed
assert_checkpoint 4

# CP5: IN 2 (expect 0x42)
assert_checkpoint 5 \
    "L=0x42"

echo ""
echo "=== Final State ==="

# CP6: Final success checkpoint
assert_checkpoint 6

# Verify final state via traditional method
assert_final_state \
    "A=0x00" \
    "B=0x03"

# Print summary and exit
print_summary
exit $?
