#!/bin/bash

# ============================================
# B8008 REGRESSION TEST RUNNER
# ============================================
# Runs all verification scripts in this directory
# and reports overall pass/fail status

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR/../.." || exit 1

echo "==========================================="
echo "B8008 Regression Test Suite"
echo "==========================================="
echo ""
echo "Running all verification scripts..."
echo ""

TOTAL=0
PASSED=0
FAILED=0
FAILED_TESTS=""

# Find all .sh files except this script
for script in "$SCRIPT_DIR"/*.sh; do
    # Skip this script
    if [ "$(basename "$script")" = "run_all_tests.sh" ]; then
        continue
    fi

    # Skip non-executable files
    if [ ! -x "$script" ]; then
        continue
    fi

    TOTAL=$((TOTAL + 1))
    TEST_NAME=$(basename "$script" .sh)

    echo "-------------------------------------------"
    echo "Running: $TEST_NAME"
    echo "-------------------------------------------"

    # Run the test and capture output
    OUTPUT=$("$script" 2>&1)

    # Check if test passed (look for PASSED or SUCCESS in output)
    if echo "$OUTPUT" | grep -q "ALL.*PASSED\|TESTS PASSED\|SUCCESS"; then
        echo "[PASS] $TEST_NAME"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $TEST_NAME"
        FAILED=$((FAILED + 1))
        FAILED_TESTS="$FAILED_TESTS $TEST_NAME"
        # Show relevant output for failed tests
        echo ""
        echo "Test output:"
        echo "$OUTPUT" | grep -E "FAIL|\[FAIL\]|expected|Error" | head -10
    fi
    echo ""
done

echo "==========================================="
echo "REGRESSION TEST SUMMARY"
echo "==========================================="
echo ""
echo "Total tests: $TOTAL"
echo "Passed:      $PASSED"
echo "Failed:      $FAILED"
echo ""

if [ $FAILED -eq 0 ]; then
    echo "==========================================="
    echo "ALL TESTS PASSED!"
    echo "==========================================="
    exit 0
else
    echo "==========================================="
    echo "SOME TESTS FAILED:$FAILED_TESTS"
    echo "==========================================="
    exit 1
fi
