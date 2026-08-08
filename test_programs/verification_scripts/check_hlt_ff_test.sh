#!/bin/bash

# HLT 0xFF Test - Verify CPU halts with opcode 0xFF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "hlt_ff_as" "5ms"
list_checkpoints

echo "=== HLT 0xFF Test ==="
assert_checkpoint 1

# The CPU must actually stop: the sentinel checkpoint placed after the
# HLT must never fire (a CPU that sails through HLT executes it).
assert_checkpoint_absent 2

# RTL-only extra: the state machine must report entering s_stopped after
# the checkpoint (synthesis strips report statements from the netlist).
if [ "$B8008_CORE" != "netlist" ]; then
    ((TOTAL_ASSERTIONS++))
    if grep -aq "s_stopped" "$LOG_FILE"; then
        echo "  [PASS] state machine entered s_stopped"
        ((PASS_COUNT++))
    else
        echo "  [FAIL] no s_stopped transition in log"
        ((FAIL_COUNT++))
    fi
fi

print_summary
exit $?
