#!/bin/bash

# ============================================
# MEMORY ALU OPERATIONS TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly
# executes memory-based ALU operations:
#   - ADC M (Add memory with carry)
#   - SBB M (Subtract memory with borrow)
#   - ANA M (AND memory)
#   - XRA M (XOR memory)
#   - ORA M (OR memory)
#   - CMP M (Compare memory)

echo "=========================================="
echo "B8008 Memory ALU Operations Test"
echo "=========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=memory_alu_test_as 2>&1 > memory_alu_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x00 (success marker - all tests passed)"
echo "  B = 0x01 (test counter showing completion)"
echo "  H = 0x00 (high byte of memory pointer)"
echo "  L = 0xF0 (low byte - points to test data area)"
echo ""

echo "=== Final Register State ==="
tail -50 memory_alu_test.log | grep -E "Reg\.(A|B)" | tail -1
tail -50 memory_alu_test.log | grep -E "Reg\.(H|L)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 memory_alu_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 memory_alu_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')
FINAL_H=$(tail -50 memory_alu_test.log | grep "Reg\.H = " | tail -1 | sed -E 's/.*Reg\.H = (0x[0-9A-F]+).*/\1/')
FINAL_L=$(tail -50 memory_alu_test.log | grep "Reg\.L = " | tail -1 | sed -E 's/.*Reg\.L = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (all tests passed)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00 - test failed)"
    PASS=false
fi

if [ "$FINAL_B" = "0x01" ]; then
    echo "  [PASS] B = 0x01 (test completion marker)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x01)"
    PASS=false
fi

if [ "$FINAL_H" = "0x00" ]; then
    echo "  [PASS] H = 0x00 (memory pointer high)"
else
    echo "  [FAIL] H = $FINAL_H (expected 0x00)"
    PASS=false
fi

if [ "$FINAL_L" = "0xF0" ]; then
    echo "  [PASS] L = 0xF0 (memory pointer low)"
else
    echo "  [FAIL] L = $FINAL_L (expected 0xF0)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "=========================================="
    echo "ALL MEMORY ALU TESTS PASSED!"
    echo "=========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - ADC M (Add memory with carry)"
    echo "  - SBB M (Subtract memory with borrow)"
    echo "  - ANA M (AND memory)"
    echo "  - XRA M (XOR memory)"
    echo "  - ORA M (OR memory)"
    echo "  - CMP M (Compare memory)"
else
    echo "=========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "=========================================="
fi

echo ""
echo "Full output saved to: memory_alu_test.log"
echo "=========================================="
