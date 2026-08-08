# b8008 External Bus Protocol

**Status:** active. Pin-level contract of the 8008 bus, derived from the spec sources ranked in `docs/SPEC.md` §2. Every claim cites its `docs/VPLAN.md` row; the cocotb bus-protocol monitor (`sim/cocotb/test_b8008_top.py`, in CI) asserts these tables.

**Implementation mapping note:** the b8008 CORE entity diverges from the physical 8008 pinout in two synthesis-driven ways: φ1/φ2 are OUTPUTS (generated internally by phase_clocks from clk_in, not fed in), and the bidirectional D bus is split into data_bus_in / data_bus_out / data_bus_oe (FPGA tri-state modeling). The PROTOCOL below — what appears when, per T-state — is unchanged by either.

**T4/T5 divergence (VPLAN BUS-06, CLOSED-AS-CONSTRAINT):** the PMOS 8008 leaks internal data-bus values onto the external bus at T4/T5 (UM p.48 n.3 marks them internal-use). b8008 does not reproduce the leak: data_bus_oe drives the bus only at T1/T2, write T3, and INP T4 (the flag output, which IS contract). No external device may rely on T4/T5 bus content on either implementation.

## 1. Signals

| Signal | Dir | Width | Role |
|--------|-----|-------|------|
| D7..D0 | bidir | 8 | time-multiplexed address/status/data bus |
| S0,S1,S2 | out | 3 | processor state code (§2) |
| SYNC | out | 1 | φ2÷2; one full cycle per T-state (CLK-04) |
| READY | in | 1 | memory/IO ready; sampled per §5 |
| INT | in | 1 | interrupt request; recognized per §6 |
| φ1, φ2 | in | 2 | non-overlapping two-phase clock (CLK-01); each T-state = 2 clock periods (CLK-03) |

## 2. State codes (VPLAN ST-01)

| State | S0 S1 S2 |
|-------|---------|
| T1 | 0 1 0 |
| T1I | 0 1 1 |
| T2 | 0 0 1 |
| WAIT | 0 0 0 |
| T3 | 1 0 0 |
| STOPPED | 1 1 0 |
| T4 | 1 1 1 |
| T5 | 1 0 1 |

No other code is ever driven. Monitor assertion: at every SYNC-qualified sample, S decodes to one of these 8.

## 3. Bus contents per T-state (VPLAN BUS-01..06)

| T-state | D7..D0 carry | Notes |
|---------|--------------|-------|
| T1 / T1I | lower 8 address bits | PC-low for PCI/operand-fetch cycles; REG.L for H:L cycles (BUS-10/11) |
| T2 | D5..D0 = upper 6 address bits; D7,D6 = cycle code (§4) | cycle code appears ONLY here (BUS-04) |
| WAIT | bus floats | CPU output buffers disabled (BUS-09) |
| T3 | read cycles: data INTO CPU; PCW: data OUT of CPU | fetch/data/write (BUS-05) |
| STOPPED | bus floats | (BUS-09) |
| T4, T5 | internal-bus value observable (testability) | per micro-op tables (BUS-06); INP drives flags at T4: S→D0, Z→D1, P→D2, C→D3 (FLG-13) |

**SQ-07 RULED (pre-carry):** the T2 high byte is the CURRENT fetch's page; the pending carry lands at T2 second half (SPEC §6). The monitor asserts T2 = current fetch page.

## 4. Cycle types (VPLAN BUS-03, BUS-07, BUS-08)

| Code (D6, D7 at T2) | Type | Meaning |
|--------------------|------|---------|
| 0 0 | PCI | instruction fetch (always cycle 1) |
| 0 1 | PCR | read: operand byte or mem[H:L] |
| 1 0 | PCC | I/O command cycle (INP/OUT cycle 2) |
| 1 1 | PCW | memory write |

Cycle sequences per class: PCI-only = {MOVrr, INR, DCR, ALUr, rotates, RET, Rcond, RST, HLT}; PCI+PCR = {MOVrM, MVIr, ALUM, ALUI}; PCI+PCW = {MOVMr}; PCI+PCR+PCW = {MVIM}; PCI+PCR+PCR = {JMP/Jcond/CAL/Ccond}; PCI+PCC = {INP, OUT}.

## 5. READY (VPLAN §D)

- Sampled at T2 (and in WAIT) of **every** cycle type; not-ready → WAIT; WAIT holds while low; high → T3 (ST-03/04, RDY-02).
- READY tied high ⇒ code 000 never appears (RDY-01).
- OUT's PCC cycle requires READY to complete (RDY-04).
- Monitor assertions: WAIT entered iff READY low at T2; post-WAIT resume produces same T3 as an un-waited cycle; bus floating during WAIT.

## 6. Interrupt acknowledge (VPLAN §E)

- INT high → next instruction-fetch cycle opens with T1I (code 011) instead of T1; never mid-instruction (INT-01, ST-09).
- T1I cycle drives the SAME address as the following (or preceding) fetch — PC not incremented (INT-02). Monitor: address at T1I-cycle T1/T2 equals the address of the next PCI cycle's T1/T2.
- The byte presented at T3 of the T1I cycle is jammed into IR (INT-03); multi-cycle jams: only cycle 1 is T1I (INT-04).
- One T1I per INT pulse if INT drops before next PCI (INT-07).

## 7. Instruction-boundary observables (monitor cross-checks)

- Cycle 1 is always PCI (BUS-07); cycles 2/3 never PCI.
- T4/T5 skipped exactly per the exit map (ST-10); monitor may count states per instruction and diff against `docs/isa.json` (the check_cycle_count idiom, ST-11) — including correlating conditional taken/not-taken with 11-vs-9 / 5-vs-3 (closes ST-11 ⚠).

## 8. Cross-reference

Closing this document's assertions in a cocotb monitor closes VPLAN rows: BUS-01, BUS-02, BUS-03 (external half), BUS-04, BUS-06, BUS-09 (system half), FLG-13 (bus half), INT-02, plus the ST-11 taken/not-taken residual. See VPLAN Phase 5 Tier-1 #4.
