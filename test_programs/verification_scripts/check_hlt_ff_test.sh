#!/bin/bash

# HLT 0xFF Test - Verify CPU halts with opcode 0xFF

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "hlt_ff_as" "5ms"
list_checkpoints

echo "=== HLT 0xFF Test ==="
assert_checkpoint 1

print_summary
exit $?
