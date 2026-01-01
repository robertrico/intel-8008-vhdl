# Blinky FPGA Debug - Status Summary

## Date: 2025-12-25

## Current Problem
The b8008 CPU enters T1I (interrupt acknowledge) state but then returns to STOPPED instead of continuing to T2 and executing code.

## What We Know For Certain

1. **POR works correctly** - D21 turns OFF after ~5ms, reset releases properly
2. **Reset switch works** - D21 follows the switch correctly
3. **phi1/phi2 clocks running** - D22 blinks at ~1.7Hz
4. **Bootstrap interrupt fires** - D26 flashes briefly
5. **CPU sees interrupt** - D27 (interrupt_pending) flashes briefly
6. **CPU enters T1I state** - D25 (S2) and D24 (seen_not_stopped) both confirm this
7. **CPU returns to STOPPED** - D28/D29 show S0=1, S1=1 after the brief flash

## The Mystery
- T1I should transition to T2 (not STOPPED)
- The only way to return to STOPPED from T1I is via async reset
- But D21 (reset_int) appears stable (OFF = not in reset)
- Something is causing the state machine to reset during T1I

## LED Mapping (Current Build)
| LED | Pin | Signal | ON means |
|-----|-----|--------|----------|
| D25 | LED0 | S2 | S2=1 (T1I, T2, T4, T5) |
| D24 | LED1 | seen_not_stopped | We exited STOPPED at some point |
| D22 | LED2 | slow_counter | phi1 running |
| D21 | LED3 | reset_int | In reset |
| D26 | LED4 | bootstrap_int | Bootstrap interrupt pending |
| D27 | LED5 | int_pending_sig | CPU interrupt_pending |
| D28 | LED6 | S0 | S0=1 |
| D29 | LED7 | S1 | S1=1 |

## State Reference
| State   | S2 | S1 | S0 | D25 | D29 | D28 |
|---------|----|----|----|----|-----|-----|
| STOPPED |  0 |  1 |  1 | OFF | ON  | ON  |
| T1      |  0 |  1 |  0 | OFF | ON  | OFF |
| T2      |  1 |  0 |  0 | ON  | OFF | OFF |
| T3      |  0 |  0 |  1 | OFF | OFF | ON  |
| T4      |  1 |  1 |  1 | ON  | ON  | ON  |
| T5      |  1 |  0 |  1 | ON  | OFF | ON  |
| T1I     |  1 |  1 |  0 | ON  | ON  | OFF |

## Theories to Investigate

### 1. Reset Glitch (Most Likely)
- `reset_int` may have a brief glitch not visible on LED
- Could be timing issue between 100MHz clk domain and phi2 domain
- The `reset_pulse_count` signal was added but not connected to LED

### 2. Ready Signal Issue
- State machine only advances when `ready = '1'`
- `ready_status` comes from `interrupt_ready_ff`
- Should be '1' (tied high in b8008_top), but worth verifying

### 3. Synthesis Issues with rising_edge on State Signals
- `machine_cycle_control` uses `rising_edge(state_t1i)`, `rising_edge(state_t1)`, etc.
- These are NOT true clocks - they're combinational outputs
- Works in simulation but can cause issues on FPGA
- May create latches or miss edges

## Next Steps to Try

### Quick Test: Connect reset_pulse_count to LED
Change one LED to show if reset pulses after POR:
```vhdl
-- In blinky_top.vhdl LED section:
led(1) <= '0' when reset_pulse_count > 0 else '1';  -- ON if any reset pulses detected
```

### If Reset IS Pulsing
1. Add reset release synchronizer to phi2 domain
2. Ensure clean handoff from POR to running state

### If Reset NOT Pulsing
1. Check `ready_status` signal path
2. Add debug for `ready` signal to LED
3. May need to refactor `machine_cycle_control` to use proper phi1/phi2 clocks instead of rising_edge on state signals

## Files Modified During Debug Session
- `projects/blinky/src/blinky_top.vhdl` - Major changes for POR, bootstrap, LED debug
- `src/b8008/state_timing_generator.vhdl` - Added reset port
- `src/b8008/b8008.vhdl` - Connected reset to state_timing_generator
- `src/components/phase_clocks.vhdl` - Added signal initializations

## Key Code Locations
- State machine: `src/b8008/state_timing_generator.vhdl:180-200`
- Interrupt FF: `src/b8008/interrupt_ready_ff.vhdl:50-61`
- Bootstrap logic: `projects/blinky/src/blinky_top.vhdl:185-207`
- POR logic: `projects/blinky/src/blinky_top.vhdl:148-157`
