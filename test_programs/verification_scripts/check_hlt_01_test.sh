#!/bin/bash

# HLT 0x01 Test - Verify CPU halts with opcode 0x01

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "hlt_01_as" "5ms"
list_checkpoints

echo "=== HLT 0x01 Test ==="
assert_checkpoint 1

print_summary
exit $?
