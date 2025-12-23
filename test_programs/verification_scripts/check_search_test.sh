#!/bin/bash

# ============================================
# SEARCH PROGRAM TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly
# executes the search_as.asm program

echo "=========================================="
echo "B8008 Search Program Test Verification"
echo "=========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=search_as 2>&1 > search_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x2E (period character '.')"
echo "  H = 0x2E (copied from A by MOV H,A)"
echo "  L = 0xD4 (position 212 where period found)"
echo ""

echo "=== Final Register State ==="
tail -50 search_test.log | grep -E "Reg\.(A|B)" | tail -1
tail -50 search_test.log | grep -E "Reg\.(H|L)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 search_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_H=$(tail -50 search_test.log | grep "Reg\.H = " | tail -1 | sed -E 's/.*Reg\.H = (0x[0-9A-F]+).*/\1/')
FINAL_L=$(tail -50 search_test.log | grep "Reg\.L = " | tail -1 | sed -E 's/.*Reg\.L = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0x2E" ]; then
    echo "  [PASS] A = 0x2E (period character)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x2E)"
    PASS=false
fi

if [ "$FINAL_H" = "0x2E" ]; then
    echo "  [PASS] H = 0x2E (copied from A)"
else
    echo "  [FAIL] H = $FINAL_H (expected 0x2E)"
    PASS=false
fi

if [ "$FINAL_L" = "0xD4" ]; then
    echo "  [PASS] L = 0xD4 (position 212)"
else
    echo "  [FAIL] L = $FINAL_L (expected 0xD4)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "=========================================="
    echo "ALL SEARCH TESTS PASSED!"
    echo "=========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - MOV r,M (Read from memory)"
    echo "  - MOV r,r (Register to register)"
    echo "  - CPI (Compare immediate)"
    echo "  - JZ (Jump on zero)"
    echo "  - JNZ (Jump on not zero)"
    echo "  - INR (Increment register)"
    echo "  - CALL/RET (Subroutine)"
else
    echo "=========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "=========================================="
fi

echo ""
echo "Full output saved to: search_test.log"
echo "=========================================="
