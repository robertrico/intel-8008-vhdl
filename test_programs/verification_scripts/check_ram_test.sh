#!/bin/bash

# ============================================
# RAM INTENSIVE PROGRAM TEST VERIFICATION
# ============================================
# This script verifies the b8008 CPU correctly
# executes the ram_intensive_as.asm program

echo "==========================================="
echo "B8008 RAM Intensive Test Verification"
echo "==========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=ram_intensive_as 2>&1 > ram_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0xF0 (last inverted value: 0x0F XOR 0xFF)"
echo "  B = 0xFF (first inverted value: 0x00 XOR 0xFF)"
echo "  H = 0x10 (RAM base high)"
echo "  L = 0x0F (last array index)"
echo ""

echo "=== Final Register State ==="
tail -50 ram_test.log | grep -E "Reg\.(A|B)" | tail -1
tail -50 ram_test.log | grep -E "Reg\.(H|L)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 ram_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 ram_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')
FINAL_H=$(tail -50 ram_test.log | grep "Reg\.H = " | tail -1 | sed -E 's/.*Reg\.H = (0x[0-9A-F]+).*/\1/')
FINAL_L=$(tail -50 ram_test.log | grep "Reg\.L = " | tail -1 | sed -E 's/.*Reg\.L = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0xF0" ]; then
    echo "  [PASS] A = 0xF0 (last inverted value)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0xF0)"
    PASS=false
fi

if [ "$FINAL_B" = "0xFF" ]; then
    echo "  [PASS] B = 0xFF (first inverted value)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0xFF)"
    PASS=false
fi

if [ "$FINAL_H" = "0x10" ]; then
    echo "  [PASS] H = 0x10 (RAM base high)"
else
    echo "  [FAIL] H = $FINAL_H (expected 0x10)"
    PASS=false
fi

if [ "$FINAL_L" = "0x0F" ]; then
    echo "  [PASS] L = 0x0F (last array index)"
else
    echo "  [FAIL] L = $FINAL_L (expected 0x0F)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "==========================================="
    echo "ALL RAM TESTS PASSED!"
    echo "==========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - MOV r,M (Read from RAM)"
    echo "  - MOV M,r (Write to RAM)"
    echo "  - ADD r (Add register)"
    echo "  - XRI (XOR immediate)"
    echo "  - INR (Increment register)"
    echo "  - CALL/RET (Subroutine)"
    echo "  - JNZ (Conditional jump)"
else
    echo "==========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "==========================================="
fi

echo ""
echo "Full output saved to: ram_test.log"
echo "==========================================="
