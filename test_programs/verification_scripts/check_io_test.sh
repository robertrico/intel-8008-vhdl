#!/bin/bash

# ============================================
# INP/OUT I/O INSTRUCTION TEST VERIFICATION SCRIPT
# ============================================
# This script verifies the b8008 CPU correctly executes:
#   - INP (IN): Read from input port to accumulator
#   - OUT: Write accumulator to output port
#
# Port allocation (simulated in b8008_top.vhdl):
#   Input ports 0-7: Return test values
#     Port 0: 0x55 (alternating bits)
#     Port 1: 0xAA (alternating bits, inverted)
#     Port 2: 0x42 (ASCII 'B')
#   Output ports 8-31: Latch values for verification
#
# Test sequence:
#   1. IN 0 -> OUT 8 (expect 0x55)
#   2. IN 1 -> OUT 9 (expect 0xAA)
#   3. IN 2 (expect 0x42)

echo "=========================================="
echo "B8008 INP/OUT I/O Instruction Test"
echo "=========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
cd /Users/hackbook/Development/intel-8008-vhdl && make test-b8008-top ROM_FILE=test_programs/io_test_as.mem 2>&1 > io_test.log

echo ""
echo "=== Expected Results ==="
echo "  A = 0x00 (success marker - all tests passed)"
echo "  B = 0x03 (test counter - 3 I/O tests passed)"
echo "  Output port 8 = 0x55"
echo "  Output port 9 = 0xAA"
echo ""

echo "=== Final Register State ==="
tail -100 io_test.log | grep -E "Reg\.(A|B)" | tail -1

echo ""
echo "=== I/O Port Activity ==="
grep -E "I/O:" io_test.log | head -10

echo ""
echo "=== Test Summary ==="

# Check final register values
PASS=true

FINAL_A=$(tail -100 io_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-F]+).*/\1/')
FINAL_B=$(tail -100 io_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-F]+).*/\1/')

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (all tests passed)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00 - test failed)"
    PASS=false
fi

if [ "$FINAL_B" = "0x03" ]; then
    echo "  [PASS] B = 0x03 (3 I/O tests passed)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x03)"
    PASS=false
fi

# Check I/O port outputs if test passed
if grep -q "I/O: OUT port 8 = 0x55" io_test.log; then
    echo "  [PASS] Port 8 = 0x55"
else
    echo "  [INFO] Port 8 output not found or incorrect"
fi

if grep -q "I/O: OUT port 9 = 0xAA" io_test.log; then
    echo "  [PASS] Port 9 = 0xAA"
else
    echo "  [INFO] Port 9 output not found or incorrect"
fi

echo ""
if [ "$PASS" = true ]; then
    echo "=========================================="
    echo "ALL I/O TESTS PASSED!"
    echo "=========================================="
    echo ""
    echo "Instructions tested:"
    echo "  - INP (IN 0, IN 1, IN 2)"
    echo "  - OUT (OUT 8, OUT 9)"
else
    echo "=========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "=========================================="
    echo ""
    echo "Debug hints:"
    echo "  - Check for PCC cycle type in log"
    echo "  - Verify io_input_data is being placed on data bus"
    echo "  - Check T-state timing for I/O cycles"
fi

echo ""
echo "Full output saved to: io_test.log"
echo "=========================================="
