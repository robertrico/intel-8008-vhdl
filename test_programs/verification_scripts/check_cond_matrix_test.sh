#!/bin/bash

# ============================================================================
# CONDITIONAL 48-COMBO MATRIX (VPLAN XP-08 + ST-11 taken/not-taken pairing)
# ============================================================================
# Program: cond_matrix_test_as.asm (GENERATED - see gen_cond_matrix.py)
#
# {JMP,CAL,RET} x {C,Z,S,P} x {sense} x {flag value} = 48 combos, each
# checkpointed. D counts taken calls, E counts not-taken returns; any
# wrong branch lands on FAIL (checkpoint 0xFE) or skews a counter.
#
# Pairing (closes the ST-11 residual): every conditional's measured
# T-state count must equal the datasheet value FOR ITS OUTCOME -
# 11/9 for J and C, 5/3 for R (DS72 p.45) - not just fall in the set.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "$SCRIPT_DIR/checkpoint_lib.sh"

run_test "cond_matrix_test_as" "40ms"

echo ""
echo "=== Conditional Matrix ==="

# FAIL sentinel must never fire
assert_checkpoint_absent 254

# Per-combo counter trace + final checkpoint
while read -r id family flag sense value taken dexp eexp states; do
    [ "${id:0:1}" = "#" ] && continue
    assert_checkpoint "$id" \
        "$(printf 'D=0x%02X' "$dexp")" \
        "$(printf 'E=0x%02X' "$eexp")"
done < "$PROJECT_DIR/test_programs/cond_matrix_expected.txt"

assert_checkpoint 49 \
    "D=0x08" \
    "E=0x08"

# --- taken/not-taken state-count pairing ------------------------------
echo ""
echo "=== State-count pairing (DS72 p.45) ==="
python3 - "$LOG_FILE" "$PROJECT_DIR/test_programs/cond_matrix_expected.txt" <<'PYEOF'
import re, sys

log_path, exp_path = sys.argv[1], sys.argv[2]

expected = []   # (id, family, states) in program order
for line in open(exp_path):
    if line.startswith("#"):
        continue
    f = line.split()
    expected.append((int(f[0]), f[1], int(f[8])))

def is_conditional(op):
    if (op & 0xC7) == 0x40:  return True   # Jcc  01 xcc 000
    if (op & 0xC7) == 0x42:  return True   # Ccc  01 xcc 010
    if (op & 0xC7) == 0x03:  return True   # Rcc  00 xcc 011
    return False

# Instruction windows between PCI markers (check_cycle_count idiom)
events = []
re_state = re.compile(r'STATE: (\w+) -> (\w+)')
re_pci   = re.compile(r'MCycle: T2 cycle_type=PCI \(cycle 1\)')
re_ir    = re.compile(r'IR: Loading from bus = 0x([0-9A-Fa-f]{2})')
for line in open(log_path, errors='replace'):
    if re_state.search(line):
        events.append(('state',))
    elif re_pci.search(line):
        events.append(('pci',))
    else:
        m = re_ir.search(line)
        if m:
            events.append(('ir', int(m.group(1), 16)))

measured = []   # (opcode, states) for conditional opcodes, in order
count, opcode, started = 0, None, False
for ev in events:
    if ev[0] == 'pci':
        if started and opcode is not None and is_conditional(opcode):
            measured.append((opcode, count))
        count, opcode, started = 0, None, True
    elif ev[0] == 'state':
        if started:
            count += 1
    elif ev[0] == 'ir':
        if started and opcode is None:
            opcode = ev[1]

errors = 0
if len(measured) < len(expected):
    print(f"[FAIL] only {len(measured)} conditionals measured, expected {len(expected)}")
    errors += 1
for (cid, family, want), (op, got) in zip(expected, measured):
    if got != want:
        print(f"[FAIL] combo {cid} ({family}, op 0x{op:02X}): {got} states, "
              f"expected {want} for its outcome")
        errors += 1
if errors == 0:
    print(f"[PASS] all {len(expected)} conditionals matched their "
          f"outcome-specific state count")
    print("PAIRING PASSED")
else:
    sys.exit(1)
PYEOF
PAIR_STATUS=$?
if [ $PAIR_STATUS -ne 0 ]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
fi
TOTAL_ASSERTIONS=$((TOTAL_ASSERTIONS + 1))
[ $PAIR_STATUS -eq 0 ] && PASS_COUNT=$((PASS_COUNT + 1))

print_summary
exit $?
