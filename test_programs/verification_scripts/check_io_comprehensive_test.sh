#!/bin/bash

# ============================================================================
# COMPREHENSIVE I/O TEST VERIFICATION SCRIPT
# ============================================================================
# Tests all I/O instructions comprehensively
#
# Program: io_comprehensive_test_as.asm
#
# Tests:
#   - INP 0-7: All 8 input ports with expected values
#   - OUT 8-30: Output port writes (port 31 is checkpoint)
#
# Input port expected values (from b8008_top.vhdl):
#   Port 0: 0x55
#   Port 1: 0xAA
#   Port 2: 0x42
#   Port 3: 0x03
#   Port 4: 0x04
#   Port 5: 0x05
#   Port 6: 0x06
#   Port 7: 0x07
#
# Checkpoint Results:
#   CP1:  IN 0 - L=0x55
#   CP2:  IN 1 - L=0xAA
#   CP3:  IN 2 - L=0x42
#   CP4:  IN 3 - L=0x03
#   CP5:  IN 4 - L=0x04
#   CP6:  IN 5 - L=0x05
#   CP7:  IN 6 - L=0x06
#   CP8:  IN 7 - L=0x07
#   CP9:  OUT 8-15 complete
#   CP10: OUT 16-23 complete
#   CP11: OUT 24-30 complete
#   CP12: Final success
# ============================================================================

# Source the checkpoint library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

# Run the test
run_test "io_comprehensive_test_as" "20ms"

# List all checkpoints found
list_checkpoints

echo ""
echo "=== Input Port Tests (INP 0-7) ==="

# CP1: IN 0 - expect 0x55
assert_checkpoint 1 \
    "L=0x55"

# CP2: IN 1 - expect 0xAA
assert_checkpoint 2 \
    "L=0xAA"

# CP3: IN 2 - expect 0x42
assert_checkpoint 3 \
    "L=0x42"

# CP4: IN 3 - expect 0x03
assert_checkpoint 4 \
    "L=0x03"

# CP5: IN 4 - expect 0x04
assert_checkpoint 5 \
    "L=0x04"

# CP6: IN 5 - expect 0x05
assert_checkpoint 6 \
    "L=0x05"

# CP7: IN 6 - expect 0x06
assert_checkpoint 7 \
    "L=0x06"

# CP8: IN 7 - expect 0x07
assert_checkpoint 8 \
    "L=0x07"

echo ""
echo "=== Output Port Tests ==="

# CP9: OUT 8-15 complete
assert_checkpoint 9 \
    "A=0x09"

# CP10: OUT 16-23 complete
assert_checkpoint 10 \
    "A=0x0A"

# CP11: OUT 24-30 complete
assert_checkpoint 11 \
    "A=0x0B"

echo ""
echo "=== Final State ==="

# CP12: Final success
assert_checkpoint 12 \
    "A=0x0C"

# Verify final state
assert_final_state \
    "A=0x00"

# Print summary and exit
print_summary
exit $?
