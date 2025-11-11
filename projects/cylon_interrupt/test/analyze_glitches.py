#!/usr/bin/env python3
"""
Analyze logic analyzer CSV for bus contention glitches.

Looks for:
1. Data bus changes during same state (bus contention)
2. CP_D_EN conflicts (multiple drivers)
3. State glitches
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
    """Extract data bus value from row (D7=MSB, D0=LSB)."""
    bits = ''.join([row[f' D{i}'].strip() for i in range(7, -1, -1)])
    return int(bits, 2) if '?' not in bits else None

def get_state(row):
    """Get state from S2 S1 S0."""
    bits = row[' S2'].strip() + row[' S1'].strip() + row[' S0'].strip()
    return STATES.get(bits, f'UNKNOWN({bits})')

def analyze_glitches(csv_file, start_time_us=None, end_time_us=None):
    """Analyze CSV for bus contention and glitches."""

    print(f"Analyzing {csv_file}")
    print("=" * 80)

    rows = parse_csv(csv_file)

    # Filter by time range if specified
    if start_time_us is not None or end_time_us is not None:
        filtered = []
        for row in rows:
            time_s = float(row['Time(s)'])
            time_us = time_s * 1e6
            if start_time_us is not None and time_us < start_time_us:
                continue
            if end_time_us is not None and time_us > end_time_us:
                break
            filtered.append(row)
        rows = filtered
        print(f"Filtered to time range: {start_time_us}us - {end_time_us}us")
        print(f"Samples: {len(rows)}")
        print("=" * 80)

    # Track state for glitch detection
    prev_sync = None
    prev_state = None
    prev_data = None
    prev_cp_d_en = None

    current_state_start = 0
    state_data_values = []

    glitch_count = 0

    for i, row in enumerate(rows):
        time_s = float(row['Time(s)'])
        time_us = time_s * 1e6

        sync = row[' SYNC'].strip()
        state = get_state(row)
        data = get_data_byte(row)
        cp_d_en = row[' CP_D_EN'].strip()

        # Detect state transition (SYNC rising edge)
        if sync == '1' and prev_sync == '0':
            # Check for data glitches within previous state
            if len(state_data_values) > 1:
                unique_values = set(state_data_values)
                if len(unique_values) > 1:
                    glitch_count += 1
                    print(f"\n*** GLITCH #{glitch_count} at ~{time_us:.1f}us ***")
                    print(f"  State: {prev_state}")
                    print(f"  Multiple data values within same state:")
                    for val in unique_values:
                        count = state_data_values.count(val)
                        print(f"    0x{val:02X} ({val:08b}) - {count} samples")
                    print(f"  Line range: {current_state_start} - {i}")

            # Start new state
            current_state_start = i
            state_data_values = []
            prev_state = state

        # Track data values within current state
        if data is not None:
            state_data_values.append(data)

        # Check for CP_D_EN glitches (should be stable during state)
        if cp_d_en != prev_cp_d_en and prev_sync == sync and sync != '?':
            print(f"\n*** CP_D_EN GLITCH at {time_us:.1f}us (line {i}) ***")
            print(f"  CP_D_EN changed from {prev_cp_d_en} to {cp_d_en}")
            print(f"  State: {state}, SYNC: {sync}")

        prev_sync = sync
        prev_data = data
        prev_cp_d_en = cp_d_en

    print(f"\n{'=' * 80}")
    print(f"Total glitches found: {glitch_count}")
    print(f"{'=' * 80}")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: analyze_glitches.py <csv_file> [start_us] [end_us]")
        print("Example: analyze_glitches.py test2.csv 55 56")
        sys.exit(1)

    csv_file = sys.argv[1]
    start_us = float(sys.argv[2]) if len(sys.argv) > 2 else None
    end_us = float(sys.argv[3]) if len(sys.argv) > 3 else None

    analyze_glitches(csv_file, start_us, end_us)
