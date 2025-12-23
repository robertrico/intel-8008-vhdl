#!/bin/bash

# ============================================
# RST (RESTART) INSTRUCTION TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly executes:
#   - RST 1 (jump to 0x0008)
#   - RST 2 (jump to 0x0010)
#   - RST 3 (jump to 0x0018)
#   - RST 4 (jump to 0x0020)
#
# RST is a 1-cycle instruction that:
#   - Pushes return address to stack
#   - Jumps to address AAA * 8 (RST vector)

echo "=========================================="
echo "B8008 RST (Restart) Instruction Test"
echo "=========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
cd /Users/hackbook/Development/intel-8008-vhdl && make test-b8008-top ROM_FILE=test_programs/rst_test_as.mem 2>&1 > rst_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x00 (success marker - all tests passed)"
echo "  B = 0x04 (test counter - 4 RST handlers called)"
echo ""

echo "=== Final Register State ==="
tail -50 rst_test.log | grep -E "Reg\.(A|B)" | tail -1

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -50 rst_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -50 rst_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (all tests passed)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00 - test failed)"
    PASS=false
fi

if [ "$FINAL_B" = "0x04" ]; then
    echo "  [PASS] B = 0x04 (4 RST handlers called)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x04)"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "=========================================="
    echo "ALL RST TESTS PASSED!"
    echo "=========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - RST 1 (jump to 0x0008)"
    echo "  - RST 2 (jump to 0x0010)"
    echo "  - RST 3 (jump to 0x0018)"
    echo "  - RST 4 (jump to 0x0020)"
    echo "  - RET (return from RST handler)"
else
    echo "=========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "=========================================="
fi

echo ""
echo "Full output saved to: rst_test.log"
echo "=========================================="
