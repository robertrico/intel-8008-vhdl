#!/bin/bash

# ============================================================================
# READY SINGLE-STEP TEST (VPLAN RDY-03, RDY-04, XP-15)
# ============================================================================
# READY_MODE=step holds READY low and pulses it once per machine cycle
# (the documented 8008 single-stepping technique, UM/DS72 §V.B). The TB
# asserts, per pulse:
#   - the CPU parks in WAIT and stays parked while READY is low
#   - exactly one T1/T1I entry per pulse (one machine cycle per pulse)
#
# This script runs two programs stepped end-to-end and diffs their
# checkpoints against free runs (single-stepping must be architecturally
# invisible - XP-15):
#   1. alu_test    - PCI/PCR coverage
#   2. io_test     - PCC coverage; additionally requires that an OUT
#                    instruction's PCC cycle was itself parked in WAIT
#                    (RDY-04: OUT requires READY and stalls losslessly)
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_DIR" || exit 1

FAIL=0

run_pair() {
    local PROG="$1"
    local FREE_TIME="$2"
    local STEP_TIME="$3"
    local FREE_LOG="$SCRIPT_DIR/ready_step_${PROG}_free.log"
    local STEP_LOG="$SCRIPT_DIR/ready_step_${PROG}_step.log"

    echo ""
    echo "--- $PROG: free run ---"
    make test-b8008-top PROG="$PROG" SIM_TIME="$FREE_TIME" > "$FREE_LOG" 2>&1 || {
        echo "[FAIL] $PROG free run exited nonzero"; FAIL=1; }

    echo "--- $PROG: single-stepped run (READY_MODE=step) ---"
    make test-b8008-top PROG="$PROG" SIM_TIME="$STEP_TIME" READY_MODE=step > "$STEP_LOG" 2>&1 || {
        echo "[FAIL] $PROG step run exited nonzero"; FAIL=1; }

    if ! grep -aq "READY step: single-step mode engaged" "$STEP_LOG"; then
        echo "[FAIL] $PROG: step mode did not activate"
        FAIL=1
    fi

    # TB per-pulse assertions (park integrity, one-cycle-per-pulse)
    if grep -aq "ERROR:" "$STEP_LOG"; then
        echo "[FAIL] $PROG: TB step assertions fired:"
        grep -a "ERROR:" "$STEP_LOG" | head -5
        FAIL=1
    else
        echo "[PASS] $PROG: park integrity + one machine cycle per pulse"
    fi

    # Completion summary must exist (program reached HLT while stepping)
    local SUMMARY
    SUMMARY=$(grep -a "READY step: [0-9]* pulses" "$STEP_LOG" | head -1)
    if [ -z "$SUMMARY" ]; then
        echo "[FAIL] $PROG: stepped run never completed (no pulse summary)"
        FAIL=1
    else
        # A CPU that ignores READY free-runs to HLT with ~0 pulses and
        # identical checkpoints - the pulse floor catches that
        local PULSES
        PULSES=$(echo "$SUMMARY" | sed -E 's/.*READY step: ([0-9]+) pulses.*/\1/')
        if [ "$PULSES" -lt 50 ]; then
            echo "[FAIL] $PROG: only $PULSES pulses - CPU not actually being stepped"
            FAIL=1
        else
            echo "[PASS] $PROG: ${SUMMARY##*note): }"
        fi
    fi

    # Checkpoints byte-identical to the free run
    grep -a "CHECKPOINT:" "$FREE_LOG" | sed -E 's/.*(CHECKPOINT:)/\1/' > "$SCRIPT_DIR/.rs_free_cp"
    grep -a "CHECKPOINT:" "$STEP_LOG" | sed -E 's/.*(CHECKPOINT:)/\1/' > "$SCRIPT_DIR/.rs_step_cp"
    local CP_COUNT
    CP_COUNT=$(wc -l < "$SCRIPT_DIR/.rs_free_cp" | tr -d ' ')
    if [ "$CP_COUNT" -eq 0 ]; then
        echo "[FAIL] $PROG: free run produced no checkpoints"
        FAIL=1
    elif diff -q "$SCRIPT_DIR/.rs_free_cp" "$SCRIPT_DIR/.rs_step_cp" > /dev/null; then
        echo "[PASS] $PROG: all $CP_COUNT checkpoints identical free vs stepped"
    else
        echo "[FAIL] $PROG: checkpoint divergence free vs stepped:"
        diff "$SCRIPT_DIR/.rs_free_cp" "$SCRIPT_DIR/.rs_step_cp" | head -10
        FAIL=1
    fi
    rm -f "$SCRIPT_DIR/.rs_free_cp" "$SCRIPT_DIR/.rs_step_cp"
}

echo "==========================================="
echo "READY single-step test (RDY-03/RDY-04/XP-15)"
echo "==========================================="

run_pair "alu_test_as" "10ms" "15ms"
run_pair "io_test_as"  "10ms" "15ms"

# --- RDY-04: an OUT instruction's PCC cycle parked in WAIT --------------
# In step mode every cycle parks; confirm from the log that at least one
# PCC cycle belonging to an OUT opcode entered WAIT after its T2.
# Mines RTL report lines (MCycle/STATE/IR), which synthesis strips -
# RTL core only, like check_cycle_count_test.sh. The step/park/checkpoint
# assertions above still run on the netlist core.
if [ "$B8008_CORE" = "netlist" ]; then
    echo ""
    echo "=== RDY-04 log scan skipped (netlist core strips reports) ==="
    if [ $FAIL -eq 0 ]; then echo "ALL TESTS PASSED!"; exit 0; else echo "SOME TESTS FAILED"; exit 1; fi
fi
echo ""
python3 - "$SCRIPT_DIR/ready_step_io_test_as_step.log" <<'PYEOF'
import re, sys

out_pcc_waits = 0
inp_pcc_waits = 0
last_ir = None
pending_pcc = False

re_ir   = re.compile(r'IR: Loading from bus = 0x([0-9A-Fa-f]{2})')
re_pcc  = re.compile(r'MCycle: T2 cycle_type=PCC')
re_mcyc = re.compile(r'MCycle: T2 cycle_type=')
re_wait = re.compile(r'STATE: s_t2 -> s_wait')

for line in open(sys.argv[1], errors='replace'):
    m = re_ir.search(line)
    if m:
        last_ir = int(m.group(1), 16)
        continue
    if re_pcc.search(line):
        pending_pcc = True
        continue
    if re_mcyc.search(line):
        pending_pcc = False
        continue
    if pending_pcc and re_wait.search(line):
        # PCC cycle parked in WAIT; classify by the opcode that owns it
        if last_ir is not None and (last_ir & 0xC1) == 0x41:
            port = (last_ir >> 1) & 0x1F
            if port >= 8:
                out_pcc_waits += 1
            else:
                inp_pcc_waits += 1
        pending_pcc = False

print(f"OUT PCC cycles parked in WAIT: {out_pcc_waits}")
print(f"INP PCC cycles parked in WAIT: {inp_pcc_waits}")
if out_pcc_waits < 1:
    print("[FAIL] no OUT PCC cycle was ever parked in WAIT (RDY-04 unexercised)")
    sys.exit(1)
print("[PASS] OUT stalls on READY and completes losslessly (RDY-04)")
PYEOF
if [ $? -ne 0 ]; then
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
