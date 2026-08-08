#!/bin/bash

# ============================================================================
# READY/WAIT SYSTEM-LEVEL TEST (VPLAN Tier1-1: XP-04, XP-05, RDY-02/03)
# ============================================================================
# Runs memory_alu_test twice on the full CPU: once free, once with
# READY_MODE=stress (hundreds of READY drops of varied length plus one
# long park - WAIT states land in every machine-cycle type: PCI,
# PCR-immediate, PCR-H:L, PCW, PCC).
#
# Pass requires:
#   1. WAIT status (000) actually observed while parked (TB asserts)
#   2. Every checkpoint line in the stressed run byte-identical to the
#      free run - wait states must be architecturally invisible
#
# History: a real WAIT bug was found by period software, not by this
# suite. This closes that hole.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

PROG="memory_alu_test_as"
SIM_TIME="30ms"
FREE_LOG="$SCRIPT_DIR/ready_wait_free.log"
STRESS_LOG="$SCRIPT_DIR/ready_wait_stress.log"

echo "==========================================="
echo "READY/WAIT stress test: $PROG"
echo "==========================================="

echo ""
echo "--- Free run ---"
make test-b8008-top PROG="$PROG" SIM_TIME="$SIM_TIME" > "$FREE_LOG" 2>&1
FREE_STATUS=$?

echo "--- Stressed run (READY_MODE=stress) ---"
make test-b8008-top PROG="$PROG" SIM_TIME="$SIM_TIME" READY_MODE=stress > "$STRESS_LOG" 2>&1
STRESS_STATUS=$?

FAIL=0

if [ $FREE_STATUS -ne 0 ] || [ $STRESS_STATUS -ne 0 ]; then
    echo "[FAIL] simulation exited nonzero (free=$FREE_STATUS stress=$STRESS_STATUS)"
    FAIL=1
fi

# TB-side WAIT assertions fire as report ... severity error
if grep -aq "never saw WAIT" "$STRESS_LOG"; then
    echo "[FAIL] stressed run never parked in WAIT"
    FAIL=1
else
    echo "[PASS] WAIT status observed while parked"
fi

# The stressed run must actually have been stressed
if ! grep -aq "READY stress: long park begins" "$STRESS_LOG"; then
    echo "[FAIL] stress mode did not activate (generic not wired?)"
    FAIL=1
else
    echo "[PASS] stress mode active"
fi

# Checkpoint lines must be byte-identical (strip the report prefix,
# which carries sim timestamps that legitimately differ)
extract_checkpoints() {
    grep -a "CHECKPOINT:" "$1" | sed -E 's/.*(CHECKPOINT:)/\1/'
}
extract_checkpoints "$FREE_LOG"   > "$SCRIPT_DIR/.ready_wait_free_cp"
extract_checkpoints "$STRESS_LOG" > "$SCRIPT_DIR/.ready_wait_stress_cp"

CP_COUNT=$(wc -l < "$SCRIPT_DIR/.ready_wait_free_cp" | tr -d ' ')
if [ "$CP_COUNT" -eq 0 ]; then
    echo "[FAIL] free run produced no checkpoints"
    FAIL=1
fi

if diff -q "$SCRIPT_DIR/.ready_wait_free_cp" "$SCRIPT_DIR/.ready_wait_stress_cp" > /dev/null; then
    echo "[PASS] all $CP_COUNT checkpoints identical between free and stressed runs"
else
    echo "[FAIL] checkpoint divergence between free and stressed runs:"
    diff "$SCRIPT_DIR/.ready_wait_free_cp" "$SCRIPT_DIR/.ready_wait_stress_cp" | head -10
    FAIL=1
fi

rm -f "$SCRIPT_DIR/.ready_wait_free_cp" "$SCRIPT_DIR/.ready_wait_stress_cp"

echo ""
if [ $FAIL -eq 0 ]; then
    echo "ALL TESTS PASSED!"
    exit 0
else
    echo "SOME TESTS FAILED"
    exit 1
fi
