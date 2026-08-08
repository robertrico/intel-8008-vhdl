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

# Find all check_*.sh files (test scripts only, not libraries)
for script in "$SCRIPT_DIR"/check_*.sh; do
    # Skip non-executable files
    if [ ! -x "$script" ]; then
        continue
    fi

    TEST_NAME=$(basename "$script" .sh)

    # Tests that mine RTL-internal report statements cannot run against the
    # write_vhdl netlist core (synthesis strips reports). Skip loudly.
    if [ "$B8008_CORE" = "netlist" ] && [ "$TEST_NAME" = "check_cycle_count_test" ]; then
        echo "-------------------------------------------"
        echo "SKIPPED (RTL-only, mines report output): $TEST_NAME"
        echo "-------------------------------------------"
        continue
    fi

    TOTAL=$((TOTAL + 1))

    echo "-------------------------------------------"
    echo "Running: $TEST_NAME"
    echo "-------------------------------------------"

    # Run the test and capture output
    OUTPUT=$("$script" 2>&1)
    STATUS=$?

    # Exit code is the primary signal; the banner is a cross-check.
    # A script that dies after printing success-shaped text, or that
    # exits 0 without the banner, is reported as a failure either way.
    if [ $STATUS -eq 0 ] && echo "$OUTPUT" | grep -q "ALL.*PASSED\|TESTS PASSED\|SUCCESS"; then
        echo "[PASS] $TEST_NAME"
        PASSED=$((PASSED + 1))
    else
        echo "[FAIL] $TEST_NAME (exit=$STATUS)"
        FAILED=$((FAILED + 1))
        FAILED_TESTS="$FAILED_TESTS $TEST_NAME"
        # Show relevant output for failed tests (case-insensitive:
        # GHDL prints lowercase 'error:'), fall back to the tail so a
        # failure is never silent.
        echo ""
        echo "Test output:"
        RELEVANT=$(echo "$OUTPUT" | grep -iE "fail|expected|error" | head -10)
        if [ -n "$RELEVANT" ]; then
            echo "$RELEVANT"
        else
            echo "$OUTPUT" | tail -10
        fi
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
