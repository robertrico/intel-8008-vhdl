# b8008 Architecture Specification (SPEC.md)

**Status:** draft — binds existing normative sources; 15 open decisions pending (§6).
**Scope:** the programmer-visible contract of the b8008 core. Internals belong to the MAS (`docs/MAS.md`); testable enumeration of every claim here lives in `docs/VPLAN.md`.

## 1. Identity

b8008 is a cycle-accurate, block-based VHDL implementation of the Intel 8008 (1972). "Cycle-accurate" means: T-state sequences, machine-cycle structure, and state counts per instruction match the Intel documentation at the granularity of §3 — not transistor-level or analog timing.

## 2. Normative source hierarchy

Conflicts resolve top-down; any discovered conflict becomes a SPEC-QUESTION in VPLAN §SQ, never silently resolved.

1. `docs/8008_1972.pdf` (Intel datasheet, 1972) and `docs/8008UM.pdf` (MCS-8 User's Manual) — joint primary authority.
2. `docs/isa.json` — machine-readable per-instruction T-state/cycle oracle, used directly by `check_cycle_count_test.sh`. Known divergences from the PDFs are logged as SQ-01/SQ-02/SQ-14 and must be fixed in isa.json, not worked around.
3. `docs/VPLAN.md` — the row-level enumeration (97 rows). Where prose here is compressed, the VPLAN row is the precise statement.

## 3. Programmer-visible state

| State | Width | Notes |
|-------|-------|-------|
| A, B, C, D, E, H, L | 7 × 8-bit | scratchpad; A is the ALU accumulator |
| Address stack | 8 × 14-bit | one slot IS the PC, selected by SP (VPLAN STK-01) |
| SP | 3-bit | wraps mod 8 both directions (STK-02) |
| Flags C, Z, S, P | 4 × 1-bit | definitions per VPLAN FLG-02..05; parity = EVEN |

No other state is architecturally visible. Temp registers a/b and the machine-cycle bookkeeping are microarchitecture (MAS).

## 4. Contract summary (per area → VPLAN rows)

- **Instruction set:** 48 instructions, encodings and semantics per VPLAN §J and §K; all 256 opcodes decode to a defined instruction or documented alias (DC-05). Don't-care fields (JMP/CAL/RET XXX, B3[7:6]) are behavior-identical (DC-01..03).
- **Timing:** state counts per class per ST-11 (conditional split 9/11 and 3/5); machine-cycle types per BUS-08; first cycle always PCI (BUS-07).
- **Bus protocol:** per-T-state bus contents per VPLAN §C — T1 low address, T2 high address + D6/D7 cycle code, T3 data; bus floats in WAIT/STOPPED (BUS-09). This is a hard contract: external memory/IO controllers are built against it.
- **Flags:** update masks are load-bearing spec (escaped twice historically — VPLAN S2/S3): loads touch nothing (FLG-06), INR/DCR spare carry (FLG-07), rotates touch only carry (FLG-10), logicals clear carry (FLG-09), CMP writes flags not A (FLG-11).
- **Stack:** CALL/RET move SP, slots retain values; 7-level nesting guaranteed; 8th call wraps onto oldest (STK-03..06). Pushed value = address of the instruction after the CALL/RST (STK-09).
- **Interrupts:** recognized only at instruction boundaries; acknowledge cycle is T1I with PC not incremented; the T3 byte of that cycle is jammed into IR; multi-cycle jams continue as normal cycles (VPLAN §E). No automatic state save.
- **READY/WAIT:** READY sampled at T2 of every cycle; not-ready parks in WAIT losslessly; single-stepping by READY pulse is supported behavior (VPLAN §D).
- **HLT/STOPPED:** three encodings; STOPPED exits only via interrupt (ST-05/06, I-HLT-01).

## 5. Explicit non-goals

- Dynamic-memory refresh (Intel PMOS implementation detail; architecturally invisible — VPLAN pruning log).
- Analog/DC electrical characteristics; absolute microsecond timing (sim runs scaled clocks; ratios and non-overlap are kept — CLK-01/02).
- 8008-1 speed grade distinction.

## 6. Open decisions (blocking full ratification)

The 15 SPEC-QUESTIONs in `docs/VPLAN.md` §SPEC-QUESTIONS. Load-bearing subset:

| SQ | Decision needed | Default proposed |
|----|-----------------|------------------|
| SQ-15 | Model the 8008 power-on protocol (HLT forced into IR, 16-clock clear, INT to start) or accept explicit reset as a divergence? | accept explicit reset; document divergence here in §5 |
| SQ-04 | Which T-state architecturally updates A during INP (T3 text vs T5 table)? | T5 (micro-op table), matching temp-reg b path |
| SQ-05 | Does INP modify flags? | no — flags only driven onto bus at T4 |
| SQ-07 | Page-cross: is same-cycle T2 high-byte pre-carry (visible artifact) or post-carry? | needs waveform-level ruling before bus monitor is written |
| SQ-06 | Stack overflow "lowest level register" = oldest (relative) or slot 0 (absolute)? | oldest (current stackwrap_test reading) |
| SQ-12 | Decode of 00 111 000 / 00 111 001 (would-be INR/DCR M)? | document actual decoder behavior as the defined alias |

Answering an SQ = editing this file + flipping the VPLAN row from SPEC-QUESTION to decided; the diff is the ratification record.
