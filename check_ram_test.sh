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
make test-b8008-top 2>&1 > ram_test.log

echo ""
echo "=== 1. Program Start - Initial C register (array size) ==="
echo "Should be 0x10 (16 decimal)"
grep "Reg\.B = 0x00" ram_test.log | head -5 | tail -3

echo ""
echo "=== 2. FILL_RAM Phase - Check H:L pointer progression ==="
echo "H should be 0x10 (RAM base), L should increment 0x00->0x0F"
grep "Reg\.H = 0x10" ram_test.log | grep -E "Reg\.L = 0x0[0-F]" | head -20 | tail -16

echo ""
echo "=== 3. CALC_SUM Phase - Accumulator (E register) building sum ==="
echo "E should progressively accumulate: 0x00 + 0x01 + 0x02 ... = 0x78"
grep "PC = 0x011" ram_test.log -A3 | grep "Reg\.E" | sort -u | tail -10

echo ""
echo "=== 4. Check D register gets final sum ==="
echo "After CALC_SUM returns, D should have 0x78 (120 decimal = sum of 0..15)"
grep "Reg\.D = 0x" ram_test.log | grep -v "Reg\.D = 0x00" | head -5

echo ""
echo "=== 5. INVERT_RAM Phase - XOR operations ==="
echo "Should see XRI 0xFF instructions"
grep "IR = 0x" ram_test.log | grep -E "(0x[A-F]C|XRI)" | head -10

echo ""
echo "=== 6. Final Register State (at program end) ==="
echo "Expected:"
echo "  A = 0xF0 (last inverted value: 0x0F XOR 0xFF)"
echo "  B = 0xFF (first inverted value: 0x00 XOR 0xFF)"
echo "  C = 0x10 (array size = 16)"
echo "  D = 0x78 (sum of 0..15 = 120)"
echo "  E = 0xF0 (last inverted value)"
echo "  H = 0x10 (RAM base high)"
echo "  L = 0x0F (last array index)"
echo ""
echo "Actual (last reported state):"
tail -100 ram_test.log | grep -E "Reg\.(A|B|C|D|E|H|L)" | tail -8

echo ""
echo "=== 7. HLT Instruction Detection ==="
HLT_COUNT=$(grep "IR = 0x00" ram_test.log | wc -l)
echo "HLT instruction (IR=0x00) seen $HLT_COUNT times"
grep "IR = 0x00" ram_test.log | tail -3

echo ""
echo "==========================================="
echo "Full output saved to: ram_test.log"
echo "==========================================="
