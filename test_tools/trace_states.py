#!/usr/bin/env python3
"""
Trace state-by-state execution with data bus values.
Shows exactly what happens at each state transition.
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

CYCLE_TYPES = {
    '00': 'PCI',
    '01': 'PCR',
    '10': 'PCW',
    '11': 'PCC'
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
    return STATES.get(bits, f'UNK({bits})')

def trace_states(csv_file, start_us, end_us):
    """Trace state-by-state with data bus values."""

    print(f"Tracing states in {csv_file} from {start_us}us to {end_us}us")
    print("=" * 90)

    rows = parse_csv(csv_file)

    prev_sync = None
    prev_state = None
    state_num = 0
    cycle_num = 0

    for i, row in enumerate(rows):
        time_s = float(row['Time(s)'])
        time_us = time_s * 1e6

        if time_us < start_us:
            prev_sync = row[' SYNC'].strip()
            continue
        if time_us > end_us:
            break

        state = get_state(row)
        sync = row[' SYNC'].strip()
        data = get_data_byte(row)
        cp_d_en = row[' CP_D_EN'].strip()
        int_sig = row[' INT'].strip()

        # Detect state transitions (SYNC rising edge)
        if sync == '1' and prev_sync == '0':
            state_num += 1

            # Track cycle boundaries (T1 starts new cycle)
            if state == 'T1' or state == 'T1I':
                cycle_num += 1
                print(f"\n--- Cycle #{cycle_num} ---")

            # Get cycle type from D7:D6 during T2
            cycle_type = "?"
            if state == 'T2' and data is not None:
                ct_bits = f"{(data >> 6) & 0x3:02b}"
                cycle_type = CYCLE_TYPES.get(ct_bits, f"?({ct_bits})")

            print(f"State #{state_num:3d} @ {time_us:6.1f}us: {state:6s}  Data=0x{data:02X}  " +
                  f"CP_D_EN={cp_d_en}  INT={int_sig}" +
                  (f"  CycleType={cycle_type}" if state == 'T2' else ""))

        prev_sync = sync
        prev_state = state

    print(f"\n{'=' * 90}")
    print(f"Traced {state_num} states, {cycle_num} cycles")

if __name__ == '__main__':
    if len(sys.argv) < 4:
        print("Usage: trace_states.py <csv_file> <start_us> <end_us>")
        print("Example: trace_states.py test3.csv 75 85")
        sys.exit(1)

    csv_file = sys.argv[1]
    start_us = float(sys.argv[2])
    end_us = float(sys.argv[3])

    trace_states(csv_file, start_us, end_us)
