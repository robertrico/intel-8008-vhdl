#!/bin/bash

# ============================================
# CONDITIONAL CALL AND CARRY IMMEDIATE TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly executes:
#   - ACI (Add immediate with carry)
#   - SBI (Subtract immediate with borrow)
#   - CNC (Call on no carry)
#   - CC (Call on carry)
#   - CNZ (Call on not zero)
#   - CZ (Call on zero)
#   - RZ (Return on zero)

echo "=========================================="
echo "B8008 Conditional Call & Carry Imm Test"
echo "=========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=conditional_call_test_as 2>&1 > conditional_call_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x00 (success marker - all tests passed)"
echo "  B = 0x07 (test counter - 7 tests completed)"
echo ""

echo "=== Final Register State ==="
tail -50 conditional_call_test.log | grep -E "Reg\.(A|B)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 conditional_call_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 conditional_call_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (all tests passed)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00 - test failed)"
    PASS=false
fi

if [ "$FINAL_B" = "0x07" ]; then
    echo "  [PASS] B = 0x07 (7 tests completed)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x07)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "=========================================="
    echo "ALL CONDITIONAL CALL TESTS PASSED!"
    echo "=========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - ACI (Add immediate with carry)"
    echo "  - SBI (Subtract immediate with borrow)"
    echo "  - CNC (Call on no carry)"
    echo "  - CC (Call on carry)"
    echo "  - CNZ (Call on not zero)"
    echo "  - CZ (Call on zero)"
    echo "  - RZ (Return on zero)"
else
    echo "=========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "=========================================="
fi

echo ""
echo "Full output saved to: conditional_call_test.log"
echo "=========================================="
