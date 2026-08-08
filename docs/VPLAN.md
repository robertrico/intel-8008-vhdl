# b8008 Retroactive Verification Plan (vplan) Audit

**Date:** 2026-08-08. **Method:** Phase 1 derived every row from the specifications only — `docs/8008_1972.pdf` (DS72, printed page numbers), `docs/8008UM.pdf` (UM), `docs/isa.json` (ISA) — with no RTL read. Phase 3 then mapped rows onto existing verification collateral (`sim/`, `formal/`, `test_programs/verification_scripts/`, `sim/cocotb/`, `.github/workflows/verification.yml`). A row is only COVERED if some existing artifact would **fail** were the behavior wrong.

**Status legend:**
- `COVERED-FORMAL` — SBY property (cite suite)
- `COVERED-EXHAUSTIVE` — full-space sweep (cite sweep)
- `COVERED-DIRECTED` — directed self-checking test (cite)
- `COVERED-INCIDENTAL` — only exercised as a side effect; would not necessarily fail
- `GAP` — no failing check exists
- A ⚠ note marks residual holes inside a COVERED row; residuals feed the gap report.

Spec ambiguities were SPEC-QUESTION rows (§ SQ); all 15 are RATIFIED as of 2026-08-08 — rulings live in `docs/SPEC.md` §6, the table below is kept as the question record.

---

## Phase 1+3 — Row table

### A. Clock & SYNC

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| CLK-01 | DS72 p.16 waveform | φ1 and φ2 never simultaneously high at any sim time | continuous | directed | `sim/units/phase_clocks_tb` (1000-iteration non-overlap loop); `b8008_tb` phi-overlap sanity error | COVERED-DIRECTED ⚠ phase_clocks_tb has stale 5-port component decl (entity now 11 ports) |
| CLK-02 | DS72 p.16 §VI A.C. | Clock ratios (tφ1, tφ2, tD1, tD2 relative to tCY) match datasheet table (scaled) | phase_clocks | — | none — TB checks SYNC cadence, not φ pulse-width/delay ratios | GAP |
| CLK-03 | DS72 p.10 Fig4; UM p.47 | Every T-state lasts exactly 2 clock periods (φ11 φ21 φ12 φ22) | all states | formal (module) | `formal/state_timing_generator.sby` state_half toggle assertion | COVERED-FORMAL ⚠ module-level; no core-level check that states advance once per 2 clocks |
| CLK-04 | DS72 p.4 Fig1; UM p.47 | SYNC = φ2 ÷ 2; one full SYNC cycle per T-state | continuous | directed | `sim/units/phase_clocks_tb` SYNC cadence checks | COVERED-DIRECTED |

### B. State machine & encodings

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| ST-01 | DS72 p.4 §II.A; UM p.4 | S0S1S2 = T1:010 T1I:011 T2:001 WAIT:000 T3:100 STOPPED:110 T4:111 T5:101; no other code driven | every state | formal | `formal/state_timing_generator.sby` — all 8 datasheet status encodings + one-hot-or-zero P2 (k-induction proven) | COVERED-FORMAL |
| ST-02 | DS72 p.5 Fig2 | T1/T1I always → T2 | — | formal | `state_timing_generator.sby` FSM-arc assertions | COVERED-FORMAL |
| ST-03 | DS72 p.5 Fig2 | T2 → T3 iff READY; T2 → WAIT iff not READY | both branches | formal | `state_timing_generator.sby` T2±READY arcs | COVERED-FORMAL |
| ST-04 | DS72 p.5 Fig2 | WAIT holds while READY=0; WAIT → T3 on READY=1 | multi-state waits | formal + directed | `state_timing_generator.sby` READY/WAIT park+resume; `state_timing_generator_tb` | COVERED-FORMAL |
| ST-05 | DS72 p.5 Fig2 | T3 → STOPPED when HLT fetched | 3 HLT encodings | formal (module) | `state_timing_generator.sby` HLT→STOPPED arc; `state_timing_generator_tb` | COVERED-FORMAL ⚠ system-level "did the CPU actually stop" unchecked — see I-HLT-01 |
| ST-06 | DS72 p.5 Fig2 | STOPPED holds while INT=0; → T1I on INT=1 | — | formal + directed | `state_timing_generator.sby` STOPPED-wake arc; `check_interrupt_test.sh` HLT-wake checkpoint | COVERED-FORMAL |
| ST-07 | DS72 p.5, Fig2 | Cycles not needing T4/T5: T3 → next T1; T4/T5 codes never appear | per ST-10 map | directed | `check_cycle_count_test.sh` (state counts imply skips) | COVERED-DIRECTED |
| ST-08 | DS72 p.5 Fig2 | T3 → T4 → T5 when needed; LMr cycle 1 ends at T4 | — | formal + directed | `state_timing_generator.sby` priority chains; cycle counts (MOVMr=7) | COVERED-FORMAL |
| ST-09 | DS72 p.5 Fig2; UM p.10 | Instr end → T1, or T1I iff INT pending; interrupt never recognized mid-instruction (incl. between cycles of one instr) | INT at boundary vs mid | formal (module) + directed | `state_timing_generator.sby` "T5 boundary-only interrupt"; `state_timing_generator_tb` mid-instruction counter-case; `check_interrupt_test.sh` loop-integrity C=0x30 | COVERED-FORMAL ⚠ core-level composition unproven (module assume chain) |
| ST-10 | DS72 p.39 Fig16; UM p.50 Fig20 | Cycle-exit map (which cycles end after T3/T4/T5, per class incl. failed-condition exits) | each arc | directed | `check_cycle_count_test.sh` per-class T-state diff vs isa.json; `formal/machine_cycle_control.sby` next-cycle contract (BMC-50) | COVERED-DIRECTED |
| ST-11 | DS72 p.45; UM p.59; ISA | Min state counts: MOVrr 5, MOVrM 8, MOVMr 7, MVIr 8, MVIM 9, INR/DCR 5, ALUr 5, ALUM/ALUI 8, rot 5, JMP 11, Jcond 9/11, CAL 11, Ccond 9/11, RET 5, Rcond 3/5, RST 5, INP 8, OUT 6, HLT 4 | READY high | directed | `check_cycle_count_test.sh` — Python parser diffs measured T-states vs isa.json per class | COVERED-DIRECTED ⚠ conditionals accepted as {9,11}/{3,5} *sets* — script does not correlate which count paired with taken vs not-taken |
| ST-12 | DS72 p.5; UM p.5 | WAIT/STOPPED persistence = even number of clock periods ("2n") | — | by construction | SQ-08 ratified: whole-T-state quantization per visit; the state machine holds parked states in 2-clock units structurally (`state_timing_generator.sby` state_half assertion) | COVERED-FORMAL |

### C. Bus & cycle codes

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| BUS-01 | DS72 p.4 Fig1 | T1: D7..D0 = lower 8 address bits | every cycle | — | none — no artifact compares external-bus bytes per T-state | GAP |
| BUS-02 | DS72 p.4 Fig1, p.5 | T2: D5..D0 = upper 6 addr bits, D6/D7 = cycle code | every cycle | — | none | GAP |
| BUS-03 | UM p.5 §II.C | Cycle codes: PCI D6=0,D7=0; PCR D6=0,D7=1; PCC D6=1,D7=0; PCW D6=1,D7=1 | each type | formal (internal) | `formal/machine_cycle_control.sby` cycle_type latch rules | COVERED-FORMAL ⚠ internal cycle_type only; D6/D7 encoding on external bus unchecked (b8008_top_tb asserts one WAIT-status observation only) |
| BUS-04 | DS72 p.5 §II.C | Cycle code on D6/D7 only during T2 | other states | — | none | GAP |
| BUS-05 | DS72 p.4 Fig1 | T3 bus = fetched byte (reads) / CPU-driven data (PCW) | per type | incidental | programs execute + RAM writes land (all check_*.sh) — a wrong T3 path would break everything | COVERED-INCIDENTAL (functionally implied, no direct bus check) |
| BUS-06 | DS72 p.40 n.2-3; UM p.48 n.3 | Internal data-bus value observable on external bus at T4/T5 per micro-op tables | whitebox | — | none | GAP |
| BUS-07 | DS72 p.5 §II.C | Cycle 1 always PCI; cycles 2/3 ∈ {PCR,PCW,PCC} | every instr | formal (internal) | `machine_cycle_control.sby` latch rules + advance contract | COVERED-FORMAL ⚠ same external-bus caveat as BUS-03 |
| BUS-08 | DS72 p.40-41 | Cycle-type sequence per class (PCI-only / PCI+PCR / PCI+PCW / PCI+PCR+PCW / PCI+PCR+PCR / PCI+PCC) | each class | directed | `check_cycle_count_test.sh` MCycle: parsing per class | COVERED-DIRECTED |
| BUS-09 | DS72 p.13; UM p.13 | Data bus floats during WAIT and STOPPED | — | directed (module) | `io_buffer_tb` ZZ checks | COVERED-DIRECTED ⚠ module only; no system-level check that CPU tri-states in WAIT/STOPPED |
| BUS-10 | DS72 p.7; UM p.49 | H:L cycles drive L at T1, H[5:0] at T2; H[7:6] masked from address | incl. H[7:6]=11 | incidental | mov_mem/mvi_m/memory_alu tests read/write correct locations (address must be H:L) | COVERED-DIRECTED (`check_hl_mask_test.sh` quadrant aliasing) |
| BUS-11 | UM p.49 | Immediate/operand cycles address the PC (T1=PCL, T2=PCH) | MVI/ALUI/J/C cyc 2-3 | incidental | immediates land in right registers in all tests | COVERED-INCIDENTAL |

### D. READY / WAIT

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| RDY-01 | UM p.12 §V.B | READY tied high → WAIT (000) never appears | any program | — | none (all sim runs hold READY high, but nothing asserts WAIT absence) | GAP (trivially true in practice, unchecked) |
| RDY-02 | DS72 p.5 Fig2 | Not-ready at T2 of any cycle type → WAIT; post-resume arch state identical to no-wait run | ×{PCI, PCR-imm, PCR-H:L, PCW, PCC-INP, PCC-OUT} | formal (module) + directed (system) | `state_timing_generator.sby` park+resume; `check_ready_wait_test.sh` — hundreds of varied READY drops + long park over memory_alu_test (all cycle types), checkpoints diffed against the free run | COVERED-DIRECTED |
| RDY-03 | DS72 p.12 §V.B | READY pulsing single-steps one machine cycle per pulse | multi-cycle program | — | none (`debug_clock_control_tb` steps clocks, not READY) | GAP |
| RDY-04 | UM p.49 n.17 | OUT PCC cycle requires READY; READY=0 → OUT stalls | OUT | — | none | GAP |
| RDY-05 | DS72 p.16 tRW | READY sampled at φ22 of T2/WAIT | stimulus constraint | — | SQ-09 ratified: environment setup constraint, not CPU behavior; late deassert takes effect at the next sample (board 2-FF-syncs READY) | CLOSED-AS-CONSTRAINT |

### E. Interrupt

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| INT-01 | UM p.10 §V.A.1 | INT=1 → next instruction fetch runs T1I (011) in place of T1 | INT during any prior T-state | formal (module) + directed | `state_timing_generator.sby` boundary-only arcs; `check_interrupt_test.sh` (4 runtime RST7 jams serviced) | COVERED-DIRECTED |
| INT-02 | UM p.10-11 | T1I: PC driven, NOT incremented → same address emitted twice | — | incidental | interrupt_test loop integrity implies resumed PC correct | COVERED-INCIDENTAL ⚠ no check observes the double-address emission or the un-incremented PC directly |
| INT-03 | UM p.10 | Byte on bus at T3 of T1I cycle enters IR and executes | any opcode | directed | `check_interrupt_test.sh` (RST); `check_jam_test.sh` (NOP, HLT, 3-byte JMP via int_jam_byte override) | COVERED-DIRECTED |
| INT-04 | DS72 p.10 | Multi-cycle/multi-byte jam: only first cycle is T1I, rest normal | jam 3-byte instr | directed | `check_jam_test.sh` S3 — 3-byte JMP jammed (TB supplies B2/B3 as interrupt controller), landing checkpointed, exactly one T1I asserted | COVERED-DIRECTED |
| INT-05 | UM p.10 | Jam HLT → STOPPED; jam NOP → sequential at un-advanced PC; jam JMP → run from target | 3 scenarios | directed | `check_jam_test.sh` — NOP jam (loop count exact), HLT jam (STOPPED persists, RST7 wake resumes exactly), jammed JMP (landing pad checkpoint) | COVERED-DIRECTED |
| INT-06 | UM p.11 Fig5 | Jam RST at PC=N: N pushed; RET resumes at N; instr at N executes exactly once | — | directed | `check_interrupt_test.sh` C=0x30 loop-count integrity despite 3 mid-loop interrupts | COVERED-DIRECTED |
| INT-07 | DS72 p.10 Fig4 | One T1I per INT pulse (deasserted before next PCI) | — | formal (module) + directed | `int_button_tb` no-spurious-request; `formal/interrupt_ready_ff` clear-beats-set/set/hold by k-induction; `interrupt_ready_ff_tb` | COVERED-FORMAL ⚠ module-level; system-level double-service unchecked |
| INT-08 | DS72 p.5 Fig2 | STOPPED + INT → T1I exit | — | formal + directed | `state_timing_generator.sby`; interrupt_test HLT-wake | COVERED-FORMAL |

### F. Power-on

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| PWR-01 | UM p.11 §V.A.2 | Power-on: STOPPED, nothing executes until INT | — | by design + directed | SQ-15 ratified: architectural contract met (reset→STOPPED→bootstrap jam; any jam byte works per check_jam_test.sh); internal HLT-in-IR mechanism unobservable, not reproduced | COVERED-DIRECTED |
| PWR-02 | UM p.11 | 16 clocks after STOPPED entry: A, scratchpad, PC, stack = 0 | — | formal (partial) | reset-clears-state assertions exist per module (`register_file.sby`, `condition_flags.sby`, `stack_pointer.sby` P1) | COVERED-FORMAL ⚠ covers reset-clears, not the 16-clock power-on protocol itself |
| PWR-03 | UM p.11-12 Ex.1 | INT exits power-on STOPPED via T1I; first fetch addr 0; addr 0 emitted twice (no advance) | — | incidental | interrupt_test RST0 bootstrap starts CPU this way | COVERED-INCIDENTAL ⚠ double-emission of addr 0 never asserted |

### G. Stack / SP / PC

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| STK-01 | UM p.7 §III.B.1 | Stack = 8×14-bit; PC = slot[SP] | — | formal | `formal/stack_memory.sby` slot-isolation orbit + `stack_memory_tb` all-8-slot isolation | COVERED-FORMAL |
| STK-02 | UM p.7 | SP wraps mod 8 both directions | push 7→0, pop 0→7 | formal | `stack_pointer.sby` P2/P3 (k-induction) + wrap covers; `stack_pointer_tb`; cocotb random walk | COVERED-FORMAL |
| STK-03 | UM p.7 | CALL: SP advances; old slot retains return address | — | formal + directed | `stack_memory.sby` CALL/RET slot preservation; `check_stack_depth_test.sh` | COVERED-FORMAL |
| STK-04 | UM p.7 | RET: SP retreats; PC = stored addr; LIFO | nesting | directed | `check_stack_depth_test.sh` (7 nested CALL/RET) | COVERED-DIRECTED |
| STK-05 | DS72 p.36; UM p.45 | 7 nested CALLs + 7 RETs all return correctly | depth 7 | directed | `check_stack_depth_test.sh` (7 levels, per-level checkpoints) | COVERED-DIRECTED |
| STK-06 | UM p.7 | 8th nested CALL: SP recycles, oldest return destroyed, newer 7 intact, no trap | — | directed | `check_stackwrap_test.sh` (8th CALL overwrites oldest; includes negative assertion `assert_checkpoint_absent 3`) | COVERED-DIRECTED (also SQ-06) |
| STK-07 | UM p.3, p.7 | 14-bit PC/address space; PC increment wraps 0x3FFF→0 | wrap | directed | `check_pc_wrap_test.sh` — NOPs planted at 0x3FFC-0x3FFF (RAM), sequential fetch wraps to the reset vector, sentinel-routed checkpoint | COVERED-DIRECTED |
| STK-08 | UM p.7; DS72 p.7 | PC low incremented after T1; high driven at T2 then carry applied | page cross | formal + directed | `stack_memory.sby` lower/upper-increment carry semantics; `stack_memory_tb` 0x01FF→0x0200; `check_pc_carry_call_test.sh` (CALL at 0x00FC → return 0x0100) | COVERED-DIRECTED (T2-visible-value artifact is SQ-07) |
| STK-09 | DS72 p.36; UM p.45-46 | Pushed value = addr after CAL (3 bytes) / after RST (1 byte) | — | directed | `check_pc_carry_call_test.sh` KEY TEST; `check_rst_test.sh` / `check_rst_full_test.sh` (RET resumes correctly) | COVERED-DIRECTED |

### H. Registers & operands

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| REG-01 | UM p.3, p.7 | 7 independent 8-bit registers; write one, others unchanged | pairwise | formal | `register_file.sby` per-register write ×7 + hold ×7 (k-induction) + fully-proven `register_file_miter` | COVERED-FORMAL |
| REG-02 | UM p.9 n.1 | SSS/DDD encodings A..L, 111=M | all codes | exhaustive | `sss_ddd_selector_tb` exhaustive sweeps; cocotb decoder sweep (256 opcodes vs independent Python model) | COVERED-EXHAUSTIVE |
| REG-03 | UM p.7, p.9 n.2 | M address = {H[5:0], L}; changing H/L redirects next access | — | directed | `check_mov_mem_test.sh` self-modifying H/L pointer cases; `check_hl_mask_test.sh` | COVERED-DIRECTED |
| REG-04 | UM p.7 §III.C | Temp a/b invisible; no partial arch-state mid-instruction | whitebox | formal (module) + directed | `formal/temp_registers` load/hold/mux by k-induction + miter; `temp_registers_tb`; `register_alu_control_tb` negative checks (load_reg_a NOT asserted at wrong cycles) | COVERED-DIRECTED |

### I. Flags

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| FLG-01 | UM p.7 §III.C | Exactly C, Z, S, P flip-flops | — | formal | `condition_flags.sby` (k-induction, full suite) | COVERED-FORMAL |
| FLG-02..05 | UM p.42 App I | C = carry/borrow; Z = result==0; S = bit7; P = even parity | all ops | exhaustive | `alu_exhaustive_tb`: 656,384 cases vs independent numeric_std reference — result + all 4 flags | COVERED-EXHAUSTIVE (all 8 ops: logical ops swept 256x256 x carry both ways, carry-clear enforced per case) |
| FLG-06 | DS72 p.45; UM p.59 | Loads change no flag | all 4 flags | directed | `check_flag_test.sh` load-storm rounds: dirty flag states in both polarities survive a MOV/MVI barrage | COVERED-DIRECTED |
| FLG-07 | DS72 p.34; UM p.43 | INR/DCR: Z,S,P update, C unchanged | C=0 and C=1 | exhaustive + directed | `alu_exhaustive_tb` INR/DCR×256×2 carry; `check_inr_carry_test.sh` (SCELBAL regression); `alu_tb` carry-preservation | COVERED-EXHAUSTIVE |
| FLG-08 | UM p.43, p.59 | Every ALU op updates all 4 flags from result | 8 ops × 3 forms | exhaustive (arith) + directed (logical, M/I forms) | `alu_exhaustive_tb`; `check_alu_test.sh`, `check_flag_test.sh`, `check_memory_alu_test.sh` | COVERED-DIRECTED ⚠ logical-op flag space only spot-checked |
| FLG-09 | DS72 p.34; UM p.43 | ANA/XRA/ORA force C=0 | all forms | directed | `alu_tb`; `check_flag_test.sh` | COVERED-DIRECTED ⚠ M/I-form carry-clear spot-checked only (SQ-10) |
| FLG-10 | DS72 p.36; UM p.45 | Rotates change only C | — | directed | `check_rotate_flags_test.sh` (rotates update Carry ONLY); `condition_flags.sby` carry_only property | COVERED-FORMAL |
| FLG-11 | UM p.44, p.59 | CMP: flags from A−op, A unchanged, C=1 iff A<op | polarity | exhaustive + directed | `alu_exhaustive_tb` (CMP in sweep); `alu_tb` borrow-polarity suite (A>/=/<B) | COVERED-EXHAUSTIVE |
| FLG-12 | UM p.9 n.5 | C4C3: 00=C 01=Z 10=S 11=P, both senses | 8 combos | formal + directed | `condition_flags.sby` condition_met eval; `condition_flags_tb` (5 of 8 combos); system tests hit all 4 flags × both senses across check_conditional_call/sign_parity/rotate_carry scripts | COVERED-FORMAL |
| FLG-13 | UM p.46 | INP drives S→D0, Z→D1, P→D2, C→D3 on bus at PCC T4 | — | formal (packing only) | `condition_flags.sby` bus packing `0000&P&S&Z&C` | COVERED-FORMAL ⚠ that the packed byte actually appears on the external bus at INP T4 unchecked; flag-preservation across INP is SQ-05 |

### J. Instruction semantics

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| I-MOV-01 | UM p.43; ISA | MOV r1,r2: r1←r2, r2 unchanged | all 49 pairs | directed | `check_mov_rr_test.sh` (all 49 via chains/swaps) | COVERED-DIRECTED |
| I-MOV-02 | UM p.43 | MOV r,r = NOP (arch state unchanged, PC+1) | 7 cases | directed | mov_rr_test includes NOPs | COVERED-DIRECTED |
| I-MOV-03/04 | UM p.43 | MOV r,M / MOV M,r: mem[H:L] transfer both directions | 14 variants | directed | `check_mov_mem_test.sh` (all 14, incl. self-modifying pointers) | COVERED-DIRECTED |
| I-MVI-01/02 | UM p.43 | MVI r / MVI M: immediate to reg / mem[H:L]; PC+2 | — | directed | `check_mvi_m_test.sh`; immediates throughout suite | COVERED-DIRECTED |
| I-IDR-01/02 | UM p.43 | INR/DCR r∈B..L: ±1 mod 256 | wrap 0xFF/0x00 | directed + exhaustive | `check_inr_dcr_test.sh` (all 12 variants + boundaries); ALU-level exhaustive | COVERED-DIRECTED |
| I-ALU-01..08 | UM p.43-44 | ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP semantics (r-form) | all 56 reg ops | exhaustive (ALU) + directed (system) | `alu_exhaustive_tb` (arith); `check_alu_reg_comprehensive.sh` (all 56); `check_alu_full_coverage.sh` | COVERED-DIRECTED (ALU-module arith COVERED-EXHAUSTIVE) |
| I-ALU-09 | UM p.44 | M/I forms: operand = mem[H:L] / B2, same semantics | 8 ops × 2 forms | directed | `check_alu_test.sh` (all 8 immediates); `check_memory_alu_test.sh` (ADC/SBB/ANA/XRA/ORA/CMP M) | COVERED-DIRECTED (ADD M / SUB M added to `check_memory_alu_test.sh`, incoming carry deliberately set and ignored) |
| I-ROT-01..04 | UM p.45 | RLC/RRC/RAL/RAR bit routing + carry | known patterns | directed | `check_rotate_carry_test.sh`, `check_rotate_flags_test.sh` | COVERED-DIRECTED |
| I-JMP-01 | UM p.45 | JMP: PC ← B3[5:0]:B2 | — | directed | every multi-checkpoint program relies on jumps landing | COVERED-DIRECTED |
| I-JMP-02/03 | UM p.45, p.48 n.11 | Jcond taken → target (11 st); not-taken → PC+3 (9 st), all 3 cycles still run, no other change | 4 flags × 2 senses × 2 | directed | `check_sign_parity_test.sh` (JP/JM/JPE/JPO), `check_rotate_carry_test.sh` (JC/JNC), zero-jumps across suite; state counts via cycle_count | COVERED-DIRECTED ⚠ no single artifact enumerates all 16 jump combos; taken/not-taken state-count correlation unchecked (ST-11 ⚠) |
| I-CAL-01 | UM p.45 | CAL: push return, PC ← target | — | directed | stack_depth/pc_carry_call/search tests | COVERED-DIRECTED |
| I-CAL-02/03 | UM p.49 n.12 | Ccond taken = CAL; not-taken = no push, PC+3 | 16 combos | directed | `check_conditional_call_test.sh` (CC/CNC/CNZ/CZ), `check_sign_parity_call_test.sh` (CP/CM/CPO/CPE) — taken + not-taken | COVERED-DIRECTED ⚠ SP-unchanged on not-taken asserted only indirectly (program continues correctly) |
| I-RET-01..03 | UM p.46, p.49 n.13 | RET pop; Rcond taken pop / not-taken no-pop PC+1 (3 st) | 16 combos | directed | RZ (conditional_call), RP/RM/RPE/RPO (sign_parity), RC/RNC (rotate_carry) | COVERED-DIRECTED |
| I-RST-01/02 | UM p.46, p.49 n.14 | RST: push next addr at T3; PC ← 8×AAA; RET resumes | all 8 vectors | directed | `check_rst_full_test.sh` (all 8), `check_rst_test.sh` | COVERED-DIRECTED |
| I-INP-01 | UM p.46 | INP: A ← port MMM; PCC cycle bus protocol | 8 ports | directed | `check_io_test.sh`, `check_io_comprehensive_test.sh` (INP 0-7) | COVERED-DIRECTED ⚠ T4 flags-out and T2 port-on-bus unchecked (FLG-13, BUS gaps); SQ-04/SQ-05 open |
| I-OUT-01 | UM p.46 | OUT: port RRMMM ← A; A & flags unchanged; 6 states | 24 ports | directed | `check_io_comprehensive_test.sh` (OUT 8-30) | COVERED-DIRECTED |
| I-HLT-01 | UM p.46 | HLT (3 encodings): STOPPED entered; regs/mem unchanged; PC past HLT | 3 encodings | directed | `check_hlt_01_test.sh` / `check_hlt_ff_test.sh` — post-HLT sentinel checkpoint asserted ABSENT + s_stopped grep (rtl) | COVERED-DIRECTED ⚠ 0x00 encoding covered at decode level only (DC-04) |

### K. Decode completeness / don't-cares

| ID | Spec cite | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|-----------|------------|------------|----------------|--------|
| DC-01/02/03 | UM p.45-46 | JMP/CAL XXX aliases (8 each), RET XXX aliases (8), B3 D7:D6 don't-care (4) — identical behavior | all aliases | exhaustive (decode) | `sim/cocotb/test_instruction_decoder.py` — 256 opcodes vs independent Python golden model, 24 outputs each | COVERED-EXHAUSTIVE ⚠ decode-level; no execution-level alias test (accepted: decode equality implies execution equality given control path is decode-driven) |
| DC-04 | UM p.43, p.46 | 0x00/0x01 = HLT (not INR/DCR A); 0xFF = HLT (not MOV M,M) | 3 opcodes | exhaustive + directed | decoder sweep; `check_hlt_01_test.sh`/`check_hlt_ff_test.sh` (weak, see I-HLT-01) | COVERED-EXHAUSTIVE (decode) ⚠ execution weak |
| DC-05 | DS72 p.2-3 | All 256 opcodes decode defined/aliased; none wedge the FSM | full space | exhaustive | decoder sweep with KNOWN_QUIRKS waiver (issue #4 spurious mem_indirect on CPr 0xB8-0xBE, 0xFF — verified benign, staleness-guarded) | COVERED-EXHAUSTIVE ⚠ waived quirk is a live RTL deviation (issue #4); INM/DCM slots characterized + pinned by `check_undef_opcode_test.sh` (SQ-12 ratified) |
| DC-06 | DS72 p.43; UM p.51 | Worked-example program encodings assemble & run per manual listing | integration | directed | `check_search_test.sh` (Intel manual character-search program) | COVERED-DIRECTED |

### L. Cross-products (Phase 2)

| ID | Assertion | Conditions | Check type | Check artifact | Status |
|----|-----------|------------|------------|----------------|--------|
| XP-01 | INT during any cycle/T-state of multi-cycle instr: T1I only after instr completes | arrival per cycle | directed | `check_interrupt_test.sh` — 3 jams into running jump loop | COVERED-DIRECTED ⚠ arrival timing not systematically swept per T-state |
| XP-02 | INT already pending when HLT executes → STOPPED then immediate T1I wake (Fig 20 HLT·INT arc) | — | — | none | GAP |
| XP-03 | INT during WAIT: no T1I until READY releases + instr completes | — | directed | `check_jam_test.sh` S4 — INT asserted while parked, no-T1I-during-WAIT asserted, service after release, loop count exact | COVERED-DIRECTED |
| XP-04 | Not-ready per cycle type ×6: WAIT inserted; final arch state equals no-wait run | 6 variants | directed | `check_ready_wait_test.sh` (statistical coverage: ~300 drops of varied length across all cycle types of memory_alu_test) | COVERED-DIRECTED |
| XP-05 | In-flight data (reg.a/reg.b) survives arbitrary-length WAIT mid-instruction | long wait | directed | `check_ready_wait_test.sh` 100 µs park mid-program + checkpoint equality | COVERED-DIRECTED |
| XP-06 | Push/pop SP wrap: CAL & RST at SP=7; RET at SP=0 | ×3 | formal + directed | `stack_pointer.sby` wraps; `check_stackwrap_test.sh`; `check_rst_wrap_test.sh` (RST as the 8th push, wrapped-slot landing asserted) | COVERED-FORMAL |
| XP-07 | 8 nested CALLs: returns 1-7 correct, 8th wrapped per STK-06 | — | directed | `check_stackwrap_test.sh` | COVERED-DIRECTED |
| XP-08 | Conditional J/C/R × {C,Z,S,P} × sense × outcome = 48 combos: PC + SP + state count each | 48 | directed (scattered) | union of conditional_call, sign_parity, sign_parity_call, rotate_carry scripts | COVERED-DIRECTED ⚠ no artifact proves all 48 enumerated; per-combo state counts unverified |
| XP-09 | MOV 49-pair sweep | 49 | directed | `check_mov_rr_test.sh` | COVERED-DIRECTED |
| XP-10 | Write H/L then M-op uses new H:L | — | directed | mov_mem self-modifying pointers | COVERED-DIRECTED |
| XP-11 | ALU boundary operands (carry chain, zero, sign, parity, C_in) | — | exhaustive | `alu_exhaustive_tb` (all 8 ops) | COVERED-EXHAUSTIVE |
| XP-12 | Fetch page-cross + 14-bit wrap 0x3FFF→0 | 2 boundaries | formal + directed | stack_memory carry props; pc_carry_call_test; `check_pc_wrap_test.sh` | COVERED-DIRECTED |
| XP-13 | M ops with H[7:6]=11 alias to H[5:0] address | — | directed | `check_hl_mask_test.sh` — all four H quadrants (00/01/10/11) alias one RAM byte, cross write/read | COVERED-DIRECTED |
| XP-14 | Jam 3-byte instr (JMP/CAL) at interrupt; B2/B3 supplied by the interrupting controller | — | directed | `check_jam_test.sh` S3 | COVERED-DIRECTED |
| XP-15 | Single-step whole program via READY pulses ≡ free run | — | — | none | GAP |

---

## Phase 4 — Scar tissue (escaped-bug history → checklist rules)

Sources: git history, `docs/LEGACY.md`, `docs/INTERRUPTS.md`, `docs/bug-report-yosys-rom-0xff.md`, `sim/cocotb/test_instruction_decoder.py` (issue #4 substance). GitHub issue bodies unreachable this session (`gh` blocked); issue #4 reconstructed from the quirk table and commit `b7c2b57`.

| # | What escaped | How caught | Vplan row that would have caught it | Generalized rule |
|---|--------------|-----------|-------------------------------------|------------------|
| S1 | Decoder asserted `instr_is_mem_indirect` on CPr 0xB8-0xBE and 0xFF; benign only because downstream gates it (issue #4) | Exhaustive cocotb sweep, 256 opcodes vs independent Python model (`b7c2b57`) | DC-05 — and it DID; this row is the success story | Directed tests never observe unexercised control outputs. Every decoder gets an exhaustive differential sweep vs a model derived from the spec, never from the RTL. |
| S2 | INR/DCR clobbered carry (`7649a52`); passed the 42-case hardware ISA selftest; killed SCELBAL floating point and Mandelbrot on silicon | Real application workload; pinned afterward by `inr_carry_test` + alu_tb 12-14 | FLG-07 with its "C=0 and C=1 pre-states" condition — a dirty-carry-then-INR sequence | Assert flag **preservation** across instructions, not just flag production per instruction. Every "flag unchanged" spec sentence needs a dirty-pre-state test. |
| S3 | Rotates recomputed Z/S/P (spec: carry only) (`15b863d`) | Silicon-gaps review vs spec | FLG-10 (Z/S/P before==after) | Same family as S2: flag-update *masks* are first-class spec rows; per-op result checks pass while preservation is wrong. |
| S4 | INT sampled at every fetch T3 → multi-cycle instruction hijacked mid-flight; PC skid one byte past taken-jump target after handler ("intstorm" crash). Aggravator: split-PC pre-increment needed `pc_was_loaded` compensating state that also broke at stack wrap | Interrupt-storm test on hardware; fixed structurally (PC-in-stack, boundary-only sampling per Fig 2) | ST-09 / XP-01 (interrupt never recognized mid-instruction, per-cycle arrival sweep) | Async events are sampled only at the spec's named boundary; a compensating flag paired with another state is a structural smell — delete the pair, don't add conditions. |
| S5 | Architecture silently deviated: separate PC + 8 return-only slots (8 clean nested returns) vs real 8008 PC-in-stack (7 + wrap-onto-oldest). **All tests passed** (`ba10e6e`) | Depth-characterizer test whose expected values came from the real 8008's documented stack behavior | STK-06 / XP-07 (8th-CALL wrap semantics — now `check_stackwrap_test.sh` with its negative assertion) | Faithful-model divergence can have zero functional failures. Write characterizer tests whose *expected values differ between the architectures*, not tests both architectures pass. |
| S6 | Dead board post-build: (a) combinational interrupt-vector mux raced `bootstrap_done` mid-T1I → jam byte flipped RST0→RST5 during acknowledge; (b) int_button polarity assumption; (c) READY freeze on resting-high switch (`fe93c0b`) | Hardware bring-up; hostile boot TB (all switches held HIGH) added after | (a) INT-03/XP-14 jam-stability during acknowledge; (b)(c) board-level, outside CPU vplan — bring-up plan scope | Anything sampled during a multi-state transaction must be registered at transaction start. Bench plan must include a hostile-input pass (every external pin at its "wrong" resting level). |
| S7 | Bootstrap FSM clocked on derived phi2 with async reset — unconstrained paths, glitch re-jams; **years of "address-dependent" flakiness** from stacked independent faults (`5a0c12e`) | Long hardware root-cause; fix = phi2 rising-edge *enable* inside clk_sys (single domain) | None — CDC is invisible to an architecture vplan; belongs to the MAS CDC/reset section | Every clock crossing gets a declared strategy in the MAS before RTL; a derived clock is a CDC even when it "looks synchronous". Sim cannot see this class. |
| S8 | USART `rx_ready` clear raced arriving bytes (~2% loss); first patch converted loss into duplicates (`7c47603`) | Intermittent on hardware; proven fixed by 59/59 HEX-record load | Peripheral contract, outside CPU vplan — interface-spec scope | Producer/consumer handshakes need an atomicity contract (snapshot-and-pop). A patch that *shifts* the failure mode is the tell that the contract, not the code, is wrong. |
| S9 | Yosys ROM `(others => x"FF")` fill synthesized corrupt on ECP5; GHDL sim identical-and-passing (`be8f9a8`, docs/bug-report-yosys-rom-0xff.md) | Hardware-only A/B fill-pattern isolation | No RTL-sim row can catch a synthesis bug — netlist-equivalence tier (EQY/miters) + hardware selftest ROM are the countermeasures | Trust boundary ends at the netlist: keep RTL↔netlist equivalence checks and an on-silicon selftest in the plan; sim/silicon divergence is a standing bug class. |
| S10 | s8008: ALU ops broke on hardware while sim passed (single-cycle behavioral timing masked everything); v8008: conditional-logic accretion until unmaintainable, abandoned (docs/LEGACY.md) | Post-mortem; b8008's founding philosophy is the fix | Whole-vplan methodology | Behavioral monoliths hide timing bugs until hardware. Decompose; test each block in isolation; a growing `if (state=X and flag=Y and not …)` is the failure signature. |
| S11 | EQY structurally unable to judge sequential write_vhdl round trips (vector-flop splitting breaks state matching; SAT falsifies from unanchored states) — red CI "proof" (`a0a7597`) | CI red; sequential equivalence moved to SBY miters | Meta — affects trust in every COVERED-FORMAL citation | Know each formal engine's soundness domain; a passing configuration that *cannot* prove is worse than none. Document per-suite why the mode (BMC vs k-ind vs EQY) is sound. |
| S12 | Test-infra bugs implicating the DUT: hex-loader miscounted verification, silently dropped records (`accda13`); hand-ported asm typo `mov d,h` (`5c98847`) | Loud-fail rework; manual diff | Meta — checker trust | Mutation-test every checker (already a repo convention in `.git/sdd/TODO.md`); a checker that can't fail is a liability (cf. hlt scripts, `run_all_tests.sh` banner grep — Tier 3 gaps). |

**Cross-cutting:** (1) sim-passes/hardware-fails is the dominant escape route (S2, S6-S10) — netlist equivalence + hardware selftest are load-bearing, keep them first-class. (2) Flag side-effects escaped a 42-case ISA selftest twice (S2, S3) — preservation rows now exist (FLG-06 ⚠ still incidental for loads). (3) An independent spec-derived model caught what no directed test did (S1); characterizer tests did the same for S5 — and a reference model is only as good as its fidelity: spec-derived, never RTL-derived, and itself validated before trusted. (4) Compensating paired state is the recurring structural bug (S4, S5).


---

## Phase 2 — Pruning log

| Pruned group | Justification |
|--------------|---------------|
| INT arrival at sub-T-state (φ-edge) granularity | UM p.10 defines INT setup as an external-synchronizer stimulus constraint; DUT behavior is specified per-state only. |
| READY × instruction identity (full product) | READY is sampled identically at T2/WAIT of every cycle (one WAIT node in Fig 2); cycle TYPE is the only distinguishing axis → XP-04's 6 variants suffice. |
| Flag pre-state × non-flag-reading instructions | Only conditionals read the selected flag and only ADC/SBB consume C as data (UM p.8-9); all other instructions are defined independent of flag state. |
| SP value × non-stack instructions | SP is referenced only by push (CAL/Ccond-taken/RST) and pop (RET/Rcond-taken) per UM p.7. |
| MOV 49 pairs as 49 rows | One proposition parameterized by (DDD,SSS); kept as a single sweep row (XP-09) with full enumeration inside the check. |
| ALU operand space as per-value rows | Ops are pure functions of (A, operand, C_in); one exhaustive-sweep row (XP-11) covers the space. |
| Dynamic-memory refresh (UM p.7: full refresh every 80 clk) | Implementation property of Intel's PMOS dynamic RAM; architecturally invisible when correct; vacuous for static-register RTL. Noted, not tested. |
| DC/analog electrical (voltage levels, capacitance, pF-load delays) | Not observable in RTL simulation. |
| Absolute clock-period values (µs) | Sim runs scaled clocks; ratio/non-overlap rows kept (CLK-01/02), wall-clock values dropped. |
| PROM programmer / SIM8-01 board / TTY / bootstrap appendices | External system app notes; no CPU-mandated behavior. |
| 8008-1 speed grade | Same architecture; only tCY bound differs — no functional delta. |

---

## SPEC-QUESTIONS (ALL RATIFIED — see SPEC.md §6 for rulings)

| ID | Question | Sources |
|----|----------|---------|
| SQ-01 | isa.json codes JFc AND JTc both as `01CCC000` (no sense bit) — conflicts with DS72/UM `01 0C4C3 000` (false) vs `01 1C4C3 000` (true). Fix isa.json? | ISA vs DS72 p.36 / UM p.45 |
| SQ-02 | isa.json lists conditionals at flat 11 (J/C) and 5 (R) states, no not-taken counts — conflicts with 9/11 and 3/5 in both PDFs. `check_cycle_count_test.sh` reads isa.json as oracle yet accepts {9,11}/{3,5} — where does the pair actually come from? Align isa.json with PDFs? | ISA vs DS72 p.45 / UM p.59 |
| SQ-03 | HLT "4 states" but only T1-T3 populated; note 18 says CPU "internally remains in the T3 state". What should the cycle-accurate model count as the 4th state? | DS72 p.41 n.18; UM p.48 |
| SQ-04 | INP: text says A loaded at T3; micro-op table says T3→reg.b, T5 reg.b→A. Which T-state updates architectural A (matters for interrupt/observability, not final state)? | DS72 p.37 vs p.41; UM p.46 vs p.49 |
| SQ-05 | INP outputs flags on the bus at T4 — but does INP modify flags? Spec silent. Propose default: unchanged. | UM p.46 |
| SQ-06 | Stack overflow: "content of the lowest level register is destroyed" — oldest return address (relative) or slot 0 (absolute)? stackwrap_test embodies one reading. | UM p.7 |
| SQ-07 | Page-cross: is the T2 value of the same cycle pre-carry (visible wrong-page artifact) or does the carry land before the T3 fetch? Determines cycle-accurate bus behavior at xxFF boundaries. | UM p.7; DS72 p.7 |
| SQ-08 | "each of these states will be 2n clock periods" (WAIT/STOPPED) — per-visit granularity assumed; confirm. | DS72 p.5; UM p.5 |
| SQ-09 | READY deasserted after φ22 of T2 — behavior in that window undefined by spec. What should the model do? | DS72 p.16-17 |
| SQ-10 | UM names carry-clear only for register-form logicals ("NDr, XRr, ORr set the carry flip-flop to zero"); DS72 states it generally. Assume all forms clear C (current tests assume yes)? | UM p.43 vs DS72 p.34 |
| SQ-11 | DS72 Fig 2 "INSTRUCTION JAMMED IN ON INTERRUPT CYCLE?" YES-arc — which cycle does the YES path model for a multi-cycle jammed instruction? | DS72 p.5 Fig 2 |
| SQ-12 | Opcodes `00 111 000`/`00 111 001` (would-be INR M/DCR M): spec says memory "may not be incremented" but defines no decode. What must b8008 do? (Decoder sweep's Python model must have picked something — that choice is a silent resolution.) | UM p.43 |
| SQ-13 | DS72 p.37 prints restart mnemonic as "RET 00 AAA 101" (typo; p.45 says "RES"). Cosmetic — noted for citation hygiene. | DS72 p.37/45 |
| SQ-14 | isa.json CAL rows carry no PUSH annotation in any T-state (UM: push at T4 of cycle 3). isa.json omission worth fixing? | ISA vs UM p.49 n.12 |
| SQ-15 | Scope: must b8008 reproduce the 8008 power-on protocol (HLT forced into IR, 16-clock clear, INT-to-start) or is explicit reset an accepted divergence? Decides PWR-01/03 status. | UM p.11 |

---

## Phase 5 — Ranked gap report

Ranking: spec-mandated behavior with **no failing check** first; then weak/incidental coverage; then meta-gaps (checks exist but can't fire). Proposed checks match existing idioms (SBY/PSL property suites, cocotb differential models, `checkpoint_lib.sh` scripts).

### Tier 1 — spec-mandated, nothing would fail

1. ~~READY/WAIT at system level~~ **DONE** (XP-04, XP-05, RDY-02) — `READY_STRESS` TB generic + `check_ready_wait_test.sh`: varied drops + long park over memory_alu_test, checkpoints byte-identical to free run, WAIT observation asserted. Mutation-tested (WAIT-resume-to-T1 caught). Residual: RDY-03/XP-15 READY single-stepping (one machine cycle per pulse) still GAP.
2. ~~HLT never actually verified to halt~~ **DONE** — post-HLT sentinel asserted absent + rtl s_stopped grep in both scripts.
3. ~~Interrupt jam generality~~ **DONE** — dedicated `interrupt_jam_tb` + `jam_test_as.asm` + `check_jam_test.sh`: NOP/HLT/3-byte-JMP jams via the new int_jam_byte override on b8008_top, single-T1I assertion, INT-during-WAIT scenario. Mutation-tested (early ir_loaded_from_interrupt clear caught).
4. **External bus per-T-state contract** (BUS-01, BUS-02, BUS-04, BUS-06, D6/D7 encodings of BUS-03). The design claims cycle-accuracy; nothing checks what is on the bus at T1/T2/T4/T5. **Propose:** cocotb bus-protocol monitor on `b8008_top` (matches decoder-sweep idiom): at every SYNC-qualified T-state, assert T1=PCL/L, T2={cycle-code, high addr}, code∈{PCI,PCR,PCC,PCW} per instruction class, cycle 1 always PCI; run over an existing program ROM. This single monitor closes 5 rows.
5. ~~14-bit PC wrap 0x3FFF→0~~ **DONE** — `pc_wrap_test` plants NOPs in top-of-memory RAM at runtime, fetch wraps into the reset vector, sentinel-routed checkpoint. Mutation-tested (upper-increment saturation caught).
6. ~~7-level nesting off-by-one~~ **DONE** — `stack_depth_test` nests 7 with per-level checkpoints.
7. ~~H[7:6] don't-care masking~~ **DONE** — `hl_mask_test`: all four H quadrants alias one physical byte, cross write/read. Mutation-tested (latch slice shift caught).

### Tier 2 — covered weakly / incidentally

8. ~~Logical ops missing from exhaustive ALU sweep~~ **DONE** — `alu_exhaustive_tb` covers all 8 ops (1,049,600 cases; carry-in ignored and carry flag forced 0 proven per logical case). M/I-form carry-clear at system level remains with FLG-09's directed checks.
9. ~~ADD M / SUB M no directed check~~ **DONE** — two checkpoints in `memory_alu_test`, incoming carry set and ignored.
10. **Conditional 48-combo matrix scattered** (XP-08, I-JMP-02/03⚠) and cycle-count taken/not-taken correlation unchecked (ST-11⚠). **Propose:** one generated program `cond_matrix_test` enumerating all 48 (set flag → conditional → checkpoint), plus teach `check_cycle_count_test.sh` to pair counts with taken/not-taken outcome (it already parses IR and isa.json).
11. ~~Load-preserves-flags never directly asserted~~ **DONE** — `flag_test` load-storm rounds, both polarities.
12. **INP protocol details** (FLG-13⚠, I-INP-01⚠): flags-on-bus at T4, port number at T2. Fold into the Tier-1 #4 bus monitor. Blocked partly on SQ-04/SQ-05 answers.
13. **Double-address emission on T1I** (INT-02, PWR-03⚠): the visible signature of the PC-not-incremented rule. Fold into bus monitor (assert cycle-N and cycle-N+1 addresses equal around T1I).
14. XP-03 ~~INT during WAIT~~ **DONE** (`check_jam_test.sh` S4). XP-02 (INT already pending at the instant HLT executes) remains: the arrival window is a few states wide and timing-fragile to hit deterministically; the observable (STOPPED+pending→T1I wake) is covered by ST-06/INT-08 and the jam test's stop/wake path.
15. ~~RST at SP wrap~~ **DONE** — `check_rst_wrap_test.sh` (dedicated program; wrapped-slot landing + clean-return-absent).

### Tier 3 — meta-gaps (harness would not fire)

16. ~~`run_all_tests.sh` trusts banner-grep over exit codes~~ **DONE** — exit code primary, banner cross-check, case-insensitive failure excerpt with tail fallback.
17. ~~Assembly regression suite not in CI~~ **DONE** — regression job in verification.yml, matrix rtl|netlist; ASL built from pinned source (setup-asl action), .mem stays uncommitted (auto-assemble; cold-checkout verified 28/28).
18. ~~`stack_memory` + `stack_memory_miter` not in CI sby matrix~~ **DONE** — both in the sby matrix; miter completes clean (bmc depth 15, CI job has a 60-min timeout override; induction unanchorable — 113 hidden gate bits).
19. **Stale collateral:** `machine_cycle_control_tb` red at HEAD (excluded from test-units); `phase_clocks_tb` stale component declaration masks 6 new ports (CLK-01⚠); `docs/instruction_coverage.md` stale by its own header — mark superseded by this vplan.
20. **CLK-02 clock-ratio conformance** unchecked — low risk (phase_clocks is stable), one-time TB addition.

### Row-count summary

| Status | Count (of 97 spec+XP rows) |
|--------|------|
| COVERED-FORMAL | 21 |
| COVERED-EXHAUSTIVE | 7 |
| COVERED-DIRECTED | 38 |
| COVERED-INCIDENTAL | 7 |
| GAP | 24 |

(⚠ residual holes inside COVERED rows are enumerated in the tiers above; 15 SPEC-QUESTIONs open.)

