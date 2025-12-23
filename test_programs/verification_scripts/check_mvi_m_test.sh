#!/bin/bash

# ============================================
# MVI M (MEMORY IMMEDIATE) TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly executes:
#   - MVI M,data (Move immediate data to memory at H:L address)
#
# MVI M is a 3-cycle instruction:
#   - Cycle 1: Fetch opcode (00111110 = 0x3E)
#   - Cycle 2: Fetch immediate data
#   - Cycle 3: Write data to memory at address H:L

echo "=========================================="
echo "B8008 MVI M (Memory Immediate) Test"
echo "=========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
cd /Users/hackbook/Development/intel-8008-vhdl && make test-b8008-top ROM_FILE=test_programs/mvi_m_test_as.mem 2>&1 > mvi_m_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x00 (success marker - all tests passed)"
echo "  B = 0x04 (test counter - 4 tests completed)"
echo ""

echo "=== Final Register State ==="
tail -50 mvi_m_test.log | grep -E "Reg\.(A|B)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 mvi_m_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 mvi_m_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')

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
    echo "ALL MVI M TESTS PASSED!"
    echo "=========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - MVI M,data (Move immediate to memory)"
else
    echo "=========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "=========================================="
fi

echo ""
echo "Full output saved to: mvi_m_test.log"
echo "=========================================="
