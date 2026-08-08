# b8008 Architecture Specification (SPEC.md)

**Status:** ratified — binds existing normative sources; all 15 SPEC-QUESTIONs decided (§6).
**Scope:** the programmer-visible contract of the b8008 core. Internals belong to the MAS (`docs/MAS.md`); testable enumeration of every claim here lives in `docs/VPLAN.md`.

## 1. Identity

b8008 is a cycle-accurate, block-based VHDL implementation of the Intel 8008 (1972). "Cycle-accurate" means: T-state sequences, machine-cycle structure, and state counts per instruction match the Intel documentation at the granularity of §3 — not transistor-level or analog timing.

## 2. Normative source hierarchy

Conflicts resolve top-down; any discovered conflict becomes a SPEC-QUESTION in VPLAN §SQ, never silently resolved.

1. `docs/8008_1972.pdf` (Intel datasheet, 1972) and `docs/8008UM.pdf` (MCS-8 User's Manual) — joint primary authority.
2. `docs/isa.json` — machine-readable per-instruction T-state/cycle oracle, used directly by `check_cycle_count_test.sh`. Known divergences from the PDFs are logged as SQ-01/SQ-02/SQ-14 and must be fixed in isa.json, not worked around.
3. `docs/VPLAN.md` — the row-level enumeration (102 rows). Where prose here is compressed, the VPLAN row is the precise statement.

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
- **READY/WAIT:** READY sampled at T2 of every cycle; not-ready parks in WAIT losslessly (system-verified by the READY stress test). Single-stepping by READY pulse verified end-to-end: whole programs stepped one machine cycle per pulse with checkpoints identical to free runs (VPLAN RDY-03/RDY-04/XP-15, `check_ready_step_test.sh`).
- **HLT/STOPPED:** three encodings; STOPPED exits only via interrupt (ST-05/06, I-HLT-01).

## 5. Explicit non-goals

- Dynamic-memory refresh (Intel PMOS implementation detail; architecturally invisible — VPLAN pruning log).
- Analog/DC electrical characteristics; absolute microsecond timing (sim runs scaled clocks; ratios and non-overlap are kept — CLK-01/02).
- 8008-1 speed grade distinction.
- T4/T5 internal-bus leakage onto the external bus (PMOS artifact, marked internal-use by the UM; b8008 floats the bus there — VPLAN BUS-06 ruling).

## 6. Ratified decisions (2026-08-08)

Ruling principle: most accurate to the Intel documentation, and the 8008
stays working. All 15 SPEC-QUESTIONs are decided:

| SQ | Ruling |
|----|--------|
| SQ-01 | isa.json fixed: JFc `010CC000` / JTc `011CC000` per DS72 p.36 (D5 = true/false sense bit; the C/R families already carried it) |
| SQ-02 | isa.json gains `num_states_not_taken` (9 for J/C conditionals, 3 for R) per DS72 p.45 "(9 or 11)" / "(3 or 5)"; `check_cycle_count_test.sh` now sources the pair from the oracle instead of hardcoding it |
| SQ-03 | HLT "4 states" = 3 driven states + STOPPED entry; the CPU "internally remains in T3" (DS72 p.41 n.18) — no externally observable 4th state exists |
| SQ-04 | A commits at T5 per the micro-op table (T3→Reg.b, T5→A). The p.37 prose "loaded at T3" describes bus-data arrival; the table is the cycle-accurate normative layer |
| SQ-05 | INP does not modify flags — DS72 p.37 only *outputs* S,Z,P,C on D0-D3 at T4 |
| SQ-06 | Stack overflow destroys the oldest return context, SP-relative (stackwrap_test and rst_wrap_test landing predictions confirm) |
| SQ-07 | Page-cross T2 high byte is pre-carry: it is the CURRENT fetch's page; the pending carry belongs to the next address and lands at T2 second half (DS72 order: address out, then increment). No wrong-page artifact exists |
| SQ-08 | WAIT/STOPPED persist in whole T-state (2-clock) units per visit |
| SQ-09 | Late READY deassert (after the φ22 sample) is an environment setup constraint; the CPU acts on the sampled value, late changes take effect at the next sample |
| SQ-10 | Logicals clear carry in ALL forms (r/M/I) — DS72 p.34's Accumulator Group header governs the whole group; exhaustively verified for r-form by alu_exhaustive_tb |
| SQ-11 | Multi-cycle jam: only cycle 1 is T1I, remaining cycles are normal (verified by check_jam_test.sh) |
| SQ-12 | 0x38/0x39 (would-be INR/DCR M) are excluded from every DS72 definition; the only derivable constraint is "memory may not be written". b8008's implementation-defined behavior, characterized and pinned by `check_undef_opcode_test.sh`: one PCI cycle, no memory write, no register write, flags update as INR/DCR of a dummy zero operand (0x38 → Z=0 S=0 P=0; 0x39 → Z=0 S=1 P=1), carry preserved |
| SQ-13 | DS72 p.37 prints the restart mnemonic as "RET 00 AAA 101" — typo for RES/RST; citation note only |
| SQ-14 | isa.json CAL/CFc/CTc cycle-3 T4 now carries the PUSH annotation (UM p.49 n.12) |
| SQ-15 | Dissolved: the architectural power-on contract (power up STOPPED, execute nothing until INT, machine-chosen jam byte starts execution) is already met by reset→STOPPED→bootstrap-jam; Intel's internal HLT-in-IR/16-clock mechanism is unobservable and not reproduced |
