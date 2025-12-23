#!/bin/bash

# ============================================
# SIGN AND PARITY TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly
# executes the sign_parity_test_as.asm program

echo "==========================================="
echo "B8008 Sign and Parity Test Verification"
echo "==========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=sign_parity_test_as SIM_TIME=30ms 2>&1 > sign_parity_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x00 (success indicator)"
echo "  B = 0x01 (test 1 passed marker)"
echo "  H = 0x10 (RAM pointer high)"
echo "  L = 0x08 (final test marker)"
echo ""

echo "=== Final Register State ==="
tail -50 sign_parity_test.log | grep -E "Reg\.(A|B)" | tail -1
tail -50 sign_parity_test.log | grep -E "Reg\.(H|L)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 sign_parity_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 sign_parity_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')
FINAL_H=$(tail -50 sign_parity_test.log | grep "Reg\.H = " | tail -1 | sed -E 's/.*Reg\.H = (0x[0-9A-F]+).*/\1/')
FINAL_L=$(tail -50 sign_parity_test.log | grep "Reg\.L = " | tail -1 | sed -E 's/.*Reg\.L = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (success indicator)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00)"
    PASS=false
fi

if [ "$FINAL_B" = "0x01" ]; then
    echo "  [PASS] B = 0x01 (test 1 passed marker)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x01)"
    PASS=false
fi

if [ "$FINAL_H" = "0x10" ]; then
    echo "  [PASS] H = 0x10 (RAM pointer high)"
else
    echo "  [FAIL] H = $FINAL_H (expected 0x10)"
    PASS=false
fi

if [ "$FINAL_L" = "0x08" ]; then
    echo "  [PASS] L = 0x08 (final test marker)"
else
    echo "  [FAIL] L = $FINAL_L (expected 0x08)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "==========================================="
    echo "ALL SIGN/PARITY TESTS PASSED!"
    echo "==========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - JP  (Jump on Positive)"
    echo "  - JM  (Jump on Minus)"
    echo "  - JPE (Jump on Parity Even)"
    echo "  - JPO (Jump on Parity Odd)"
    echo "  - RP  (Return on Positive)"
    echo "  - RM  (Return on Minus)"
    echo "  - RPE (Return on Parity Even)"
    echo "  - RPO (Return on Parity Odd)"
    echo "  - ORI (OR Immediate - used to set flags)"
else
    echo "==========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "==========================================="
fi

echo ""
echo "Full output saved to: sign_parity_test.log"
echo "==========================================="
