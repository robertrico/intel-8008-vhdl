#!/usr/bin/env python3
"""
analyze_logic_csv.py - Analyze logic analyzer CSV for glitches and anomalies

Usage:
    python3 analyze_logic_csv.py <csv_file>
"""

import csv
import sys


def load_csv(filename):
    """Load and parse CSV file, returning list of row dicts with stripped keys."""
    with open(filename, 'r') as f:
        lines = f.readlines()

    # Find the header line
    header_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('Time'):
            header_idx = i
            break

    # Parse CSV - strip whitespace from field names
    reader = csv.DictReader(lines[header_idx:], skipinitialspace=True)
    rows = [{k.strip(): v for k, v in row.items()} for row in list(reader)]
    return rows


def get_data_byte(row):
    """Extract D0-D7 as a byte value."""
    data = 0
    for bit in range(8):
        data |= (int(row[f'D{bit}']) << bit)
    return data


def analyze_interrupts(rows):
    """Analyze interrupt signals."""
    int_rst_high = sum(1 for r in rows if r['INT_RST'] == '1')
    int_rst_low = sum(1 for r in rows if r['INT_RST'] == '0')
    int_pending_high = sum(1 for r in rows if r['INT_PENDING'] == '1')
    int_pending_low = sum(1 for r in rows if r['INT_PENDING'] == '0')

    print(f"\nInterrupt signals:")
    print(f"  INT_RST: high={int_rst_high}, low={int_rst_low}")
    print(f"  INT_PENDING: high={int_pending_high}, low={int_pending_low}")

    # Check CPU_SYNC
    sync_high = sum(1 for r in rows if r['CPU_SYNC'] == '1')
    sync_low = sum(1 for r in rows if r['CPU_SYNC'] == '0')
    print(f"  CPU_SYNC: high={sync_high}, low={sync_low}")


def analyze_state_transitions(rows, max_transitions=50):
    """Show state transitions."""
    # Correct 8008 state encoding for S[2:0]
    state_names = {
        '000': 'WAIT',
        '001': 'T3',
        '010': 'T1',
        '011': 'STOP',
        '100': 'T2',
        '101': 'T5',
        '110': 'T1I',
        '111': 'T4'
    }

    print(f"\nFirst {max_transitions} state transitions:")
    prev_state = None
    count = 0
    for r in rows:
        state = f"{r['S2']}{r['S1']}{r['S0']}"
        if state != prev_state:
            data = get_data_byte(r)
            name = state_names.get(state, '???')
            print(f"  t={float(r['Time(s)']):.6f}, {state}({name:4}), data=0x{data:02X}, "
                  f"sync={r['CPU_SYNC']}, int_rst={r['INT_RST']}, int_pend={r['INT_PENDING']}")
            prev_state = state
            count += 1
            if count >= max_transitions:
                break


def analyze_rom_reads(rows, max_samples=100000):
    """Separate T3 ROM reads from CPU outputs in other states."""
    print("\n\nAnalyzing ROM reads (T3) vs CPU outputs:")

    print("\nT3 (ROM reads) - first 20 unique transitions:")
    prev_state = None
    t3_count = 0
    for r in rows[:max_samples]:
        state = f"{r['S2']}{r['S1']}{r['S0']}"
        if state != prev_state:
            data = get_data_byte(r)
            if state == '001':  # T3
                t3_count += 1
                if t3_count <= 20:
                    print(f"  T3: data=0x{data:02X} at t={r['Time(s)']}")
            prev_state = state

    print("\nT1 (CPU outputs low addr) - first 10:")
    prev_state = None
    t1_count = 0
    for r in rows[:max_samples]:
        state = f"{r['S2']}{r['S1']}{r['S0']}"
        if state != prev_state:
            data = get_data_byte(r)
            if state == '010':  # T1
                t1_count += 1
                if t1_count <= 10:
                    print(f"  T1: addr_low=0x{data:02X} at t={r['Time(s)']}")
            prev_state = state

    print("\nT2 (CPU outputs high addr) - first 10:")
    prev_state = None
    t2_count = 0
    for r in rows[:max_samples]:
        state = f"{r['S2']}{r['S1']}{r['S0']}"
        if state != prev_state:
            data = get_data_byte(r)
            if state == '100':  # T2
                t2_count += 1
                if t2_count <= 10:
                    print(f"  T2: addr_high=0x{data:02X} at t={r['Time(s)']}")
            prev_state = state


def analyze_fetch_sequence(rows, max_fetches=20):
    """Track T1->T2->T3 sequences to see address vs data read."""
    print(f"\n\nMemory fetch sequence (first {max_fetches} fetches):")
    print("  Addr     → Data (Expected from ROM)")
    print("  -------- → ----")

    addr_low = None
    addr_high = None
    prev_state = None
    fetch_count = 0

    for r in rows:
        state = f"{r['S2']}{r['S1']}{r['S0']}"
        if state != prev_state:
            data = get_data_byte(r)

            if state == '010':  # T1 - low address
                addr_low = data
            elif state == '100':  # T2 - high address
                addr_high = data
            elif state == '001':  # T3 - data read
                if addr_low is not None and addr_high is not None:
                    addr = (addr_high << 8) | addr_low
                    fetch_count += 1
                    if fetch_count <= max_fetches:
                        print(f"  0x{addr:04X} → 0x{data:02X}")
                    addr_low = None
                    addr_high = None
            elif state == '110':  # T1I - interrupt, captures addr differently
                addr_low = data  # During T1I, data bus has status/addr info

            prev_state = state

        if fetch_count >= max_fetches:
            break


def analyze_csv(filename):
    # Load CSV
    rows = load_csv(filename)

    print(f"Total samples: {len(rows)}")
    print(f"Time range: {rows[0]['Time(s)']} to {rows[-1]['Time(s)']}")

    # Analyze interrupts and state transitions first
    analyze_interrupts(rows)
    analyze_state_transitions(rows, max_transitions=50)
    analyze_rom_reads(rows)
    analyze_fetch_sequence(rows)

    # Glitch analysis
    glitches = []

    # Look for glitches - data changes that last only 1-2 samples (50-100ns at 20MHz)
    prev_data = None
    data_change_start = None
    data_at_change = None

    glitch_count = 0
    normal_count = 0

    for i, row in enumerate(rows):
        # Combine D0-D7 into a byte
        data = 0
        for bit in range(8):
            data |= (int(row[f'D{bit}']) << bit)

        time = float(row['Time(s)'])

        if prev_data is not None and data != prev_data:
            # Data changed
            if data_change_start is not None:
                # Calculate duration of previous value
                duration = time - data_change_start
                duration_ns = duration * 1e9

                if duration_ns < 200:  # Less than 200ns = potential glitch
                    glitch_count += 1
                    if glitch_count <= 50:  # Show first 50 glitches
                        glitches.append({
                            'time': data_change_start,
                            'duration_ns': duration_ns,
                            'value': data_at_change,
                            'sync': row['CPU_SYNC'],
                            'state': f"{row['S2']}{row['S1']}{row['S0']}"
                        })
                else:
                    normal_count += 1

            data_change_start = time
            data_at_change = data

        prev_data = data

    print(f"\nGlitch analysis (data changes < 200ns):")
    print(f"  Glitches found: {glitch_count}")
    print(f"  Normal transitions: {normal_count}")

    print(f"\nFirst 50 glitches:")
    for g in glitches[:50]:
        print(f"  t={g['time']:.6f}s, dur={g['duration_ns']:.1f}ns, data=0x{g['value']:02X}, sync={g['sync']}, state={g['state']}")

    # Also look at what data values appear when CPU_DATA_EN is high
    print("\n\nData values when CPU_DATA_EN=1:")
    data_en_values = {}
    for row in rows:
        if row['CPU_DATA_EN'] == '1':
            data = 0
            for bit in range(8):
                data |= (int(row[f'D{bit}']) << bit)
            data_en_values[data] = data_en_values.get(data, 0) + 1

    # Sort by frequency
    sorted_values = sorted(data_en_values.items(), key=lambda x: -x[1])[:30]
    for val, count in sorted_values:
        print(f"  0x{val:02X}: {count} samples")

    # Check for 0x9A specifically
    print("\n\nChecking for 0x9A on data bus:")
    nine_a_count = 0
    for row in rows:
        data = 0
        for bit in range(8):
            data |= (int(row[f'D{bit}']) << bit)
        if data == 0x9A:
            nine_a_count += 1
    print(f"  0x9A appears {nine_a_count} times on data bus")

    # Look at state machine transitions
    print("\n\nState machine (S2,S1,S0) distribution:")
    state_counts = {}
    for row in rows:
        state = f"{row['S2']}{row['S1']}{row['S0']}"
        state_counts[state] = state_counts.get(state, 0) + 1

    # Correct 8008 state encoding
    state_names = {
        '000': 'WAIT',
        '001': 'T3 (data)',
        '010': 'T1 (addr low)',
        '011': 'STOP',
        '100': 'T2 (addr high)',
        '101': 'T5',
        '110': 'T1I (int ack)',
        '111': 'T4'
    }
    for state, count in sorted(state_counts.items()):
        name = state_names.get(state, 'UNKNOWN')
        print(f"  {state} ({name}): {count} samples")


if __name__ == '__main__':
    if len(sys.argv) < 2:
        filename = '/Users/hambook/Development/intel-8008-vhdl/projects/b8008_monitor/logic.csv'
    else:
        filename = sys.argv[1]

    analyze_csv(filename)
