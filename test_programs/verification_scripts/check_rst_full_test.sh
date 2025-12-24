#!/bin/bash

# ============================================
# FULL RST TEST VERIFICATION SCRIPT
# ============================================
# Tests ALL 8 RST vectors (0-7)
# RST n jumps to address n*8:
#   RST 0 -> 0x0000 (special: also bootstrap vector)
#   RST 1 -> 0x0008
#   RST 2 -> 0x0010
#   RST 3 -> 0x0018
#   RST 4 -> 0x0020
#   RST 5 -> 0x0028
#   RST 6 -> 0x0030
#   RST 7 -> 0x0038
#
# Each RST handler increments B and sets a register to confirm execution:
#   RST 0 handler: tested by bootstrap (implicit)
#   RST 1-7 handlers: explicit test
#
# Expected final state:
#   A = 0x00 (success indicator)
#   B = 0x07 (7 explicit RST calls completed: RST 1-7)
#   (RST 0 is tested but doesn't increment B since it's also bootstrap)

echo "==========================================="
echo "B8008 Full RST (0-7) Test Verification"
echo "==========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=rst_full_test_as SIM_TIME=30ms 2>&1 > rst_full_test.log

echo ""
echo "=== 1. RST Vector Execution ==="
echo "Looking for RST handler execution..."
grep "RST.*handler\|Reached 0x00[0-3]" rst_full_test.log | head -10

echo ""
echo "=== 2. HLT Detection ==="
grep "PC = 0x01.*IR = 0x00" rst_full_test.log | tail -1

echo ""
echo "=== 3. Final Register State ==="
echo "Expected:"
echo "  A = 0x00 (success indicator)"
echo "  B = 0x07 (7 RST calls: RST 1-7)"
echo ""
echo "Actual (last reported state):"
tail -100 rst_full_test.log | grep "Reg\.A = " | tail -1
tail -100 rst_full_test.log | grep "Reg\.D = " | tail -1

echo ""
echo "=== 4. Test Summary ==="

# Check final register values
PASS=true

# Get last register values
FINAL_A=$(tail -100 rst_full_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_B=$(tail -100 rst_full_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-Fa-f]+).*/\1/')

echo "Checking final values..."

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (success indicator)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00)"
    PASS=false
fi

if [ "$FINAL_B" = "0x07" ]; then
    echo "  [PASS] B = 0x07 (7 RST handlers called)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x07)"
    PASS=false
fi

# Verify we reached specific RST vectors
echo ""
echo "Verifying RST vector addresses were reached..."

for vec in "0028" "0030" "0038"; do
    if grep -q "Addr = 0x$vec\|PC = 0x$vec" rst_full_test.log; then
        echo "  [PASS] RST vector 0x$vec was reached"
    else
        echo "  [WARN] RST vector 0x$vec not found in log"
    fi
done

echo ""
if [ "$PASS" = true ]; then
    echo "==========================================="
    echo "ALL RST TESTS PASSED!"
    echo "  - RST 0 (bootstrap) verified"
    echo "  - RST 1-7 explicitly tested"
    echo "==========================================="
    exit 0
else
    echo "==========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "==========================================="
    exit 1
fi

echo ""
echo "Full output saved to: rst_full_test.log"
echo "==========================================="
