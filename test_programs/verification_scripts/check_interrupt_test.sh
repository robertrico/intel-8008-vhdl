#!/bin/bash
# Verification script for interrupt_test_as.asm
# Tests interrupt handling: bootstrap (RST 0) and runtime interrupt (RST 7)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "========================================="
echo "Interrupt Test Verification"
echo "========================================="

# Run the interrupt test
cd "$PROJECT_ROOT"
OUTPUT=$(make test-interrupt 2>&1)

# Check for compilation errors
if echo "$OUTPUT" | grep -q "error:"; then
    echo "FAIL: Compilation errors detected"
    echo "$OUTPUT" | grep "error:"
    exit 1
fi

# Track pass/fail
PASS_COUNT=0
FAIL_COUNT=0

# Function to check checkpoint values
check_checkpoint() {
    local cp_id=$1
    local reg=$2
    local expected=$3
    local desc=$4

    # Find the checkpoint line
    local cp_line=$(echo "$OUTPUT" | grep "CHECKPOINT: ID=$cp_id " | head -1)

    if [ -z "$cp_line" ]; then
        echo "FAIL: Checkpoint $cp_id not found - $desc"
        ((FAIL_COUNT++))
        return 1
    fi

    # Extract the register value
    local actual=$(echo "$cp_line" | grep -o "${reg}=0x[0-9A-Fa-f]*" | head -1 | cut -d= -f2)

    if [ "$actual" = "$expected" ]; then
        echo "PASS: CP$cp_id $reg=$expected - $desc"
        ((PASS_COUNT++))
        return 0
    else
        echo "FAIL: CP$cp_id $reg expected $expected, got $actual - $desc"
        ((FAIL_COUNT++))
        return 1
    fi
}

# Function to check flag values
check_flag() {
    local cp_id=$1
    local flag=$2
    local expected=$3
    local desc=$4

    local cp_line=$(echo "$OUTPUT" | grep "CHECKPOINT: ID=$cp_id " | head -1)

    if [ -z "$cp_line" ]; then
        echo "FAIL: Checkpoint $cp_id not found for flag check - $desc"
        ((FAIL_COUNT++))
        return 1
    fi

    # Extract flag value (single character '0' or '1')
    local actual=$(echo "$cp_line" | grep -o "${flag}=[01]" | head -1 | cut -d= -f2)

    if [ "$actual" = "$expected" ]; then
        echo "PASS: CP$cp_id $flag=$expected - $desc"
        ((PASS_COUNT++))
        return 0
    else
        echo "FAIL: CP$cp_id $flag expected $expected, got $actual - $desc"
        ((FAIL_COUNT++))
        return 1
    fi
}

echo ""
echo "Checking Checkpoints..."
echo "-----------------------"

# CP1: Initial state after bootstrap - B=0x01, D=0x00
check_checkpoint 1 "B" "0x01" "After bootstrap, B incremented"
check_checkpoint 1 "D" "0x00" "D initially zero"

# CP2: After loop - B=0x05, D=0x00
check_checkpoint 2 "B" "0x05" "After counting loop, B=5"
check_checkpoint 2 "D" "0x00" "D still zero before interrupt"

# CP3: Inside RST 7 handler - D=0xAA
check_checkpoint 3 "D" "0xAA" "Inside interrupt handler, D set to 0xAA"

# CP4: After interrupt return - D=0xAA
check_checkpoint 4 "D" "0xAA" "After RET, D still 0xAA"

# CP5: Success - final state
check_checkpoint 5 "A" "0x05" "Success checkpoint reached"
check_checkpoint 5 "D" "0xAA" "D preserved after verification"

echo ""
echo "========================================="
echo "Interrupt Test Summary"
echo "========================================="
echo "Passed: $PASS_COUNT"
echo "Failed: $FAIL_COUNT"
echo ""

if [ $FAIL_COUNT -eq 0 ]; then
    echo "INTERRUPT TEST: ALL ASSERTIONS PASSED"
    exit 0
else
    echo "INTERRUPT TEST: SOME ASSERTIONS FAILED"
    exit 1
fi
