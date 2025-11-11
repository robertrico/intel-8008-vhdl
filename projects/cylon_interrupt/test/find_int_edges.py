#!/usr/bin/env python3
"""
Find all INT rising edges in a CSV capture
"""

import sys
import csv

if len(sys.argv) < 2:
    print("Usage: python3 find_int_edges.py <csv_file>")
    sys.exit(1)

csv_file = sys.argv[1]

# Skip comment lines, find header
with open(csv_file, 'r') as f:
    for line in f:
        if line.startswith('Time(s)'):
            header = [col.strip() for col in line.split(',')]
            break

# Find INT rising edges
int_high_times = []
with open(csv_file, 'r') as f:
    # Skip to data
    for line in f:
        if line.startswith('Time(s)'):
            break

    # Parse data
    reader = csv.DictReader(f, fieldnames=header)
    prev_int = '0'
    line_num = 6  # Start after header

    for row in reader:
        line_num += 1
        int_val = row['INT'].strip()
        time = float(row['Time(s)'].strip())

        # Find rising edges (0->1 transitions)
        if int_val == '1' and prev_int == '0':
            int_high_times.append((line_num, time))

        prev_int = int_val

print(f'Found {len(int_high_times)} INT rising edges:')
for i, (line, t) in enumerate(int_high_times):
    print(f'  Edge {i+1}: Line {line:5d} @ {t*1e6:8.2f}us')
