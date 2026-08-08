# b8008 Timing Budget

**Status:** draft. First written timing budget — previous numbers existed only as scattered results. Turns folklore into checkable statements; every figure cites its source.

## 1. Clock chain

```
100 MHz board osc (Versa P3, LVDS)
  └─ pll_25mhz.v (EHXPLLL, VCO 600 MHz, 100→25 MHz)          [monitor/basic projects only]
       └─ clk_sys 25 MHz — THE clock; every CPU flop lives here
            └─ phase_clocks: φ1/φ2/SYNC as DATA signals + one-clk enables
                 φ1 0.8 µs / dead 0.4 / φ2 0.6 / dead 0.4 = 2.2 µs φ-cycle
                 T-state = 2 φ-cycles = 4.4 µs  →  ~455 kHz effective 8008 clock
```

Style rule (post scar-S7 refactor): **derived enables, never derived clocks**. `phase_clocks` emits `phi1_rising/falling`, `phi2_rising/falling` pulses in the clk_sys domain; `run_enable` freezes the phase FSM in place rather than gating a clock. Known exception: `src/b8008/b8008_uart_top.vhdl:333,360,621` still uses `rising_edge(phi1)` as a clock edge — the last live instance of the scar class (`b8008_top.vhdl` is the fixed equivalent). Budget rule: no new `rising_edge(phi*)` anywhere; retire or refactor b8008_uart_top.

## 2. Budget table

| Domain / path | Required | Measured | Margin | Provenance |
|---------------|----------|----------|--------|-----------|
| clk_sys (whole system, current) | 25 MHz | ~95 MHz fmax | ~3.8× | deck_spec.md:12 (1,672 LUTs, 3% util) |
| clk_sys, historic monitor build @50 MHz | 50 MHz | 41.61 MHz | **FAIL** — motivated the 25 MHz PLL | archive/2026-07-02 debug doc:52-54; report file since deleted |
| CPU register paths @100 MHz direct | 100 MHz | ~44 MHz | FAIL — UART garbage on silicon | b8008_monitor_top.vhdl:380-383; pll_25mhz.v:3-4 |
| blinky-era core (112 LUT/63 FF) | 100 MHz | 218 MHz | historical only — NOT the current core | TODO.md:277, VERSIONS.md:64-68 |
| Effective 8008 clock | ≥ 500 kHz spec-equivalent | ~455 kHz (2.2 µs φ-cycle vs spec max 3 µs) | within spec envelope (tCY 2–3 µs) | phase_clocks.vhdl:67-69; DS72 p.16 |

Beware quoting 218 MHz for the current design — that number predates the full core. The honest current figure is ~95 MHz vs a 25 MHz requirement.

## 3. Constraint gaps

- `FREQUENCY PORT "clk" 100 MHz` exists only in b8008_monitor and b8008_basic LPFs; **no constraint anywhere on the 25 MHz PLL output** — nextpnr infers it from `FREQUENCY_PIN_CLKOP="25"` inside pll_25mhz.v. Fragile: a PLL swap silently unconstrains the system. Action: add explicit 25 MHz FREQUENCY/clock constraint per project.
- `projects/b8008_monitor/reports/timing.txt` (the 41.61 MHz evidence) no longer exists — reports are not retained. Action: keep the latest timing report per project under version control or CI artifact so budget rows stay backed by evidence.

## 4. Re-check rules

Re-run timing (and update §2) when a change: (a) touches anything in the φ-enable generation or `debug_clock_control`; (b) adds logic between `memory_io_control` and RAM/IO muxes (the historically failing register paths); (c) changes target clock or PLL settings; (d) grows any single module beyond trivial. A PASS at 25 MHz with <2× margin is a stop-and-look signal given the 41.61 MHz history.
