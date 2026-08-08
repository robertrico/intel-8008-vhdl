#!/usr/bin/env python3
# Differential comparator for the b8008 fuzzer: diffs the JSONL traces
# of the same seeds run on two DUT variants (rtl vs netlist-core).
#
#   python3 fuzz_compare.py [--dir fuzz_out] [--a rtl] [--b netlist-core]
#
# Exit 0 = every common seed's trace is identical record-for-record.
# Missing counterpart traces are an error (a variant silently skipping
# seeds must not pass).

import argparse
import glob
import json
import os
import sys


def load(path):
    with open(path) as f:
        return [json.loads(line) for line in f]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default=os.path.join(
        os.path.dirname(__file__), "fuzz_out"))
    ap.add_argument("--a", default="rtl")
    ap.add_argument("--b", default="netlist-core")
    args = ap.parse_args()

    a_traces = sorted(glob.glob(os.path.join(args.dir, f"trace_{args.a}_*.jsonl")))
    if not a_traces:
        print(f"[FAIL] no {args.a} traces in {args.dir}")
        return 1

    bad = 0
    for pa in a_traces:
        seed = pa.rsplit("_", 1)[1].removesuffix(".jsonl")
        pb = os.path.join(args.dir, f"trace_{args.b}_{seed}.jsonl")
        if not os.path.exists(pb):
            print(f"[FAIL] seed {seed}: no {args.b} trace")
            bad += 1
            continue
        ta, tb = load(pa), load(pb)
        if ta == tb:
            print(f"[PASS] seed {seed}: {len(ta)} records identical")
            continue
        bad += 1
        if len(ta) != len(tb):
            print(f"[FAIL] seed {seed}: {len(ta)} vs {len(tb)} records")
        for i, (ra, rb) in enumerate(zip(ta, tb)):
            if ra != rb:
                print(f"[FAIL] seed {seed} record {i}: {ra} vs {rb}")
                break

    if bad:
        print(f"\n{bad} seed(s) diverged between {args.a} and {args.b}")
        return 1
    print(f"\nAll {len(a_traces)} seeds identical between {args.a} and {args.b}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
