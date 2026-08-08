#!/bin/bash

# ============================================================================
# INTERRUPT JAM GENERALITY TEST (VPLAN INT-04/05, XP-03, XP-14)
# ============================================================================
# Runs interrupt_jam_tb (make test-interrupt-jam) on jam_test_as.asm:
#   S1  NOP jam mid-loop            -> CP1: C=0x10 D=0x00
#   S2  HLT jam mid-loop + RST7 wake -> CP2: C=0x10 D=0x01
#   S3  3-byte JMP jam out of a spin -> CP3: D=0x01 (single T1I asserted in TB)
#   S4  INT during WAIT              -> CP4: C=0x10 D=0x02
#   final                            -> CP5
# TB-side assertions (STOPPED persistence, single T1I, no T1I in WAIT)
# report as "ERROR:" lines - any of those fails the test.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

LOG_FILE="$SCRIPT_DIR/jam_test_as.log"

echo "==========================================="
echo "Interrupt jam generality test"
echo "==========================================="

make test-interrupt-jam > "$LOG_FILE" 2>&1
STATUS=$?

FAIL=0

if [ $STATUS -ne 0 ]; then
    echo "[FAIL] simulation exited nonzero ($STATUS)"
    FAIL=1
fi

if grep -aq "ERROR:" "$LOG_FILE"; then
    echo "[FAIL] TB assertions fired:"
    grep -a "ERROR:" "$LOG_FILE" | head -5
    FAIL=1
else
    echo "[PASS] no TB assertion errors"
fi

check_cp() {
    local id="$1"; shift
    local line
    line=$(grep -a "CHECKPOINT: ID=$id " "$LOG_FILE" | head -1)
    if [ -z "$line" ]; then
        echo "[FAIL] checkpoint $id not found"
        FAIL=1
        return
    fi
    local ok=1
    for want in "$@"; do
        if ! echo "$line" | grep -q "$want"; then
            echo "[FAIL] checkpoint $id: expected $want in: $line"
            ok=0
            FAIL=1
        fi
    done
    [ $ok -eq 1 ] && echo "[PASS] checkpoint $id ($*)"
}

check_cp 1 "C=0x10" "D=0x00"
check_cp 2 "C=0x10" "D=0x01"
check_cp 3 "D=0x01"
check_cp 4 "C=0x10" "D=0x02"
check_cp 5

echo ""
if [ $FAIL -eq 0 ]; then
    echo "ALL TESTS PASSED!"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
