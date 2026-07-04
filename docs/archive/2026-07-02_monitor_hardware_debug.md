> **ARCHIVED - EXECUTED.** All findings actioned: pll_25mhz.v committed,
> project.mk hardened (pipefail + no timing-allow-fail), bootstrap FSM moved
> to clk_sys, and the board came back to life (commit fe93c0b and onward -
> the real final root causes were a vector-mux race and switch polarity).
> Kept for the forensic record.

# 2026-07-02 Next Steps — b8008 Monitor Hardware Debug

## Context

Prompt for continuing debug of the b8008 monitor on real hardware (ECP5-5G Versa,
external AT28C64B EEPROM through level shifters). Symptoms observed on the board:

1. Monitor sometimes starts, sometimes not; start button needs multiple presses.
2. Typed characters produce no echo/output; no command works.
3. Adding code to the monitor firmware breaks previously-working behavior.

A diagnostic session on 2026-07-01 (dev machine) traced these to a likely root
cause chain. **This machine (build machine) is the one that builds and flashes,
so verification and fixes happen here.**

## Findings from the 2026-07-01 session

### F1. `src/components/pll_25mhz.v` is missing from the repository

Commit `17647ab` ("monitor: Implement PLL for 25 MHz system clock") is the fix
for the board's timing problems: it moves every flop from the raw 100 MHz
oscillator onto a 25 MHz PLL output. But the PLL primitive wrapper it depends on
was never committed:

- `projects/b8008_monitor/src/b8008_monitor_top.vhdl:183-189` declares component
  `pll_25mhz` (black box to GHDL).
- `projects/b8008_monitor/Makefile:30` adds `$(COMP_DIR)/pll_25mhz.v` to
  `EXTRA_V_SRCS` for Yosys.
- `git log --all -- '*pll*'` returns nothing. The file exists in no commit on any
  branch. If it exists on this machine, it is an untracked local file.

### F2. The build system swallows failures — "build succeeded" is not evidence

Two independent holes, both verified:

- `projects/project.mk:233` pipes Yosys through `tee` with no `pipefail`.
  Verified: `yosys -p "read_verilog /nonexistent.v" | tee /dev/null` prints the
  ERROR but the pipeline exits 0, so make continues past a dead synthesis step.
  When that happens, the **stale JSON from the previous build** feeds nextpnr and
  gets packed into the bitstream with no visible error.
- `projects/project.mk:246` runs nextpnr with `--timing-allow-fail`, so timing
  failures never stop the build either.

Consequence: if `pll_25mhz.v` is absent here, every "successful" build since
commit `17647ab` actually flashed the **pre-PLL netlist** — all logic clocked at
raw 100 MHz against a measured fmax of ~41–59 MHz (see
`projects/b8008_monitor/reports/timing.txt`, one section literally reports
`41.61 MHz (FAIL at 50.00 MHz)`).

That pre-PLL design explains every symptom:

- Worst timing path terminates at `u_debug_clk` clock-enable → start button
  logic misbehaves.
- UART logic is single-cycle at 100 MHz, ~2x over fmax → RX/TX flops miss
  setup → typed characters go nowhere.
- Each firmware/RTL change reshuffles place-and-route → marginal paths flip
  between passing and failing → "adding code breaks it."
- Commit `17647ab`'s own message confirms the failure mode: the 100 MHz clock
  "caused the CPU register paths to fail timing and the monitor to emit garbage
  on UART."

### F3. Post-bootstrap hardware breakpoint (independent of F1/F2)

Commit `7cba95b` added an auto-stop: `debug_clock_control` halts the CPU the
moment `bootstrap_done` rises, unless disabled by `sw(1)`
(`projects/b8008_monitor/src/b8008_monitor_top.vhdl:399`,
`src/b8008/debug_clock_control.vhdl:135-137`). With `sw(1)` off, the CPU boots,
jams RST 0, then immediately freezes — which presents exactly as "start button
doesn't take, press again, eventually works." **Set `sw(1)=1` for normal runs.**

### F4. Secondary/latent issues (not the current blocker, fix later)

- Bootstrap FSM is clocked on the derived `phi2` signal with async reset and
  1-FF sampling of `s0/s1/s2/sync` from the `clk_sys` domain
  (`b8008_monitor_top.vhdl:415-435`). Same failure class as the T1I→STOPPED
  intermittent start documented in `next_steps.md`.
- `bootstrap_done` crosses into `debug_clock_control` through a single FF
  (`debug_clock_control.vhdl:132-137`) — no synchronizer.
- `rom_d[7:0]` has no input synchronizer and no LPF input constraints; safe only
  because the ~2 µs phi cycle dwarfs EEPROM access time, but unmodeled.
- Firmware: `parse_command` dispatches on `buffer[0]` without checking length
  (`projects/b8008_monitor/b8008_monitor.asm:454-477`). A CR+LF terminal fires
  `handle_enter` twice; the second pass parses a stale buffer. Terminal must be
  **115200 8N1, send CR only, local echo OFF** (the asm header says the same).
  No backspace handling.
- UART RX oversampling divisor truncates at 25 MHz (`usart.vhdl:51-52`:
  25e6/(115200·16) = 13.56 → 13, ~4.2% fast per tick). Works, but little margin
  against a fast sender. Consider fractional accumulator later.

## Step 1 — Verify which netlist is actually on the board (do this first)

```bash
cd <repo>/projects/b8008_monitor
grep -c EHXPLLL reports/pnr.txt
grep -m3 -iE '^ERROR' reports/synthesis.txt
ls -la ../../src/components/pll_25mhz.v
git status --short
git log -1 --format='%h %ci %s'
ls -la build/*.json build/*.bit
```

Interpretation:

- **`EHXPLLL: 0/4` + an ERROR about `pll_25mhz.v`** → confirmed: board runs the
  pre-PLL 100 MHz netlist. Proceed to Step 2.
- **`EHXPLLL: 1/4` + `pll_25mhz.v` present but untracked** → the PLL build is
  real. `git add src/components/pll_25mhz.v && git commit` immediately so the
  repo is self-contained. Then skip to Step 3 fix list minus the PLL item, and
  re-aim debugging at F3/F4 (breakpoint switch, bootstrap CDC, EEPROM
  contents).

## Step 2 — Create the missing PLL wrapper (if Step 1 confirmed it's absent)

Generate with the tool from oss-cad-suite rather than hand-computing dividers:

```bash
~/oss-cad-suite/bin/ecppll -i 100 -o 25 --clkin_name clk_in --clkout0_name clk_out \
    -n pll_25mhz -f src/components/pll_25mhz.v
```

Requirements for the result (adjust by hand if ecppll flags differ by version):

- Module name `pll_25mhz`, ports `clk_in` (input), `clk_out` (output), `locked`
  (output) — must match the VHDL component declaration at
  `b8008_monitor_top.vhdl:183-189` exactly (Yosys binds by name).
- EHXPLLL instance with 100 MHz CLKI → 25 MHz CLKOP and the LOCK output wired to
  `locked`. If the generated file names the lock pin differently, wire it
  through; POR depends on it (`b8008_monitor_top.vhdl:308-321` holds reset until
  lock).

Commit the file.

## Step 3 — Harden the build so silent failure cannot recur

In `projects/project.mk`:

```make
SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
```

and remove `--timing-allow-fail` from the nextpnr invocation (line ~246). If
removal blocks iteration, keep the flag but add a post-PnR gate:

```make
@! grep -E 'FAIL at' $(PNR_REPORT)
```

Commit.

## Step 4 — Rebuild, verify, flash

```bash
cd projects/b8008_monitor
make clean && make build 2>&1 | tail -40
grep -c EHXPLLL reports/pnr.txt          # expect 1
grep -E 'Max frequency|FAIL' reports/timing.txt   # expect all PASS, clk_sys ~25 MHz domain
make prog                                 # or prog-flash for persistence
```

Do not trust a quiet build — check the two greps.

## Step 5 — Board bring-up checklist

1. `sw(1) = 1` (disable post-bootstrap breakpoint) — F3.
2. `sw(0)` = reset switch; verify its resting polarity.
3. Terminal: 115200 8N1, CR line ending only, local echo off.
4. EEPROM: after any firmware change, re-burn and **verify** against
   `b8008_monitor.bin` (minipro verify pass, `make rom-bin` path). The .bin is
   zero-padded — keep it that way (all-0xFF fill historically triggered the
   Yosys ROM corruption bug, `docs/bug-report-yosys-rom-0xff.md`).
5. Expect: banner + prompt on reset, LED0 on, typed chars echo, `H` prints help,
   `D 2000,10` dumps RAM.

## Step 6 — If symptoms persist after the 25 MHz build is confirmed flashed

Work F4 in this order:

1. Move the bootstrap FSM onto `clk_sys` using the `phi2_rising` enable pulse
   (pattern already established by commits `e7ca0cf`/`412c56c` for other
   modules); 2-FF synchronize nothing — everything lands in one domain.
2. 2-FF synchronize `bootstrap_done` into `debug_clock_control`, or make it a
   `clk_sys`-domain signal outright (falls out of item 1).
3. Add a length check to `parse_command` (skip dispatch when `CMD_LEN == 0`).
4. Probe the logic-analyzer taps (`cpu_d`, `cpu_s0/1/2`, `cpu_sync`, `cpu_phi1/2`
   pins in `constraints/b8008_monitor.lpf`) during an `IN 1` poll loop to watch
   the RX ready flag and jammed data directly.

## Evidence quick-reference

| Claim | Where |
|---|---|
| PLL file referenced but missing | `projects/b8008_monitor/Makefile:30`, `b8008_monitor_top.vhdl:183-189`, empty `git log --all -- '*pll*'` |
| tee swallows yosys exit | `projects/project.mk:233`; reproduced with `/nonexistent.v` → pipeline exit 0 |
| timing allowed to fail | `projects/project.mk:246` |
| fmax vs 100 MHz clock | `projects/b8008_monitor/reports/timing.txt` (41.61 MHz FAIL section) |
| pre-PLL build emitted UART garbage | commit message `17647ab` |
| post-bootstrap breakpoint | `b8008_monitor_top.vhdl:399`, `debug_clock_control.vhdl:135-137` |
| bootstrap CDC hazard | `b8008_monitor_top.vhdl:415-435`; prior notes in `next_steps.md` |
| CR+LF double-enter, no length check | `b8008_monitor.asm:90-95, 454-477` |
