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

Style rule (post scar-S7 refactor): **derived enables, never derived clocks**. `phase_clocks` emits `phi1_rising/falling`, `phi2_rising/falling` pulses in the clk_sys domain; `run_enable` freezes the phase FSM in place rather than gating a clock. The last live instance of the scar class (`b8008_uart_top.vhdl`) is retired. Budget rule: no new `rising_edge(phi*)` anywhere.

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

- ~~No constraint on the 25 MHz PLL output~~ **CLOSED**: both b8008 project LPFs carry `FREQUENCY NET "clk_sys" 25 MHz;` explicitly; nextpnr logs "constraining clock net 'clk_sys' to 25.00 MHz" (verified, Fmax 95.00 MHz PASS).
- ~~Timing reports not retained~~ **CLOSED**: `projects/*/reports/timing.txt` is exempted from .gitignore and committed, so budget rows stay backed by evidence.

## 4. Re-check rules

Re-run timing (and update §2) when a change: (a) touches anything in the φ-enable generation or `debug_clock_control`; (b) adds logic between `memory_io_control` and RAM/IO muxes (the historically failing register paths); (c) changes target clock or PLL settings; (d) grows any single module beyond trivial. A PASS at 25 MHz with <2× margin is a stop-and-look signal given the 41.61 MHz history.
