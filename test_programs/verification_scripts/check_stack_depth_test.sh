#!/bin/bash

# ============================================
# STACK DEPTH TEST VERIFICATION SCRIPT
# ============================================
# Tests the 8-level internal stack of the Intel 8008
#
# The 8008 has an 8-level hardware stack for CALL/RET/RST
# This test verifies:
#   1. 6 nested CALLs work correctly (using stack levels 0-5)
#   2. All 6 RETurns work correctly
#   3. Each level preserves the return address correctly
#
# Test approach:
#   - Call SUB1 which calls SUB2 which calls... SUB6
#   - Each subroutine increments a register to prove it was called
#   - Each RET must return to the correct level
#
# Expected final state:
#   A = 0x00 (success indicator)
#   B = 0x06 (6 subroutines called)
#   C = 0x06 (6 returns completed)

echo "==========================================="
echo "B8008 Stack Depth (6-level) Test"
echo "==========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=stack_depth_test_as SIM_TIME=30ms 2>&1 > stack_depth_test.log

echo ""
echo "=== 1. Nested CALL Execution ==="
echo "Looking for stack operations..."
grep "STACK_PTR:" stack_depth_test.log | head -15

echo ""
echo "=== 2. HLT Detection ==="
grep "PC = 0x01.*IR = 0x00" stack_depth_test.log | tail -1

echo ""
echo "=== 3. Final Register State ==="
echo "Expected:"
echo "  A = 0x00 (success indicator)"
echo "  B = 0x06 (6 nested CALLs completed)"
echo "  C = 0x06 (6 RETurns completed)"
echo ""
echo "Actual (last reported state):"
tail -100 stack_depth_test.log | grep "Reg\.A = " | tail -1
tail -100 stack_depth_test.log | grep "Reg\.B = " | tail -1
tail -100 stack_depth_test.log | grep "Reg\.C = " | tail -1

echo ""
echo "=== 4. Test Summary ==="

# Check final register values
PASS=true

# Get last register values
FINAL_A=$(tail -100 stack_depth_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_B=$(tail -100 stack_depth_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_C=$(tail -100 stack_depth_test.log | grep "Reg\.C = " | tail -1 | sed -E 's/.*Reg\.C = (0x[0-9A-Fa-f]+).*/\1/')

echo "Checking final values..."

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (success indicator)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00)"
    PASS=false
fi

if [ "$FINAL_B" = "0x06" ]; then
    echo "  [PASS] B = 0x06 (6 nested CALLs)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x06)"
    PASS=false
fi

if [ "$FINAL_C" = "0x06" ]; then
    echo "  [PASS] C = 0x06 (6 RETurns completed)"
else
    echo "  [FAIL] C = $FINAL_C (expected 0x06)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "==========================================="
    echo "ALL STACK DEPTH TESTS PASSED!"
    echo "  - 6 nested CALLs executed"
    echo "  - 6 RETurns completed correctly"
    echo "  - Stack levels 0-5 verified"
    echo "==========================================="
    exit 0
else
    echo "==========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "==========================================="
    exit 1
fi

echo ""
echo "Full output saved to: stack_depth_test.log"
echo "==========================================="
