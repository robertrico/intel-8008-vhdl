#!/bin/bash

# ============================================
# MOV r,M / MOV M,r TEST VERIFICATION SCRIPT
# ============================================
# Verifies all 14 MOV memory instruction tests:
#   7 MOV r,M tests (read from memory)
#   7 MOV M,r tests (write to memory)
#
# Expected final state:
#   A = 0x00 (success indicator)
#   B = 0x0E (14 tests passed)
#   PC = 0x01C2 (DONE/HLT address)
#   IR = 0x00 (HLT opcode)

echo "==========================================="
echo "B8008 MOV r,M / MOV M,r Test Verification"
echo "==========================================="
echo ""

# Run the test
echo "Running test (this takes a few seconds)..."
make test-b8008-top PROG=mov_mem_test_as SIM_TIME=30ms 2>&1 > mov_mem_test.log

echo ""
echo "=== 1. MOV r,M Tests (Read from memory) ==="
echo "Tests 1-7: MOV A,M, MOV B,M, MOV C,M, MOV D,M, MOV E,M, MOV H,M, MOV L,M"

# Check for intermediate values showing tests passed
echo ""
echo "=== 2. MOV M,r Tests (Write to memory) ==="
echo "Tests 8-14: MOV M,A, MOV M,B, MOV M,C, MOV M,D, MOV M,E, MOV M,H, MOV M,L"

echo ""
echo "=== 3. HLT Detection ==="
echo "Program should halt at PC = 0x01C2 (DONE label)"
grep "PC = 0x01C2.*IR = 0x00" mov_mem_test.log | head -1

echo ""
echo "=== 4. Final Register State ==="
echo "Expected:"
echo "  A = 0x00 (success indicator - all tests passed)"
echo "  B = 0x0E (14 tests completed)"
echo "  C = 0xBB (test value from MOV M,C test)"
echo "  D = 0xCC (test value from MOV M,D test)"
echo "  E = 0xDD (test value from MOV M,E test)"
echo "  H = 0x10 (final H:L pointer high byte)"
echo "  L = 0x0E (final H:L pointer low byte)"
echo ""
echo "Actual (last reported state):"
tail -100 mov_mem_test.log | grep "Reg\.A = " | tail -1
tail -100 mov_mem_test.log | grep "Reg\.D = " | tail -1

echo ""
echo "=== 5. Test Summary ==="

# Check final register values
PASS=true

# Get last register values
FINAL_A=$(tail -100 mov_mem_test.log | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_B=$(tail -100 mov_mem_test.log | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_C=$(tail -100 mov_mem_test.log | grep "Reg\.C = " | tail -1 | sed -E 's/.*Reg\.C = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_D=$(tail -100 mov_mem_test.log | grep "Reg\.D = " | tail -1 | sed -E 's/.*Reg\.D = (0x[0-9A-Fa-f]+).*/\1/')
FINAL_E=$(tail -100 mov_mem_test.log | grep "Reg\.E = " | tail -1 | sed -E 's/.*Reg\.E = (0x[0-9A-Fa-f]+).*/\1/')

echo "Checking final values..."

if [ "$FINAL_A" = "0x00" ]; then
    echo "  [PASS] A = 0x00 (success indicator)"
else
    echo "  [FAIL] A = $FINAL_A (expected 0x00)"
    PASS=false
fi

if [ "$FINAL_B" = "0x0E" ]; then
    echo "  [PASS] B = 0x0E (14 tests completed)"
else
    echo "  [FAIL] B = $FINAL_B (expected 0x0E)"
    PASS=false
fi

if [ "$FINAL_C" = "0xBB" ]; then
    echo "  [PASS] C = 0xBB (MOV M,C test value)"
else
    echo "  [FAIL] C = $FINAL_C (expected 0xBB)"
    PASS=false
fi

if [ "$FINAL_D" = "0xCC" ]; then
    echo "  [PASS] D = 0xCC (MOV M,D test value)"
else
    echo "  [FAIL] D = $FINAL_D (expected 0xCC)"
    PASS=false
fi

if [ "$FINAL_E" = "0xDD" ]; then
    echo "  [PASS] E = 0xDD (MOV M,E test value)"
else
    echo "  [FAIL] E = $FINAL_E (expected 0xDD)"
    PASS=false
fi

# Check HLT at correct address
if grep -q "PC = 0x01C2.*IR = 0x00" mov_mem_test.log; then
    echo "  [PASS] HLT detected at PC = 0x01C2"
else
    echo "  [FAIL] HLT not detected at expected address"
    PASS=false
fi

echo ""
if [ "$PASS" = true ]; then
    echo "==========================================="
    echo "ALL MOV MEMORY TESTS PASSED!"
    echo "  - 7 MOV r,M tests (read from memory)"
    echo "  - 7 MOV M,r tests (write to memory)"
    echo "==========================================="
    exit 0
else
    echo "==========================================="
    echo "SOME TESTS FAILED - Check output above"
    echo "==========================================="
    exit 1
fi

echo ""
echo "Full output saved to: mov_mem_test.log"
echo "==========================================="
