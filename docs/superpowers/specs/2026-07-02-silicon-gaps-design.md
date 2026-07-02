# Silicon Test-Coverage Gaps — Design

Date: 2026-07-02
Status: approved (build all now, user validates on hardware; button/INT work implemented last)

## Goal

Close the five untested-silicon gaps identified after all six period samples
passed on hardware. Every gap gets a hardware-observable validation path;
simulation proves each piece before any bitstream is flashed.

## Decisions (user-approved)

- Runtime interrupt source: **physical switch** (era front-panel feel), not an
  OUT-port latch. Automated INT coverage lives in simulation testbenches.
- READY: **sim testbench + switch hold** on hardware. No slow-peripheral RTL.
- Rotate fix: RTL fix + sim regressions + **hardware selftest ROM extension**
  (rotate-flag cases plus the INR-carry cases the 42/42 selftest lacked).
- Build everything now; user tests at silicon afterward. Gaps 1+2 (button
  INT) implemented last.

## Switch map (free DIP switches on the ECP5 Versa, SW3 bank)

| Switch | Function |
|---|---|
| sw(5) | INT trigger: debounced, edge-detected — one flip = one interrupt |
| sw(6) | READY hold: ON = CPU frozen in WAIT, OFF = resume |
| sw(7) | INT vector: OFF = RST 5, ON = RST 7 |

Pushbuttons remain owned by debug clock control.

## Gap 4 — Rotate flag fidelity (smallest RTL, first)

Real 8008 rotates (RLC/RRC/RAL/RAR) affect **carry only**; our `alu.vhdl`
writes Z/S/P from the rotate result too. Fix: rotates pass Z/S/P through
unchanged, write carry only (same pattern as the INR/DCR carry fix).

Validation:
- `alu_tb` cases: each rotate preserves pre-set Z/S/P while updating carry.
- New `rotate_flags_test_as.asm` + `check_rotate_flags_test.sh`: set flags
  via arithmetic, rotate, branch on the *preserved* flag (the period idiom).
- Hardware selftest ROM gains rotate-flag-preservation cases and INR/DCR
  carry-across cases (regression for commit 7649a52's bug class).
- Full `run_all_tests.sh` regression.

## Gap 3 — 8-level address-stack wraparound (software only)

**FINDING (2026-07-02, during implementation):** b8008 does NOT match the
8008 here. Real silicon keeps the PC inside the 8 address-stack registers
(7 usable return slots; the 8th nested CALL wraps onto the oldest context).
b8008 has a separate `program_counter` block plus 8 return-only stack slots,
so all 8 nested CALLs unwind cleanly — one level deeper than a real 8008,
different wrap semantics. Proven by `stackwrap_test_as` (RTL sim) against
the emulator's faithful PC-in-stack model. The tests below were converted
to CHARACTERIZERS: they assert b8008's current behavior (regression green)
and document the real-8008 signature, flipping expectations is a one-line
change if a PC-in-stack re-architecture is ever approved. **That
re-architecture is a user decision — it restructures the CPU core (Intel's
own block diagram has PC inside the address stack).**

`stackwrap_ram.asm`: nest CALLs 9 deep. The 8-slot stack (PC + 7 return
slots) silently overwrites the oldest entry per spec. Unwind with RETs,
printing a marker at each level; the deepest-out return lands at the
wrapped (wrong-per-naive, right-per-spec) address. Program prints the
observed unwind pattern then PASS/FAIL against the spec-predicted pattern,
exits `jmp 0`. Verified in the Python 8008 emulator first (it models the
stack as unbounded — extend it to 8 slots to predict the pattern), then in
sim, then on silicon via `send_hex.py` + `G`. Runs on any bitstream.

## Gaps 1+2 — HLT wake + runtime interrupts (button, last)

New module `src/b8008/int_button.vhdl` (dumb, ~60 lines):
- Inputs: clk, reset, raw switch level, vector-select bit, bootstrap_done.
- 2-FF synchronize the switch, debounce (reuse `debouncer.vhdl` counter
  pattern), edge-detect both flip directions → arm an interrupt request
  **latch** (not a pulse — held until consumed).
- The latch drives the CPU `interrupt` input; consumed/cleared on the CPU's
  T1I acknowledge (int_clear path already exists in `interrupt_ready_ff`).
  A pending request is gated until `bootstrap_done` so it cannot race the
  boot RST 0 jam.
- `int_vector` mux: bootstrap active → "000"; after bootstrap → sw(7)
  selects "101" (RST 5) or "111" (RST 7).

Monitor top: instantiate, OR into the existing `interrupt` port (bootstrap
already drives it), route vector mux, LPF already has sw(5)/sw(6)/sw(7).

Test programs:
- `hltwake_ram.asm` (gap 1): install RST 5 and RST 7 slot handlers, print
  `SLEEPING`, HLT. Button fires RST n; handler prints `WOKE n`, RET —
  execution resumes at HLT+1 (proves T1I exits STOPPED and the jammed RST
  pushed the right return address), prints `RESUMED`, `jmp 0`.
- `intstorm_ram.asm` (gap 2): handler prints `!` and RETs; main loop prints
  an incrementing hex counter forever. User mashes sw(5); an unbroken
  counter sequence with `!` interleaved proves full state preservation
  across mid-execution jams. Exit: any UART char → `jmp 0`.

Sim: `int_button_tb` (unit: debounce/edge/latch/gating) and a system TB
driving the CPU `interrupt` input directly around a HLT and around a print
loop — the automated equivalents of both silicon tests.

## Gap 5 — READY / WAIT states

RTL: route sw(6) (2-FF synchronized, inverted as needed) to the b8008
`ready_in` port in the monitor top; currently tied '1'.

Sim: testbench drops `ready_in` mid-T3, asserts the state machine holds in
WAIT for N cycles, releases, asserts the instruction stream continues
uncorrupted (memory-read instruction returns correct data).

Silicon: while any sample streams output, flip sw(6) ON → output freezes;
OFF → resumes exactly where it stopped.

## Build/flash batching

Two logical builds, both prepared now; user flashes when back:
- **Build 1** = rotate fix only (behavior-changing): regression + samples
  re-validation, especially calc (heaviest rotate user) + extended selftest.
- **Build 2** = Build 1 + int_button + READY wiring (pure additions).

If the user prefers a single flash, Build 2 covers everything; Build 1
exists as an isolation point if anything regresses. Verify every build per
`projects/project.mk` gates (pipefail + timing) and the EHXPLLL/timing
greps from the 2026-07-02 next-steps doc.

## Validation checklist (user, at silicon)

1. Flash Build 2. Run extended selftest ROM — expect new total, all PASS.
2. Re-run calc: `12.2 X 5.11 =` → `+0.6234202E+02`.
3. `stackwrap_ram` → `PASS`.
4. `hltwake_ram` → `SLEEPING`, flip sw(5), `WOKE 5` `RESUMED` (sw(7) OFF);
   repeat with sw(7) ON → `WOKE 7`.
5. `intstorm_ram` → mash sw(5): `!` interleaves, counter unbroken.
6. Any sample + sw(6) ON/OFF → freeze/resume mid-stream.

## Risks

- DIP-switch bounce → debounce + edge-detect mandatory; latch (not pulse)
  request so phi2-domain sampling can't miss it.
- INT during T1I of the bootstrap jam → gate on bootstrap_done.
- READY freeze while UART TX mid-frame is fine (TX is FPGA-side, not CPU),
  but document that freezing mid-echo can drop *input* characters.
- Rotate fix could expose latent sample bugs that depended on the wrong
  flags — full sample re-validation required (emulator models correct
  behavior already, so calc/stars emulation evidence carries over).
