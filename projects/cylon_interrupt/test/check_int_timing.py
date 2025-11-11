#!/usr/bin/env python3
"""
Check when INT goes high and what state the CPU is in at that moment.
This helps verify if interrupts are being acknowledged at the correct time
(right before PCI cycle, not during).
"""

import sys
import csv

if len(sys.argv) < 2:
    print("Usage: python3 check_int_timing.py <csv_file>")
    sys.exit(1)

csv_file = sys.argv[1]

# Read the CSV file
with open(csv_file, 'r') as f:
    lines = f.readlines()

# Find header line
header_idx = None
for i, line in enumerate(lines):
    if line.startswith('Time(s)'):
        header_idx = i
        break

# Find when INT goes high and what happens next
prev_int = '0'

for i in range(header_idx + 1, len(lines)):
    parts = lines[i].strip().split(',')
    if len(parts) < 9:
        continue

    time = float(parts[0])
    int_val = parts[4].strip()
    s2 = parts[7].strip()
    s1 = parts[6].strip()
    s0 = parts[5].strip()

    # Decode state
    state = 'UNKNOWN'
    if s2 == '0' and s1 == '1' and s0 == '0':
        state = 'T1'
    elif s2 == '1' and s1 == '0' and s0 == '0':
        state = 'T2'
    elif s2 == '0' and s1 == '0' and s0 == '1':
        state = 'T3'
    elif s2 == '1' and s1 == '1' and s0 == '0':
        state = 'T1I'
    elif s2 == '1' and s1 == '0' and s0 == '1':
        state = 'T5'
    elif s2 == '1' and s1 == '1' and s0 == '1':
        state = 'T4'

    if int_val == '1' and prev_int == '0':
        print(f"INT rising edge at line {i+1}: {time*1e6:.2f}us, State={state}")

        # Show next 30 lines to see full interrupt sequence
        print("\nStates after INT goes high:")
        for j in range(i, min(i+30, len(lines))):
            parts2 = lines[j].strip().split(',')
            if len(parts2) < 9:
                continue
            time2 = float(parts2[0])
            int2 = parts2[4].strip()
            s2_2 = parts2[7].strip()
            s1_2 = parts2[6].strip()
            s0_2 = parts2[5].strip()

            state2 = 'UNKNOWN'
            if s2_2 == '0' and s1_2 == '1' and s0_2 == '0':
                state2 = 'T1'
            elif s2_2 == '1' and s1_2 == '0' and s0_2 == '0':
                state2 = 'T2'
            elif s2_2 == '0' and s1_2 == '0' and s0_2 == '1':
                state2 = 'T3'
            elif s2_2 == '1' and s1_2 == '0' and s0_2 == '1':
                state2 = 'T5'
            elif s2_2 == '1' and s1_2 == '1' and s0_2 == '0':
                state2 = 'T1I'
            elif s2_2 == '1' and s1_2 == '1' and s0_2 == '1':
                state2 = 'T4'

            print(f"  Line {j+1}: {time2*1e6:7.2f}us, State={state2:7s}, INT={int2}")

            # Stop at end of interrupt acknowledge sequence
            if state2 == 'T1' and j > i + 10:
                break
        break

    prev_int = int_val
