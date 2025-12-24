#!/bin/bash

# ============================================
# FLAG VERIFICATION TEST SCRIPT
# ============================================
# Verifies all four condition flags work correctly:
#   - Carry flag (C)
#   - Zero flag (Z)
#   - Sign flag (S) - bit 7 of result
#   - Parity flag (P) - even parity = 1
#
# Tests edge cases: 0x00, 0x80, 0xFF, carry/borrow conditions
#
# ASSERTION MARKERS:
#   ZERO_TEST: After ADI 0 to 0x00, Z='1', S='0', P='1' (0x00 has even parity)
#   SIGN_TEST: After loading 0x80, S='1'
#   CARRY_TEST: After 0xFF + 1, C='1', Z='1'
#   PARITY_ODD: After loading 0x01, P='0' (odd parity)
#   PARITY_EVEN: After loading 0x03, P='1' (two 1-bits = even)
#
# Expected final state:
#   A = 0x00 (success indicator)
#   B = 0x08 (8 tests passed)

echo "==========================================="
echo "B8008 Flag Verification Test"
echo "==========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=flag_test_as SIM_TIME=30ms 2>&1 > flag_test.log

echo ""
echo "=== 1. Zero Flag (Z) Tests ==="
echo "Looking for Z='1' after operations that produce zero..."
grep "Flags:.*Z='1'" flag_test.log | head -3

echo ""
echo "=== 2. Sign Flag (S) Tests ==="
echo "Looking for S='1' when bit 7 is set..."
grep "Flags:.*S='1'" flag_test.log | head -3

echo ""
echo "=== 3. Carry Flag (C) Tests ==="
echo "Looking for C='1' after overflow..."
grep "Flags:.*C='1'" flag_test.log | head -3

echo ""
echo "=== 4. Parity Flag (P) Tests ==="
echo "Looking for parity changes..."
grep "Flags:" flag_test.log | head -10

echo ""
echo "=== 5. HLT Detection ==="
grep "PC = 0x01.*IR = 0x00" flag_test.log | tail -1

echo ""
echo "=== 6. Final Register State ==="
echo "Expected:"
echo "  A = 0x00 (success indicator)"
echo "  B = 0x08 (8 tests passed)"
echo ""
echo "Actual (last reported state):"
tail -100 flag_test.log | grep "Reg\.A = " | tail -1
tail -100 flag_test.log | grep "Flags:" | tail -1

echo ""
echo "=== 7. Test Summary ==="

# Check final register values
PASS=true

# Get last register values
FINAL_A=$(tail -100 flag_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_B=$(tail -100 flag_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-Fa-f]+).*/\1/')

echo "Checking final values..."

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (success indicator)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00)"
    PASS=false
fi

if [ "$FINAL_B" = "0x08" ]; then
    echo "  [PASS] B = 0x08 (8 tests passed)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x08)"
    PASS=false
fi

# Check that we saw the expected flag patterns
echo ""
echo "Verifying flag patterns in log..."

# Zero flag should be set at some point
if grep -q "Flags:.*Z='1'" flag_test.log; then
    echo "  [PASS] Zero flag (Z) was set during test"
else
    echo "  [FAIL] Zero flag (Z) was never set"
    PASS=false
fi

# Sign flag should be set at some point
if grep -q "Flags:.*S='1'" flag_test.log; then
    echo "  [PASS] Sign flag (S) was set during test"
else
    echo "  [FAIL] Sign flag (S) was never set"
    PASS=false
fi

# Carry flag should be set at some point
if grep -q "Flags:.*C='1'" flag_test.log; then
    echo "  [PASS] Carry flag (C) was set during test"
else
    echo "  [FAIL] Carry flag (C) was never set"
    PASS=false
fi

# Parity should toggle (we should see both P='0' and P='1')
if grep -q "Flags:.*P='1'" flag_test.log && grep -q "Flags:.*P='0'" flag_test.log; then
    echo "  [PASS] Parity flag (P) toggled during test"
else
    echo "  [FAIL] Parity flag (P) did not toggle properly"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "==========================================="
    echo "ALL FLAG TESTS PASSED!"
    echo "==========================================="
    exit 0
else
    echo "==========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "==========================================="
    exit 1
fi

echo ""
echo "Full output saved to: flag_test.log"
echo "==========================================="
