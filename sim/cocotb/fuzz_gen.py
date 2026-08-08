# Seeded random-program generator for the b8008 differential fuzzer.
#
# Emits LEGAL 8008 instruction streams only (encodings per docs/isa.json /
# DS72) with structural guarantees that make every program terminate:
#
#   - main body is straight-line; jumps are FORWARD-ONLY to instruction
#     boundaries in main (or the final HLT)
#   - calls target a small pool of leaf subroutines (no calls inside),
#     each ending in RET -> stack depth <= 2, well under the 7-level limit
#   - RST vectors 1..7 hold a single RET, so RST is a call-and-return
#   - RET/RFc/RTc never appear at main level (nothing to return to)
#   - memory operands are pinned into RAM (0x2000-0x23FF) by an emitted
#     MVI H / MVI L pair before every M-op
#   - undefined opcodes (0x38/0x39) and mid-stream HLT are never emitted
#
# gen(seed, main_len, limit) -> (mem, meta). `limit` truncates the main
# body to its first `limit` instructions (jump targets clamp to the HLT)
# - the shrinker's knob. Reproducible: same args, same program.

import random

MAIN_BASE = 0x0100
SUB_BASE = 0x0040
RAM_H = (0x20, 0x23)   # H byte range for RAM 0x2000-0x23FF

REG_NAMES = "ABCDEHL"


def _safe_instr(rng, out, meta, allow_rcc):
    """One straight-line instruction (no jumps/calls/RST/HLT).
    Appends encoded bytes to out and a text line to meta."""
    choice = rng.randrange(100)
    if choice < 20:                                   # MOV r,r
        d, s = rng.randrange(7), rng.randrange(7)
        out.append(0xC0 | d << 3 | s)
        meta.append(f"MOV {REG_NAMES[d]},{REG_NAMES[s]}")
    elif choice < 32:                                 # MVI r
        d, imm = rng.randrange(7), rng.randrange(256)
        out += [0x06 | d << 3, imm]
        meta.append(f"MVI {REG_NAMES[d]},{imm:#04x}")
    elif choice < 50:                                 # ALU r / ALU I
        p = rng.randrange(8)
        if rng.randrange(2):
            s = rng.randrange(7)
            out.append(0x80 | p << 3 | s)
            meta.append(f"ALU{p} {REG_NAMES[s]}")
        else:
            imm = rng.randrange(256)
            out += [0x04 | p << 3, imm]
            meta.append(f"ALU{p} I,{imm:#04x}")
    elif choice < 58:                                 # INR/DCR (B..L)
        d = rng.randrange(1, 7)
        op = (d << 3) | rng.randrange(2)
        out.append(op)
        meta.append(f"{'INR' if op & 1 == 0 else 'DCR'} {REG_NAMES[d]}")
    elif choice < 66:                                 # rotate
        r = rng.choice([0x02, 0x0A, 0x12, 0x1A])
        out.append(r)
        meta.append({0x02: "RLC", 0x0A: "RRC", 0x12: "RAL", 0x1A: "RAR"}[r])
    elif choice < 88:                                 # M-op with H:L pin
        h = rng.randrange(RAM_H[0], RAM_H[1] + 1)
        l = rng.randrange(256)
        out += [0x06 | 5 << 3, h, 0x06 | 6 << 3, l]
        meta.append(f"MVI H,{h:#04x}")
        meta.append(f"MVI L,{l:#04x}")
        kind = rng.randrange(4)
        if kind == 0:                                 # MOV r,M
            d = rng.randrange(7)
            out.append(0xC7 | d << 3)
            meta.append(f"MOV {REG_NAMES[d]},M")
        elif kind == 1:                               # MOV M,r
            s = rng.randrange(7)
            out.append(0xF8 | s)
            meta.append(f"MOV M,{REG_NAMES[s]}")
        elif kind == 2:                               # MVI M
            imm = rng.randrange(256)
            out += [0x3E, imm]
            meta.append(f"MVI M,{imm:#04x}")
        else:                                         # ALU M
            p = rng.randrange(8)
            out.append(0x87 | p << 3)
            meta.append(f"ALU{p} M")
    elif choice < 94:                                 # INP / OUT
        if rng.randrange(2):
            port = rng.randrange(8)
            out.append(0x41 | port << 1)
            meta.append(f"INP {port}")
        else:
            port = rng.randrange(8, 31)               # 31 = checkpoint port, skip
            out.append(0x41 | port << 1)
            meta.append(f"OUT {port}")
    elif allow_rcc and choice < 97:                   # RFc/RTc (subs only)
        cc = rng.randrange(4)
        op = (0x03 | cc << 3) | (0x20 if rng.randrange(2) else 0)
        out.append(op)
        meta.append(f"Rcc {op:#04x}")
    else:                                             # MOV A,A filler
        out.append(0xC0)
        meta.append("MOV A,A")
    return out


def gen(seed, main_len=150, limit=None):
    rng = random.Random(seed)
    mem = [0] * 0x2000
    meta = []

    # Entry: bootstrap RST 0 lands at 0 -> JMP MAIN
    mem[0:3] = [0x44, MAIN_BASE & 0xFF, MAIN_BASE >> 8]
    # RST vectors 1..7: RET
    for v in range(1, 8):
        mem[v * 8] = 0x07

    # Leaf subroutine pool
    subs = []
    addr = SUB_BASE
    for si in range(4):
        subs.append(addr)
        body, smeta = [], []
        for _ in range(rng.randrange(2, 6)):
            _safe_instr(rng, body, smeta, allow_rcc=True)
        body.append(0x07)  # RET
        smeta.append("RET")
        mem[addr:addr + len(body)] = body
        meta.append(f"; sub{si} @ {addr:#06x}: " + " | ".join(smeta))
        addr += len(body)
        assert addr < MAIN_BASE, "subroutine pool overflowed into main"

    # Main body: two passes (generate with jump placeholders, then patch
    # targets to future instruction boundaries)
    instrs = []          # list of (bytes, kind, meta_lines) per instruction
    n = main_len if limit is None else min(limit, main_len)
    for _ in range(n):
        c = rng.randrange(100)
        if c < 70:
            out, m = [], []
            _safe_instr(rng, out, m, allow_rcc=False)
            instrs.append((out, "safe", m))
        elif c < 82:                                  # JMP / JFc / JTc forward
            cc = rng.randrange(4)
            op = rng.choice([0x44,
                             0x40 | cc << 3,
                             0x60 | cc << 3])
            instrs.append(([op, 0, 0], "jump", [f"J.. {op:#04x} -> ?"]))
        elif c < 92:                                  # CAL / CFc / CTc to sub
            cc = rng.randrange(4)
            op = rng.choice([0x46,
                             0x42 | cc << 3,
                             0x62 | cc << 3])
            tgt = rng.choice(subs)
            instrs.append(([op, tgt & 0xFF, tgt >> 8], "call",
                           [f"C.. {op:#04x} -> {tgt:#06x}"]))
        else:                                         # RST 1..7
            a = rng.randrange(1, 8)
            instrs.append(([0x05 | a << 3], "rst", [f"RST {a}"]))
    instrs.append(([0xFF], "hlt", ["HLT"]))

    # Assign addresses
    addrs, a = [], MAIN_BASE
    for by, _, _ in instrs:
        addrs.append(a)
        a += len(by)
    assert a <= 0x2000, "main body overflowed ROM"
    hlt_addr = addrs[-1]

    # Patch forward jump targets
    for i, (by, kind, m) in enumerate(instrs):
        if kind == "jump":
            future = addrs[i + 1:]
            tgt = rng.choice(future) if future else hlt_addr
            if limit is not None and tgt > hlt_addr:
                tgt = hlt_addr
            by[1], by[2] = tgt & 0xFF, tgt >> 8
            m[0] = m[0].replace("?", f"{tgt:#06x}")

    for (by, _, m), ad in zip(instrs, addrs):
        mem[ad:ad + len(by)] = by
        for line in m:
            meta.append(f"{ad:#06x}: " + line)

    return mem, meta


if __name__ == "__main__":
    import sys
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    mem, meta = gen(seed)
    print("\n".join(meta))
