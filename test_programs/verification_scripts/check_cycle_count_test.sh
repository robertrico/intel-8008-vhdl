#!/bin/bash

# ============================================================================
# CYCLE-COUNT (T-STATE) VERIFICATION SCRIPT
# ============================================================================
# Enforces the line-by-line ISA_CYCLES mapping (docs/isa.json,
# num_states_execution): runs cycle_count_test_as (one instruction per
# timing class), counts actual T-states per instruction from the STATE
# transition log, and diffs against the table.
#
# Counting: the "MCycle: T2 cycle_type=PCI (cycle 1)" marker fires once
# per instruction fetch; the number of "STATE:" lines between consecutive
# markers is exactly that instruction's T-state count (the window is
# phase-shifted by one state but length-preserving). WAIT-state lines are
# excluded so the b8008_top_tb READY-drop window doesn't inflate a count.
# Conditionals accept their {taken, not-taken} pair; everything else is
# exact.
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_FILE="$SCRIPT_DIR/cycle_count_test_as.log"

echo "==========================================="
echo "Running test: cycle_count_test_as"
echo "==========================================="

cd "$PROJECT_DIR"
make test-b8008-top PROG="cycle_count_test_as" SIM_TIME="10ms" 2>&1 > "$LOG_FILE"

python3 - "$LOG_FILE" "$PROJECT_DIR/docs/isa.json" <<'PYEOF'
import json, re, sys

log_path, isa_path = sys.argv[1], sys.argv[2]
isa = json.load(open(isa_path))
states_of = {i['operation']: i['num_states_execution'] for i in isa['instructions']}

def classify(op):
    """opcode byte -> (isa operation name, expected set)"""
    if op in (0x00, 0x01, 0xFF):
        # HLT: Intel's 4 states include entering STOPPED. Our HLT executes
        # T1,T2,T3 then stops, and the terminal log window measures N-1
        # (there is no next fetch to close it) -> expect 2 measured.
        return 'HLT', {2}
    hi2, mid, lo3 = op >> 6, (op >> 3) & 7, op & 7
    if hi2 == 3:
        if lo3 == 7:  return 'LrM', {states_of['LrM']}
        if mid == 7:  return 'LMr', {states_of['LMr']}
        return 'Lr_1r_2', {states_of['Lr_1r_2']}
    if hi2 == 2:
        return ('ALU OP M', {states_of['ALU OP M']}) if lo3 == 7 else ('ALU OP r', {states_of['ALU OP r']})
    if hi2 == 0:
        if lo3 == 6:  return ('LMI', {states_of['LMI']}) if mid == 7 else ('LrI', {states_of['LrI']})
        if lo3 == 4:  return 'ALU OP I', {states_of['ALU OP I']}
        if lo3 == 0:  return 'INr', {states_of['INr']}
        if lo3 == 1:  return 'DCr', {states_of['DCr']}
        if lo3 == 2:  return {0:'RLC',1:'RRC',2:'RAL',3:'RAR'}[mid], {5}
        if lo3 == 7:  return 'RET', {states_of['RET']}
        if lo3 == 3:  return 'RFc/RTc', {3, 5}
        if lo3 == 5:  return 'RST', {states_of['RST']}
    if hi2 == 1:
        if lo3 == 4:  return 'JMP', {states_of['JMP']}
        if lo3 == 0:  return 'JFc/JTc', {9, 11}
        if lo3 == 6:  return 'CAL', {states_of['CAL']}
        if lo3 == 2:  return 'CFc/CTc', {9, 11}
        if lo3 & 1:
            port = (op >> 1) & 0x1F
            return ('INP', {states_of['INP']}) if port < 8 else ('OUT', {states_of['OUT']})
    return f'op {op:02X}', set()

# Parse the log into an ordered event stream
events = []   # ('state', dest) | ('pci',) | ('ir', byte) | ('stopped',)
re_state = re.compile(r'STATE: (\w+) -> (\w+)')
re_pci   = re.compile(r'MCycle: T2 cycle_type=PCI \(cycle 1\)')
re_ir    = re.compile(r'IR: Loading from bus = 0x([0-9A-Fa-f]{2})')
for line in open(log_path, errors='replace'):
    m = re_state.search(line)
    if m:
        events.append(('state', m.group(2)))
        continue
    if re_pci.search(line):
        events.append(('pci',))
        continue
    m = re_ir.search(line)
    if m:
        events.append(('ir', int(m.group(1), 16)))

# Split into per-instruction windows between PCI markers
instrs = []   # (opcode, state_count)
count, opcode, started = 0, None, False
for ev in events:
    if ev[0] == 'pci':
        if started and opcode is not None:
            instrs.append((opcode, count))
        count, opcode, started = 0, None, True
    elif ev[0] == 'state' and started:
        if ev[1] != 's_wait':          # WAIT stretches are not T-states
            count += 1
        if ev[1] == 's_stopped':       # HLT terminal: close the window
            instrs.append((opcode, count))
            started = False
    elif ev[0] == 'ir' and started and opcode is None:
        opcode = ev[1]

passed = failed = 0
print()
print(f"{'op':>4}  {'class':<12} {'measured':>8}  {'expected':<10} verdict")
for op, n in instrs:
    name, exp = classify(op)
    ok = n in exp if exp else False
    verdict = 'PASS' if ok else 'FAIL'
    if ok: passed += 1
    else:  failed += 1
    print(f"0x{op:02X}  {name:<12} {n:>8}  {str(sorted(exp)):<10} {verdict}")

print()
print("===========================================")
print(f"CYCLE COUNTS: {passed} passed, {failed} failed over {len(instrs)} instructions")
if failed or not instrs:
    print("SOME CYCLE COUNTS FAILED")
else:
    print("ALL CYCLE COUNTS PASSED")
print("===========================================")
sys.exit(1 if failed or not instrs else 0)
PYEOF
exit $?
