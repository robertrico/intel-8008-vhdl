# b8008 Bring-up & Bench Validation Plan

**Status:** living document — forward-looking successor to the executed/archived bring-up forensics (`docs/archive/2026-07-02_monitor_hardware_debug.md`, whose findings→gated-steps→evidence-table pattern this reuses). Use one dated copy per silicon pass; archive when executed.

## 1. Probe-point map

| DSView ch | Label | FPGA source | RTL signal |
|-----------|-------|-------------|------------|
| 0 | INT_RST | monitor LA header | cpu_int |
| 1 | PHI1 | " | phase_clocks φ1 |
| 2 | PHI2 | " | phase_clocks φ2 |
| 3 | SYNC | " | phase_clocks SYNC |
| 4-6 | S0,S1,S2 | " | state_timing_generator status |
| 7-14 | D0-D7 | " | external data bus |
| 15 | (spare) | — | candidate: READY or io_buffer_oe |

Config: `docs/dsview_settings.dsc` (reusable). Analysis: `test_tools/trace_states.py` / `trace_execution.py` / `check_int_timing.py` / `analyze_glitches.py` on DSView CSV export. Expansion pinout source: `docs/expansion_connectors.json` (X3/X4 ball map).

On-board observability: LED capture modes sw(2)=fetch data, sw(3)=addr[7:0], sw(4)=addr[13:8], default status nibble; `OUT 31` checkpoint reporting over serial; 46-test ISA selftest ROM; monitor D/W/L/G/H commands + Intel HEX load.

## 2. Bring-up sequence (gated steps)

Each step has an observable gate; do not advance on inference. Order = verify-what-exists before fixing (archive-doc discipline).

1. **Bitstream provenance.** Confirm the flashed bitstream is the build you think: rebuild, compare sizes/checksums, keep `reports/timing.txt` (do not delete — TIMING.md §3 lost the last one). Gate: report present, PASS at 25 MHz, margin logged in TIMING.md §2.
2. **Clocks.** Scope φ1/φ2 non-overlap + SYNC cadence (reference captures: `docs/two_phase_oscope_cap_*.png`). Gate: 2.2 µs φ-cycle, dead bands present, SYNC = φ-cycle ÷ 2.
3. **Reset & static state.** POR release ~21 ms after PLL lock; CPU parked (debug controller powers up stopped). Gate: LEDs show stopped status; no fetch activity on LA.
4. **Hostile-input pass (scar S6).** Before any program: every switch/button at its "wrong" resting level (all HIGH, then all LOW); watch for spurious INT, spurious reset, WAIT park. Gate: zero state transitions on LA during 10 s in each configuration.
5. **First fetch.** Run; capture bootstrap RST-0 jam. Gate (VPLAN INT-02/PWR-03): T1I cycle then first PCI both emit address 0 on D0-D7 at T1/T2 (double-emission signature); state codes walk T1I→T2→T3.
6. **Selftest ROM.** 46-test ISA selftest over serial. Gate: 46/46 — and record which VPLAN rows this does NOT cover (it missed scars S2/S3 historically; the checkpoint regression suite is the stronger net).
7. **Checkpoint regression on silicon.** Run the `check_*.sh`-instrumented programs via monitor HEX load where feasible; compare `OUT 31` serial dumps against sim logs. Gate: byte-identical checkpoint lines.
8. **Interrupt storm.** sw(5)/sw(7) RST7 jams into the spinning-loop program (VPLAN INT-06 idiom). Gate: loop-count integrity via checkpoint (C register exact).
9. **READY/WAIT on hardware.** sw(6) not-ready during execution; single-step by READY pulses. Gate (VPLAN RDY-02 sim-covered by check_ready_wait_test.sh; RDY-03 single-step sim-covered by check_ready_step_test.sh): program completes with identical final checkpoints; WAIT code 000 visible on S-pins while parked; bus floats during WAIT (LA: D-lines high-Z/pulled).
10. **Period software.** SCELBAL / Mandelbrot / STARS boot. Gate: known-good outputs (these caught scar S2 when the selftest didn't — they stay in the sequence).

## 3. Contingency

Symptoms persisting after a failed gate: capture LA trace at the failing step, run the matching `test_tools` decoder, and diff against a sim trace of the same program before touching RTL (sim-vs-silicon divergence ⇒ suspect synthesis/toolchain per scar S9 — check yosys ROM-init class first, then constraint coverage per TIMING.md §3).

## 4. Evidence table (fill per pass)

| Step | Gate observation | Artifact (capture/report/log) | Date |
|------|------------------|-------------------------------|------|
| — | — | — | — |
