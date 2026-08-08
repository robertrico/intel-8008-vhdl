# Differential fuzzer for the b8008 core (VPLAN robustness harness,
# TODO item 5). Random LEGAL 8008 instruction streams (fuzz_gen.py,
# isa.json encodings) run whole-system under three oracles at once:
#
#   1. Bus-protocol monitor - every CPU-driven byte at every T-state
#      checked against the golden decoder (test_b8008_top machinery)
#   2. Timing oracle - every instruction window's T-state count must
#      equal the isa.json datasheet value FOR ITS OUTCOME (branch
#      outcome inferred from the next fetch address), and non-branch
#      instructions must advance PC by exactly their encoded length
#   3. Differential trace - one JSONL record per machine cycle plus a
#      final register/flag/ram trailer, written to fuzz_out/. Running
#      the same seeds on the rtl core and the write_vhdl netlist core
#      (make fuzz-b8008 DUT_VARIANT=netlist-core) and diffing with
#      fuzz_compare.py closes the loop.
#
# Reproducibility: FUZZ_BASE/FUZZ_COUNT/FUZZ_LEN env vars; a failing
# seed's program listing is dumped to fuzz_out/fail_<seed>.txt.
# Shrinking: FUZZ_SHRINK_SEED=<n> binary-searches the shortest failing
# main-body prefix and dumps fuzz_out/shrunk_<seed>.txt.

import json
import os

import cocotb

from fuzz_gen import gen
from test_b8008_top import run_monitor_mem

OUT_DIR = os.path.join(os.path.dirname(__file__), "fuzz_out")

FUZZ_BASE = int(os.environ.get("FUZZ_BASE", "0"))
FUZZ_COUNT = int(os.environ.get("FUZZ_COUNT", "10"))
FUZZ_LEN = int(os.environ.get("FUZZ_LEN", "150"))
VARIANT = (os.environ.get("FUZZ_VARIANT") or
           os.environ.get("DUT_VARIANT") or "rtl")
SHRINK_SEED = os.environ.get("FUZZ_SHRINK_SEED")


def _dump(path, seed, meta, note=""):
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(path, "w") as f:
        f.write(f"; seed {seed} len {FUZZ_LEN} {note}\n")
        f.write("\n".join(meta) + "\n")


async def _run_seed(dut, seed, limit=None, trace=None):
    mem, meta = gen(seed, main_len=FUZZ_LEN, limit=limit)
    try:
        await run_monitor_mem(dut, mem, max_ms=200, timing=True,
                              trace=trace, tag=f"seed{seed}: ",
                              min_checks=10)
    except AssertionError:
        _dump(os.path.join(OUT_DIR, f"fail_{seed}.txt"), seed, meta,
              f"limit={limit}")
        raise


@cocotb.test(skip=SHRINK_SEED is not None)
async def fuzz_random_programs(dut):
    """FUZZ_COUNT seeded random programs under all three oracles."""
    os.makedirs(OUT_DIR, exist_ok=True)
    for seed in range(FUZZ_BASE, FUZZ_BASE + FUZZ_COUNT):
        trace = []
        await _run_seed(dut, seed, trace=trace)
        path = os.path.join(OUT_DIR, f"trace_{VARIANT}_{seed}.jsonl")
        with open(path, "w") as f:
            for rec in trace:
                f.write(json.dumps(rec) + "\n")
        dut._log.info(f"seed {seed}: {len(trace)} trace records -> {path}")


@cocotb.test(skip=SHRINK_SEED is None)
async def fuzz_shrink(dut):
    """Binary-search the shortest failing main-body prefix of a seed."""
    seed = int(SHRINK_SEED)

    async def fails(limit):
        try:
            await _run_seed(dut, seed, limit=limit)
            return False
        except AssertionError:
            return True

    assert await fails(None), f"seed {seed} does not fail at full length"
    lo, hi = 1, FUZZ_LEN          # invariant: hi fails
    while lo < hi:
        mid = (lo + hi) // 2
        if await fails(mid):
            hi = mid
        else:
            lo = mid + 1
    mem, meta = gen(seed, main_len=FUZZ_LEN, limit=hi)
    _dump(os.path.join(OUT_DIR, f"shrunk_{seed}.txt"), seed, meta,
          f"shortest failing prefix: {hi} instructions")
    dut._log.info(f"seed {seed}: shortest failing prefix = {hi}")
    raise AssertionError(f"seed {seed} fails from prefix {hi} "
                         f"(listing in fuzz_out/shrunk_{seed}.txt)")
