#!/bin/bash

# ============================================================================
# XP-02: HLT WITH INTERRUPT ALREADY PENDING (VPLAN XP-02)
# ============================================================================
# Runs hlt_int_pending_tb (make test-hlt-int-pending) on xp02_test_as.asm:
# INT is pulsed and RELEASED during HLT's own cycle (an INT pending at the
# previous instruction boundary would rightfully preempt HLT); the stored
# interrupt must wake the CPU from STOPPED without the line re-asserting.
#
#   CP1  main reached                    -> A=0x01
#   CP2  wake handler ran                -> A=0x02 B=0xAA
#   CP3  must NEVER fire (HLT fell through)
#
# TB-side assertions (pending latched, bounded wake, HLT in IR, exactly
# 2 T1I, final STOPPED persistence) report as "ERROR:" lines.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

LOG_FILE="$SCRIPT_DIR/xp02_test_as.log"

echo "==========================================="
echo "XP-02: HLT with pending interrupt"
echo "==========================================="

make test-hlt-int-pending > "$LOG_FILE" 2>&1
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
    echo "[PASS] TB assertions clean (latch, bounded wake, 2x T1I, STOPPED persistence)"
fi

if grep -aq "CHECKPOINT: ID=2 .*A=0x02 B=0xAA" "$LOG_FILE"; then
    echo "[PASS] wake handler ran with state intact (CP2: A=0x02 B=0xAA)"
else
    echo "[FAIL] CP2 missing or wrong - pending interrupt did not resume execution"
    FAIL=1
fi

if grep -aq "CHECKPOINT: ID=3" "$LOG_FILE"; then
    echo "[FAIL] CP3 fired - CPU sailed through HLT"
    FAIL=1
else
    echo "[PASS] HLT halted (sentinel CP3 absent)"
fi

if grep -aq "XP-02 TEST COMPLETE" "$LOG_FILE"; then
    echo "[PASS] test sequence completed"
else
    echo "[FAIL] TB did not run to completion"
    FAIL=1
fi

echo ""
if [ $FAIL -eq 0 ]; then
    echo "ALL TESTS PASSED!"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
