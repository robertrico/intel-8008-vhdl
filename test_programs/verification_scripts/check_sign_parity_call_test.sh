#!/bin/bash

# ============================================
# SIGN/PARITY CONDITIONAL CALL TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly executes:
#   - CP (Call on Positive / Sign=0)
#   - CM (Call on Minus / Sign=1)
#   - CPO (Call on Parity Odd)
#   - CPE (Call on Parity Even)

echo "=========================================="
echo "B8008 Sign/Parity Conditional Call Test"
echo "=========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=sign_parity_call_test_as 2>&1 > sign_parity_call_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x00 (success marker - all tests passed)"
echo "  B = 0x04 (test counter - 4 tests completed)"
echo ""

echo "=== Final Register State ==="
tail -50 sign_parity_call_test.log | grep -E "Reg\.(A|B)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 sign_parity_call_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 sign_parity_call_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (all tests passed)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00 - test failed)"
    PASS=false
fi

if [ "$FINAL_B" = "0x04" ]; then
    echo "  [PASS] B = 0x04 (4 tests completed)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x04)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "=========================================="
    echo "ALL SIGN/PARITY CALL TESTS PASSED!"
    echo "=========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - CP (Call on Positive / Sign=0)"
    echo "  - CM (Call on Minus / Sign=1)"
    echo "  - CPO (Call on Parity Odd)"
    echo "  - CPE (Call on Parity Even)"
else
    echo "=========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "=========================================="
fi

echo ""
echo "Full output saved to: sign_parity_call_test.log"
echo "=========================================="
