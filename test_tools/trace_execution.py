#!/usr/bin/env python3
"""
Trace instruction execution from logic analyzer CSV.
Shows instruction fetches and data after interrupt acknowledge.
"""

import csv
import sys

# State encoding: S2 S1 S0
STATES = {
    '010': 'T1',
    '100': 'T2',
    '001': 'T3',
    '110': 'T1I',
    '011': 'STOPPED',
    '111': 'T4',
    '101': 'T5',
    '000': 'TWAIT'
}

def parse_csv(filename):
    """Parse CSV and return data rows."""
    with open(filename, 'r') as f:
        lines = f.readlines()

    # Find header line
    data_start = 0
    for i, line in enumerate(lines):
        if line.startswith('Time'):
            data_start = i
            break

    return list(csv.DictReader(lines[data_start:]))

def get_data_byte(row):
    """Extract data bus value (D7=MSB, D0=LSB)."""
    bits = ''.join([row[f' D{i}'].strip() for i in range(7, -1, -1)])
    return int(bits, 2) if '?' not in bits else None

def get_state(row):
    """Get state from S2 S1 S0."""
    bits = row[' S2'].strip() + row[' S1'].strip() + row[' S0'].strip()
    return STATES.get(bits, f'UNKNOWN({bits})')

def trace_execution(csv_file, max_instructions=30):
    """Trace execution starting from T1I."""

    print(f"Tracing execution in {csv_file}")
    print("=" * 80)

    rows = parse_csv(csv_file)

    prev_sync = None
    after_t1i = False
    instr_num = 0
    current_instr = {'t1_line': None, 't1_data': None, 't3_line': None, 't3_data': None}

    for i, row in enumerate(rows):
        time_s = float(row['Time(s)'])
        time_us = time_s * 1e6

        state = get_state(row)
        sync = row[' SYNC'].strip()
        data = get_data_byte(row)

        # Detect state transitions
        if sync == '1' and prev_sync == '0':
            if state == 'T1I':
                after_t1i = True
                print(f"\n{'='*80}")
                print(f"Line {i}: T1I at {time_us:.1f}us - INTERRUPT ACKNOWLEDGED")
                print(f"{'='*80}\n")

            if after_t1i:
                if state == 'T1':
                    # Start new instruction
                    if current_instr['t1_line'] is not None and current_instr['t3_data'] is not None:
                        # Print previous instruction
                        instr_num += 1
                        print(f"#{instr_num:2d} @{current_instr['t1_line']:5d}: Opcode=0x{current_instr['t3_data']:02X}")

                    current_instr = {'t1_line': i, 't1_data': data, 't3_line': None, 't3_data': None}

                elif state == 'T3':
                    current_instr['t3_line'] = i
                    current_instr['t3_data'] = data

                if instr_num >= max_instructions:
                    break

        prev_sync = sync

    print(f"\n{'='*80}")
    print(f"Traced {instr_num} instructions")
    print(f"{'='*80}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: trace_execution.py <csv_file> [max_instructions]")
        sys.exit(1)

    csv_file = sys.argv[1]
    max_instr = int(sys.argv[2]) if len(sys.argv) > 2 else 30

    trace_execution(csv_file, max_instr)
