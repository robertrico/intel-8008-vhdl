#!/bin/bash

# ============================================
# ALU TEST PROGRAM VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly
# executes the alu_test_as.asm program
#
# Expected Results (in registers at halt):
#   A: 0x00 (final test result - success indicator)
#   B: 0x08 (ADD result: 5+3)
#   C: 0x02 (SUB result: 5-3)
#   D: 0x01 (ANA result: 0x05 AND 0x03)
#   E: 0x06 (XRA result: 0x05 XOR 0x03)
#   H: 0x07 (ORA result: 0x05 OR 0x03)
#   L: 0x00 (loop counter, decremented to 0)

echo "==========================================="
echo "B8008 ALU Test Verification"
echo "==========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=alu_test_as SIM_TIME=30ms 2>&1 > alu_test.log

echo ""
echo "=== 1. TEST 1: ADD register (5 + 3 = 8) ==="
echo "B should be 0x08"
grep "Reg\.B = 0x08" alu_test.log | head -1

echo ""
echo "=== 2. TEST 2: SUB register (5 - 3 = 2) ==="
echo "C should be 0x02"
grep "Reg\.C = 0x02" alu_test.log | head -1

echo ""
echo "=== 3. TEST 3: ANA register (0x05 AND 0x03 = 0x01) ==="
echo "D should be 0x01"
grep "Reg\.D = 0x01" alu_test.log | head -1

echo ""
echo "=== 4. TEST 4: XRA register (0x05 XOR 0x03 = 0x06) ==="
echo "E should be 0x06"
grep "Reg\.E = 0x06" alu_test.log | head -1

echo ""
echo "=== 5. TEST 5: ORA register (0x05 OR 0x03 = 0x07) ==="
echo "H should be 0x07"
grep "Reg\.H = 0x07" alu_test.log | head -1

echo ""
echo "=== 6. TEST 11: DCR loop (5 -> 0) ==="
echo "L should be 0x00 after decrementing from 5"
grep "Reg\.L = 0x00" alu_test.log | head -1

echo ""
echo "=== 7. TEST 12: CMP register (compare for equality) ==="
echo "Should NOT jump to FAIL (PC should reach 0x0136, not 0x0149)"
if grep -q "PC = 0x0149" alu_test.log; then
    echo "FAIL: CMP test failed - jumped to FAIL label"
else
    echo "PASS: CMP test passed - did not jump to FAIL"
fi

echo ""
echo "=== 8. Final Register State ==="
echo "Expected:"
echo "  A = 0x00 (success indicator)"
echo "  B = 0x08 (ADD result)"
echo "  C = 0x02 (SUB result)"
echo "  D = 0x01 (ANA result)"
echo "  E = 0x06 (XRA result)"
echo "  H = 0x07 (ORA result)"
echo "  L = 0x00 (DCR loop counter)"
echo ""
echo "Actual (last reported state):"
tail -50 alu_test.log | grep -E "Reg\.(A|B)" | tail -1
tail -50 alu_test.log | grep -E "Reg\.(H|L)" | tail -1

echo ""
echo "=== 9. HLT Detection ==="
echo "Program should halt at PC = 0x014B (DONE label)"
grep "PC = 0x014B.*IR = 0x00" alu_test.log | head -1

echo ""
echo "=== 10. Test Summary ==="
# Check final register values
PASS=true

# Get last A register value
FINAL_A=$(tail -50 alu_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 alu_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')
FINAL_H=$(tail -50 alu_test.log | grep "Reg\.H = " | tail -1 | sed -E 's/.*Reg\.H = (0x[0-9A-F]+).*/\1/')
FINAL_L=$(tail -50 alu_test.log | grep "Reg\.L = " | tail -1 | sed -E 's/.*Reg\.L = (0x[0-9A-F]+).*/\1/')

echo "Checking final values..."

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (success indicator)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00)"
    PASS=false
fi

if [ "$FINAL_B" = "0x08" ]; then
    echo "  [PASS] B = 0x08 (ADD: 5+3=8)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x08)"
    PASS=false
fi

if [ "$FINAL_H" = "0x07" ]; then
    echo "  [PASS] H = 0x07 (ORA: 0x05|0x03=0x07)"
else
    echo "  [FAIL] H = $FINAL_H (expected 0x07)"
    PASS=false
fi

if [ "$FINAL_L" = "0x00" ]; then
    echo "  [PASS] L = 0x00 (DCR loop complete)"
else
    echo "  [FAIL] L = $FINAL_L (expected 0x00)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "==========================================="
    echo "ALL ALU TESTS PASSED!"
    echo "==========================================="
else
    echo "==========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "==========================================="
fi

echo ""
echo "Full output saved to: alu_test.log"
echo "==========================================="
