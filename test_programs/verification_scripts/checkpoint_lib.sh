#!/bin/bash

# ============================================================================
# CHECKPOINT VERIFICATION LIBRARY
# ============================================================================
# This library provides functions for asserting CPU state at checkpoints.
#
# Usage in test scripts:
#   source ./checkpoint_lib.sh
#   run_test "test_name" "30ms"
#   assert_checkpoint 1 "B=0x08"
#   assert_checkpoint 2 "A=0x02" "B=0x08"
#   assert_checkpoint 3 "C=0x0A" "P=1"
#   print_summary
#
# Checkpoint format in log:
#   CHECKPOINT: ID=N PC=0xXXXX A=0xXX B=0xXX C=0xXX D=0xXX E=0xXX H=0xXX L=0xXX C=X Z=X S=X P=X
# ============================================================================

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Global variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE=""
TEST_NAME=""
PASS_COUNT=0
FAIL_COUNT=0
TOTAL_ASSERTIONS=0

# ============================================================================
# run_test - Run a test program and capture output
# ============================================================================
# Arguments:
#   $1 - Test program name (without .mem extension)
#   $2 - Simulation time (optional, default: 30ms)
# ============================================================================
run_test() {
    TEST_NAME="$1"
    local SIM_TIME="${2:-30ms}"
    LOG_FILE="${SCRIPT_DIR}/${TEST_NAME}.log"

    echo "==========================================="
    echo "Running test: $TEST_NAME"
    echo "Simulation time: $SIM_TIME"
    echo "==========================================="
    echo ""

    # Run the simulation
    cd "$PROJECT_DIR"
    make test-b8008-top PROG="$TEST_NAME" SIM_TIME="$SIM_TIME" 2>&1 > "$LOG_FILE"

    # Check if simulation ran
    if [ ! -f "$LOG_FILE" ]; then
        echo -e "${RED}ERROR: Log file not created${NC}"
        return 1
    fi

    # Count checkpoints found
    local cp_count=$(grep -c "CHECKPOINT:" "$LOG_FILE" 2>/dev/null || echo "0")
    echo "Found $cp_count checkpoint(s) in simulation output"
    echo ""

    # Reset counters
    PASS_COUNT=0
    FAIL_COUNT=0
    TOTAL_ASSERTIONS=0

    return 0
}

# ============================================================================
# get_checkpoint - Extract checkpoint data for a given ID
# ============================================================================
# Arguments:
#   $1 - Checkpoint ID
# Returns:
#   Checkpoint line from log file
# ============================================================================
get_checkpoint() {
    local id="$1"
    grep "CHECKPOINT: ID=$id " "$LOG_FILE" | head -1
}

# ============================================================================
# assert_checkpoint - Assert values at a specific checkpoint
# ============================================================================
# Arguments:
#   $1 - Checkpoint ID
#   $2+ - Assertions in format "REG=VALUE" (e.g., "A=0x00", "B=0x08", "C=1")
# ============================================================================
assert_checkpoint() {
    local id="$1"
    shift
    local assertions=("$@")

    echo "--- Checkpoint $id ---"

    # Get the checkpoint line
    local cp_line=$(get_checkpoint "$id")

    if [ -z "$cp_line" ]; then
        echo -e "  ${RED}[FAIL] Checkpoint $id not found in log${NC}"
        ((FAIL_COUNT++))
        ((TOTAL_ASSERTIONS++))
        return 1
    fi

    # Process each assertion
    local all_passed=true
    for assertion in "${assertions[@]}"; do
        ((TOTAL_ASSERTIONS++))

        # Parse the assertion (e.g., "A=0x00" -> reg="A", expected="0x00")
        local reg="${assertion%%=*}"
        local expected="${assertion#*=}"

        # Handle flag assertions (C, Z, S, P are single char after the registers)
        # Checkpoint format: ... L=0xXX C=X Z=X S=X P=X
        local actual=""

        case "$reg" in
            A|B|C|D|E|H|L)
                # Register assertion - extract hex value
                actual=$(echo "$cp_line" | sed -E "s/.*${reg}=(0x[0-9A-Fa-f]+).*/\1/")
                ;;
            PC)
                # Program counter
                actual=$(echo "$cp_line" | sed -E "s/.*PC=(0x[0-9A-Fa-f]+).*/\1/")
                ;;
            CF|CARRY)
                # Carry flag - at end of line as " C=X"
                actual=$(echo "$cp_line" | sed -E 's/.* C=([01]).*/\1/')
                reg="C(flag)"
                ;;
            ZF|ZERO)
                # Zero flag
                actual=$(echo "$cp_line" | sed -E 's/.* Z=([01]).*/\1/')
                reg="Z(flag)"
                ;;
            SF|SIGN)
                # Sign flag
                actual=$(echo "$cp_line" | sed -E 's/.* S=([01]).*/\1/')
                reg="S(flag)"
                ;;
            PF|PARITY)
                # Parity flag
                actual=$(echo "$cp_line" | sed -E 's/.* P=([01]).*/\1/')
                reg="P(flag)"
                ;;
            *)
                echo -e "  ${YELLOW}[WARN] Unknown register/flag: $reg${NC}"
                continue
                ;;
        esac

        # Normalize hex values for comparison (uppercase)
        expected=$(echo "$expected" | tr '[:lower:]' '[:upper:]')
        actual=$(echo "$actual" | tr '[:lower:]' '[:upper:]')

        # Compare
        if [ "$actual" = "$expected" ]; then
            echo -e "  ${GREEN}[PASS]${NC} $reg = $actual"
            ((PASS_COUNT++))
        else
            echo -e "  ${RED}[FAIL]${NC} $reg = $actual (expected $expected)"
            ((FAIL_COUNT++))
            all_passed=false
        fi
    done

    if $all_passed; then
        return 0
    else
        return 1
    fi
}

# ============================================================================
# assert_final_state - Assert final register state (last snapshot in log)
# ============================================================================
# Arguments:
#   $1+ - Assertions in format "REG=VALUE"
# ============================================================================
assert_final_state() {
    local assertions=("$@")

    echo "--- Final State ---"

    for assertion in "${assertions[@]}"; do
        ((TOTAL_ASSERTIONS++))

        local reg="${assertion%%=*}"
        local expected="${assertion#*=}"
        local actual=""

        case "$reg" in
            A)
                actual=$(tail -100 "$LOG_FILE" | grep "Reg\.A = " | tail -1 | sed -E 's/.*Reg\.A = (0x[0-9A-Fa-f]+).*/\1/')
                ;;
            B)
                actual=$(tail -100 "$LOG_FILE" | grep "Reg\.B = " | tail -1 | sed -E 's/.*Reg\.B = (0x[0-9A-Fa-f]+).*/\1/')
                ;;
            C)
                actual=$(tail -100 "$LOG_FILE" | grep "Reg\.C = " | tail -1 | sed -E 's/.*Reg\.C = (0x[0-9A-Fa-f]+).*/\1/')
                ;;
            D)
                actual=$(tail -100 "$LOG_FILE" | grep "Reg\.D = " | tail -1 | sed -E 's/.*Reg\.D = (0x[0-9A-Fa-f]+).*/\1/')
                ;;
            E)
                actual=$(tail -100 "$LOG_FILE" | grep "Reg\.E = " | tail -1 | sed -E 's/.*Reg\.E = (0x[0-9A-Fa-f]+).*/\1/')
                ;;
            H)
                actual=$(tail -100 "$LOG_FILE" | grep "Reg\.H = " | tail -1 | sed -E 's/.*Reg\.H = (0x[0-9A-Fa-f]+).*/\1/')
                ;;
            L)
                actual=$(tail -100 "$LOG_FILE" | grep "Reg\.L = " | tail -1 | sed -E 's/.*Reg\.L = (0x[0-9A-Fa-f]+).*/\1/')
                ;;
            *)
                echo -e "  ${YELLOW}[WARN] Unknown register: $reg${NC}"
                continue
                ;;
        esac

        # Normalize
        expected=$(echo "$expected" | tr '[:lower:]' '[:upper:]')
        actual=$(echo "$actual" | tr '[:lower:]' '[:upper:]')

        if [ "$actual" = "$expected" ]; then
            echo -e "  ${GREEN}[PASS]${NC} $reg = $actual"
            ((PASS_COUNT++))
        else
            echo -e "  ${RED}[FAIL]${NC} $reg = $actual (expected $expected)"
            ((FAIL_COUNT++))
        fi
    done
}

# ============================================================================
# list_checkpoints - List all checkpoints found in the log
# ============================================================================
list_checkpoints() {
    echo "--- Checkpoints Found ---"
    grep "CHECKPOINT:" "$LOG_FILE" | while read -r line; do
        echo "  $line"
    done
    echo ""
}

# ============================================================================
# print_summary - Print test summary and exit with appropriate code
# ============================================================================
print_summary() {
    echo ""
    echo "==========================================="
    echo "TEST SUMMARY: $TEST_NAME"
    echo "==========================================="
    echo "Total assertions: $TOTAL_ASSERTIONS"
    echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
    echo -e "Failed: ${RED}$FAIL_COUNT${NC}"
    echo ""

    if [ "$FAIL_COUNT" -eq 0 ]; then
        echo -e "${GREEN}ALL TESTS PASSED!${NC}"
        echo "==========================================="
        return 0
    else
        echo -e "${RED}SOME TESTS FAILED${NC}"
        echo "==========================================="
        return 1
    fi
}

# ============================================================================
# get_exit_code - Return exit code based on test results
# ============================================================================
get_exit_code() {
    if [ "$FAIL_COUNT" -eq 0 ]; then
        return 0
    else
        return 1
    fi
}
