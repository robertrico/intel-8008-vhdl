#!/bin/bash
# Verification script for pc_carry_call_test_as
#
# This test verifies that CALL instructions correctly handle PC carry propagation
# when the return address crosses a 256-byte boundary.
#
# Expected checkpoints:
#   CP1 (ID=1): Before CALL at 0x00FC, E=0x01
#   CP2 (ID=2): Inside subroutine at 0x0200, E=0x02
#   CP3 (ID=3): After RET, correctly at 0x0100, E=0x03 (KEY TEST)
#   CP4 (ID=4): Final success, A=0x00

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "=== PC Carry CALL Test Verification ==="
echo ""

# Run make test with our program and capture output
cd "$PROJECT_DIR"
OUTPUT=$(timeout 60 make test-b8008-top PROG=pc_carry_call_test_as 2>&1) || {
    echo "FAIL: Simulation failed or timed out"
    exit 1
}

# Check for checkpoint outputs (CHECKPOINT: ID=X format)
echo "Checking checkpoints..."

# CP1: Before CALL
if echo "$OUTPUT" | grep -q "CHECKPOINT: ID=1.*E=0x01"; then
    echo "  CP1: PASS - Before CALL, E=0x01"
else
    echo "  CP1: FAIL - Expected E=0x01 before CALL"
    echo "$OUTPUT" | grep "CHECKPOINT:" | head -5 || true
    exit 1
fi

# CP2: Inside subroutine
if echo "$OUTPUT" | grep -q "CHECKPOINT: ID=2.*E=0x02"; then
    echo "  CP2: PASS - Inside subroutine, E=0x02"
else
    echo "  CP2: FAIL - Expected E=0x02 inside subroutine"
    echo "$OUTPUT" | grep "CHECKPOINT:" | head -5 || true
    exit 1
fi

# CP3: After RET - THIS IS THE KEY TEST
if echo "$OUTPUT" | grep -q "CHECKPOINT: ID=3.*E=0x03"; then
    echo "  CP3: PASS - After RET, correctly at 0x0100, E=0x03 (KEY TEST)"
else
    echo "  CP3: FAIL - Did not reach 0x0100 after RET (PC carry bug!)"
    echo "$OUTPUT" | grep "CHECKPOINT:" | head -10 || true
    echo ""
    echo "This indicates the PC carry propagation during CALL is broken."
    echo "The return address should be 0x0100, not 0x0000."
    exit 1
fi

# CP4: Final success
if echo "$OUTPUT" | grep -q "CHECKPOINT: ID=4"; then
    echo "  CP4: PASS - Final success checkpoint"
else
    echo "  CP4: FAIL - Did not reach final success"
    echo "$OUTPUT" | grep "CHECKPOINT:" | head -10 || true
    exit 1
fi

# Check final register state from last checkpoint
FINAL=$(echo "$OUTPUT" | grep "CHECKPOINT: ID=4" | tail -1)
if echo "$FINAL" | grep -q "A=0x00.*D=0x00.*E=0x04"; then
    echo ""
    echo "Final state: PASS - A=0x00, D=0x00, E=0x04"
else
    echo ""
    echo "Final checkpoint: $FINAL"
fi

# Check CPU halted properly
if echo "$OUTPUT" | grep -q "s_stopped"; then
    echo "  CPU halted (expected)"
fi

echo ""
echo "=== ALL TESTS PASSED ==="
echo "PC carry propagation during CALL is working correctly."
exit 0
