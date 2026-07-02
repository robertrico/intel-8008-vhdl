#!/bin/bash

# ============================================================================
# ADDRESS-STACK DEPTH CHARACTERIZATION SCRIPT
# ============================================================================
# KNOWN FIDELITY DEVIATION (documented, pending user decision on a
# PC-in-stack re-architecture - see
# docs/superpowers/specs/2026-07-02-silicon-gaps-design.md):
#
#   Real 8008: PC lives inside the 8 address-stack registers -> 7 usable
#   return slots; the 8th nested CALL wraps onto the oldest context and
#   the final RET lands on the WRAP pad (CP2).
#
#   b8008 today: separate program_counter block + 8 return-only slots ->
#   all 8 nested CALLs return cleanly to MAIN (CP3).
#
# This script asserts b8008's CURRENT behavior so the regression stays
# green while the deviation is visible. If PC-in-stack ever lands, flip
# the CP2/CP3 expectations below.
#
# Program: stackwrap_test_as.asm
#
# Checkpoint Results (current b8008 architecture):
#   CP1: descent complete (inside L8), B=0x08
#   CP2: must NOT fire (spec-8008 wrap pad - fires on a real 8008)
#   CP3: fires - all 8 returns unwound back to MAIN
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "stackwrap_test_as" "30ms"

list_checkpoints

echo ""
echo "=== Stack Depth Characterization (split-PC design) ==="

# CP1: full 8-level descent happened
assert_checkpoint 1 \
    "B=0x08"

# CP2 (real-8008 wrap pad) must NOT fire on the current architecture
assert_checkpoint_absent 2

# CP3: b8008's separate PC lets all 8 returns unwind to MAIN
assert_checkpoint 3

assert_final_state \
    "A=0xFF" \
    "B=0x08"

# Print summary and exit
print_summary
exit $?
