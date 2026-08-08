# b8008 Microarchitecture Specification (MAS)

**Status:** draft — retroactive consolidation (RTL exists; this documents its actual microarchitecture, flagging debts rather than idealizing). Companions: `docs/SPEC.md` (architecture contract), `docs/BUS_PROTOCOL.md` (pin contract), `docs/VPLAN.md` (verification rows), `docs/TIMING.md` (budget).
**Contract discipline:** every interface rule below carries either a citation to an existing formal property `(PSL: <suite>)` or a `TODO-prop` marker — the queue of properties to write. Unmarked statements are descriptive only.

## 1. Design philosophy

Block-based per the Intel 8008 block diagram. Two module classes:

- **Smart (instruction/timing knowledge allowed):** `instruction_decoder`, `machine_cycle_control`, `memory_io_control`, `register_alu_control`, `ahl_pointer` (borderline: knows mem-indirect cycle mapping).
- **Dumb datapath (no instruction knowledge):** `stack_pointer`, `stack_memory`, `register_file`, `scratchpad_decoder`, `temp_registers`, `alu`, `carry_lookahead`, `condition_flags`, `instruction_register`, `io_buffer`, `mem_mux_refresh`, `interrupt_ready_ff`. (Former orphans `sss_ddd_selector`, `scratchpad_addr_mux`, `stack_addr_mux` deleted — never instantiated.)

Known violations of the split are catalogued in §9 — they are debts, not precedent.

## 2. State inventory (what lives where)

| Module | Registered state | Clock enable |
|--------|------------------|--------------|
| state_timing_generator | current_state (8-value enum), state_half | phi2_falling |
| machine_cycle_control | cycle_count (0..2), advance_latch, cycle_done_latch, cycle_type_latch(2b), instr_is_hlt_latch, 6 prev-state edge-detect bits | phi1_rising |
| memory_io_control | 4 prev-state bits, `suppress_pc_inc_next_cycle`, `ir_loaded_from_interrupt` (§9 debt) | phi1_rising |
| stack_pointer | sp (3b) | phi1_rising |
| stack_memory | stack (8×14b — slot[SP] IS the PC), carry_flag | phi1_rising |
| instruction_register | ir (8b) | phi1_falling |
| register_file | reg_a..reg_l (7×8b) | phi2_rising |
| temp_registers | reg_a, reg_b (2×8b) | phi2_rising |
| condition_flags | carry/zero/sign/parity FFs | phi2_rising |
| alu | result_latched (9b), enable_prev (edge detect — §9 debt) | phi2_rising |
| interrupt_ready_ff | int_ff, ready_ff | phi2_rising |
| Pure combinational | instruction_decoder, carry_lookahead, scratchpad_decoder, mem_mux_refresh, ahl_pointer, io_buffer, register_alu_control (control), b8008 structural top | — |

Phase-domain rule: control state updates on φ1 edges, datapath on φ2 edges, state machine on phi2_falling — datapath writes land a half-phase after the control that steers them.

## 3. Control topology

```
                     ┌──────────────────────────────────┐
 interrupt/ready ──► │ interrupt_ready_ff │ ──► int_pending, ready ──┐
                     └──────────────────────────────────┘            ▼
 ┌────────────────┐  advance_state/cycle_done  ┌──────────────────────────┐
 │ machine_cycle_ │ ─────────────────────────► │ state_timing_generator   │
 │ control        │ ◄───────────────────────── │ (T-state FSM, S0-S2 out) │
 └───┬────────────┘  state one-hots+state_half └───────────┬──────────────┘
     │ current/next_cycle, cycle_type                      │ one-hots + status
     ▼                                                     ▼
 ┌─────────────────────┐   ~28 strobes    ┌────────────────────────┐
 │ memory_io_control   │ ───────────────► │ datapath modules        │
 └─────────────────────┘                  │ (IR, io_buffer, regfile,│
     ▲ decoder flags                      │  temp, stack, PC ctrl)  │
 ┌───┴───────────────┐                    └────────────────────────┘
 │ instruction_decoder│ ◄── ir_bits ── instruction_register ◄─ internal bus
 └───────────────────┘
 register_alu_control (status-decode) ──► temp_regs / alu / condition_flags strobes
```

Internal bus: priority mux of six drivers (§6). External bus: T1/T2 address-and-status drive with io_buffer carve-outs (see BUS_PROTOCOL; implementation debt §9.3).

## 4. Sequencing conventions (the load-bearing invariants)

- **PC is post-increment, PC-in-stack.** slot[SP] always holds the NEXT fetch address. T1 second half: `pc_increment_lower` (suppressed during T1I and under `suppress_pc_inc_next_cycle`); T2 second half: `pc_increment_upper` iff carry from lower (`stack_memory` forwards the carry combinationally). `(PSL: stack_memory — lower/upper carry semantics)` Two-stage increment per DS72; page-cross visible artifact is SPEC SQ-07.
- **CALL/RST push = SP increment only** (old slot keeps the post-incremented return address); RST pushes at T4 first half, CALL at cycle-3 T4 second half (after the possible upper carry). **RET pop = SP decrement only, T4 first half; no pc_load** — loading at T5 would corrupt the live slot. `(PSL: stack_pointer P2/P3; stack_memory slot preservation)`
- **advance_state vs cycle_done:** `advance_state` = instruction complete; the ONLY gate under which an interrupt may enter (T3/T4/T5 → T1I). `cycle_done` = cycle over mid-instruction; deliberately no interrupt check. Both latch in machine_cycle_control, clear at every T1/T1I entry. `(PSL: state_timing P4 priority chains; machine_cycle latch rules)` Mutual exclusion of the two is **composition-level only** — module-locally false (HLT-at-T3 path); documented obligation, no core-level wrapper yet. `TODO-prop: core-level advance/cycle_done mutex.`
- **next_cycle contract:** `current_cycle` is stale at T1 start; any decision made at T1 must use `next_cycle` (combinational prediction). Consumers: ahl_pointer, memory_io_control T1 arms, top-level bus mux. `(PSL: machine_cycle P6)`
- **IR timing:** loads phi1_falling during T3 of PCI ("data stable mid-state"), or during T1I second half (interrupt jam); jam sets `ir_loaded_from_interrupt` to suppress the T3 reload. Decoder flags are therefore valid only from T3 first-half onward — machine_cycle_control splits its T3 decisions into t3_rising (old instruction) vs T3-second-half (new instruction) arms. This cross-module timing contract is enforced only by comments today. `TODO-prop: decoder-flag validity window.`
- **Temp registers:** Reg.b = universal transfer latch (opcode at C1 T3; operand/immediate/addr-low at C2 T3; SSS operand at C1 T4; drives bus for MOV C1 T5, port number at I/O C2 T2). Reg.a = address-high only (loads C3 T3; never an ALU operand — accumulator hardwired to ALU input 1; never drives the bus).
- **ALU:** enabled throughout T5; latches result on the rising edge of its enable; `update_flags` fires T5 second half only; destination register written at T5 (bus_to_regfile + scratchpad_write). Rotate → `carry_only` flag path; INR/DCR re-emits carry_in unchanged. `(PSL: condition_flags P3 carry_only; alu covered by exhaustive sweep + miter)`
- **Interrupt FF:** clear (T1I ack) beats set; reset beats both. `(PSL: formal/interrupt_ready_ff P2/P3/P4 — clear-priority, set, hold; k-induction)` Residual: "no-lost-request" across a clear-then-request same-tick window is the clear-wins semantics by design; system-level double-service remains open (VPLAN INT-07 ⚠).

## 5. Machine-cycle control

- cycle_count ∈ {0,1,2}, updates at t1_rising: 0→1 iff needs_cycle_2, 1→2 iff needs_cycle_3, else →0; T1I forces 0. `(PSL: machine_cycle — counter ≠3, latch rules)`
- cycle_type latch: cycle 0 → PCI; else I/O → PCC; else write-match → PCW; else PCR; holds between T2s. `(PSL: machine_cycle P3)`
- Latch arbitration: t1i_rising > t1_rising (both clear all) > t3_rising > T3-second-half > t4 > t5. `(PSL: machine_cycle P5)`

## 6. Arbitration & priority rules

| Rule | Where | Formal |
|------|-------|--------|
| Internal-bus driver priority io_buffer > mem_mux > temp_regs > alu > cond_flags > IR (mutual exclusion is control's job; mux is backstop) | b8008.vhdl:848-854 | `TODO-prop: one-driver-at-a-time (core-level)` |
| SP push beats pop; wraps both directions | stack_pointer.vhdl:53-61 | `(PSL: stack_pointer P2/P3)` |
| PC-slot op priority load > inc_upper > inc_lower > hold (same order in forwarding mux and sync update) | stack_memory.vhdl:98-131 | `(PSL: stack_memory)` |
| T3 exit: stopped > advance(T1I/T1) > cycle_done(T1, no INT check) > T4; T4: advance > cycle_done > T5; T5→T1I only at boundary | state_timing_generator.vhdl:140-197 | `(PSL: state_timing P4)` |
| STOPPED exits only on interrupt → T1I; T2/WAIT park on READY | state_timing_generator.vhdl:102-138 | `(PSL: state_timing arcs)` |
| Scratchpad address: ahl_active override beats scratchpad_select | b8008.vhdl:780 | `TODO-prop` |
| Register-file read priority A>B>…>L (one-hot input makes it moot) | register_file.vhdl:114-121 | `(PSL: register_file mux priority)` |
| PC-load source: RST vector > temp regs (RET loads nothing - the pop IS the return; the stack arm was dead and is deleted) | mem_mux_refresh.vhdl | `TODO-prop (module has no props yet)` |
| condition_met defaults '1' unconditional; conditional = flag XNOR sense | condition_flags.vhdl:132-176 | `(PSL: condition_flags P6)` |

## 7. Clocking, CDC & reset (scar-S7 section)

**Clock architecture:** single clock domain. 100 MHz osc → (monitor/basic: PLL → 25 MHz) → clk_sys; every CPU flop clocks on clk_sys. φ1/φ2/SYNC are *data* signals from `phase_clocks`, which also emits one-clk enable pulses (`phi1_rising/falling`, `phi2_rising/falling`). **Rule: derived enables, never derived clocks.** `run_enable` freezes the phase FSM (a hold, not a gated clock) — `debug_clock_control` header documents why.

**Resolved:** `b8008_uart_top.vhdl` (the last `rising_edge(phi1)` clocking, scar-S7 class) is retired — deleted, unreferenced by any project; `b8008_top.vhdl` is the equivalent. Standing rule: no new `rising_edge(phi*)` anywhere.

**Reset tree (monitor board):** POR = PLL-unlock hold + ~21 ms counter, generated synchronously in clk_sys; `reset_int = por OR sw-reset(3-FF sync) OR debug-stop pulse`; debouncers reset by POR only (breaks reset feedback loop). Core style: uniformly **async active-high** — with exceptions: `alu` and `register_alu_control` have **no reset term** (acceptable only because ALU result is re-latched before use each instruction — worth a one-line justification in RTL comments); `debouncer.vhdl` is async active-**low** (opposite polarity; callers invert — harmonize or prominently comment). No reset-deassertion synchronizer on async-reset flops; safe only because reset_int is clk_sys-synchronous — record as a standing assumption.

**Async pin entries (all → clk_sys):** debug buttons via debouncer (2-FF + 20 ms); sw-reset 3-FF; INT switch via `int_button` (2-FF + debounce + **latched request held until T1I ack** — slow φ-rate sampling can't miss it); READY switch 2-FF + baseline capture; UART RX 2-FF; sw(1..4) quasi-static raw (accepted); sw(7) vector captured at request time.

**Post-reset sequence:** debug controller powers up stopped (CPU frozen) → run/auto-start → bootstrap jams RST 0 via interrupt → hardware break re-stops unless configured. Startup relative to SPEC SQ-15 (8008 power-on protocol) is a documented divergence pending that decision.

## 8. Observability (designed-in; can't add at the bench)

- **Core debug ports (`b8008_top`):** φ/SYNC/S0-S2, address_out, data_out, all 7 registers, PC, IR, cycle, 4 flags, int_pending, state_half, IO ports 8/9/10 — plus the `OUT 31` checkpoint report (full CPU state) that the entire verification-script layer keys on.
- **Monitor board:** dedicated LA pins (cpu_d[7:0], S0-S2, SYNC, φ1/φ2, INT); LED capture modes (fetch data/addr-low/addr-high/status); run/stop/step-φ/step-SYNC buttons.
- **Bench toolchain:** DSView probe map = `INT_RST, PHI1, PHI2, SYNC, S0, S1, S2, D0-D7` (dsview_settings.dsc); `test_tools/*.py` consume DSView CSV export and decode state codes + cycle types (trace_states, trace_execution, check_int_timing, analyze_glitches).
- Rule going forward: any new internal mechanism gets its observability decided here first (scar S6: dead board = no visibility).

## 9. Debts & deviations register

1. **Compensating paired state** (`memory_io_control`): `suppress_pc_inc_next_cycle` (4-arm set condition) and `ir_loaded_from_interrupt` (set T1I, cleared after T4) — the exact pattern behind scars S4/S5; RTL comments memorialize two prior bugs from it. Candidate structural fix, not more conditions.
2. **Conditional accretion:** memory_io_control's 430-line guarded lattice and machine_cycle_control's advance/cycle_done ladder are at the CLAUDE.md style boundary — tolerated in smart modules, but the suppress-flag disjunction is past it.
3. **Instruction knowledge outside decoder/control:** structural top conditions bus mux on `instr_is_io` and picks alu_opcode from instr flags (b8008.vhdl:795-807, 838); machine_cycle_control reconstructs LMr identity by flag algebra (:137). Move into decoder outputs.
4. **Hidden state in a "no state" module:** alu's `result_latched`/`enable_prev` edge-detect adds a second timing convention beneath register_alu_control's level-based one.
5. **Duplicate state decode:** register_alu_control re-derives T-states from S0-S2 while everyone else gets one-hots — two encodings that can drift. `TODO-prop: S-code ↔ one-hot consistency (cheap SBY).`
6. **Dead/vestigial fabric:** ~~orphan modules~~ (deleted); dead memory_io_control outputs (addr_select_sss/ddd, memory_refresh, refresh_increment, stack_addr_select, stack_read/write); unused ports (register_alu_control.interrupt — repo issue #2, memory_io_control.pc_lower_byte); `stack_addr <= pc_addr` alias makes select_stack/pc_load_from_stack degenerate; `pc_control_t.hold` never read; scratchpad_decoder.enable_m dangles; condition_flags bus output permanently disabled. Delete or justify each.
7. **Record-type erosion:** only `pc_control_t` survives as a record; memory_io_control's contract is ~28 scalar strobes. Consider re-grouping into records per consumer (readability + fewer wiring bugs).
8. **Composition obligations:** machine_cycle proof assumes state_timing's one-hot P2 (assume-guarantee); advance/cycle_done mutex proven nowhere. Core-level formal wrapper is the top of the property queue.
