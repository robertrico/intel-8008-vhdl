# Intel 8008 Interrupt System

This document describes the Intel 8008 interrupt mechanism and its implementation in b8008.

## Overview

The Intel 8008 implements a **single-level, non-vectorized interrupt** with instruction injection capability. Unlike modern processors with interrupt vector tables, the 8008's approach places significant responsibility on external hardware.

### Key Characteristics

- **Single INT input line** - No priority levels in hardware
- **Instruction injection mechanism** - External device supplies the first instruction byte
- **No automatic state save** - Software/external hardware must preserve context
- **Program Counter preservation** - PC is not incremented during interrupt acknowledge

---

## The Interrupt Sequence

### 1. Interrupt Recognition (Instruction Boundary Only)

Per **Figure 2 of the 8008 User's Manual**, the INTERRUPTED? decision is
reached only when INSTR. EXECUTION COMPLETE = YES. The CPU samples the
latched INT line at the final T-state of an instruction — never between
the machine cycles of a multi-cycle instruction:

- **Sampling point**: the last state of the last machine cycle, whatever
  that is for the instruction (T3, T4, or T5 under cycle-exact timing)
- **Decision**: begin the next instruction at T1I (interrupt acknowledge)
  instead of T1
- **Mid-instruction cycle transitions** (fetch cycle done, address cycle
  done) go straight to the next cycle's T1 with NO interrupt check

**Important**: T1 and T1I are **mutually exclusive states**. The CPU never
enters T1 before T1I, and an in-flight instruction is never hijacked
between its own machine cycles. (b8008's first implementation got this
wrong — see "Common Implementation Mistakes" below.)

### 2. Interrupt Acknowledge Cycle (T1I-T2-T3)

When INT is recognized, the CPU performs a special acknowledge cycle:

**T1I State** (State outputs S2 S1 S0 = 110):
- Lower 8 bits of the PC (the SP-selected address-stack slot) output on
  the data bus
- **The slot is NOT incremented** — under the 8008's post-increment
  convention the slot already holds the next fetch address, and the T1I
  increment is suppressed so the interrupted program resumes exactly
  where it left off

**T2 State**:
- Upper 6 bits of PC and cycle type code output
- External interrupt controller recognizes acknowledge

**T3 State**:
- External controller may optionally drive data bus

### 3. Instruction Injection (Subsequent PCI Cycle)

Following the T1I acknowledge cycle, a **normal PCI cycle** occurs:

**T1 State**: CPU outputs the same PC (still not incremented)

**T2 State**: Cycle type = "00" (PCI - instruction fetch)

**T3 State**: **External interrupt controller jams instruction byte onto data bus**
- Typical instruction: RST n (Restart to vector n)
- Alternative: CALL, JMP, or any valid instruction
- CPU latches this as if it were fetched from memory

**Critical Detail**: Only the first byte is supplied by external hardware. If a multi-byte instruction is injected (e.g., CALL), subsequent bytes are fetched from normal memory.

### 4. Instruction Execution

The injected instruction executes normally through the CPU's decode and execution logic.

**For RST n instruction** (PC-in-stack: a "push" is only an SP move):
1. SP advances; the old slot keeps the return address it already holds
2. The new slot is loaded with (n × 8) — vector address in page zero
3. Execution continues from the interrupt handler

**Vector Locations** (RST instruction):
```
RST 0 → 0x00  (8 bytes: 0x00-0x07)
RST 1 → 0x08  (8 bytes: 0x08-0x0F)
RST 2 → 0x10  (8 bytes: 0x10-0x17)
RST 3 → 0x18  (8 bytes: 0x18-0x1F)
RST 4 → 0x20  (8 bytes: 0x20-0x27)
RST 5 → 0x28  (8 bytes: 0x28-0x2F)
RST 6 → 0x30  (8 bytes: 0x30-0x37)
RST 7 → 0x38  (8 bytes: 0x38-0x3F)
```

Each vector has 8 bytes - typically contains a JMP to the actual handler.

### 5. Return from Interrupt

The handler terminates with a RET instruction:
- RET is only the SP pop — the caller's slot never stopped holding the
  return address
- Execution resumes at the interrupted program's next instruction
- No special "return from interrupt" instruction needed

Note: like real silicon booted via an RST-0 jam, the bootstrap interrupt
consumes one stack level permanently — programs get 6 safe nested
returns under the monitor.

---

## Datasheet Evolution: Rev 1 vs Rev 2

An important historical note exists in the Intel datasheets regarding a discovered timing bug.

### Intel 8008 Datasheet Revision 2 (1973) - Critical Addition:

> **When the processor is interrupted, the system INTERRUPT signal must be synchronized with the leading edge of the φ1 or φ2 clock. To assure proper operation of the system, the interrupt line to the CPU must not be allowed to change within 200ns of the falling edge of φ1.**

This was NOT in Revision 1 (1972).

### Why This Matters

- The 8008 was pushing the limits of 1972 PMOS technology
- Internal synchronizers may have been minimal or absent
- Asynchronous INT input could cause race conditions
- Real systems exhibited interrupt-related failures

---

## b8008 Implementation

### Interrupt Synchronizer (`interrupt_ready_ff.vhdl`)

```vhdl
signal int_latched : std_logic := '0';

process(phi2, reset)
begin
    if reset = '1' then
        int_latched <= '0';
    elsif rising_edge(phi2) then
        if int_request = '1' and int_latched = '0' then
            int_latched <= '1';
        end if;
        if int_clear = '1' then
            int_latched <= '0';
        end if;
    end if;
end process;
```

### Key Design Decisions

1. **Clock synchronization**: Meets Rev 2 timing requirements
2. **Edge detection**: Triggers once per interrupt event
3. **No retriggering**: Cleared on acknowledge, prevents loops
4. **Metastability prevention**: Registered input avoids race conditions

---

## Common Implementation Mistakes

### Incorrect: Checking at T1 State

```vhdl
-- WRONG: Already in T1!
when T1 =>
    if INT = '1' then
        timing_state <= T1I;
    else
        timing_state <= T2;
    end if;
```

### Problems with This Approach

1. **T1/T1I exclusivity violation**: CPU enters T1, then tries to go to T1I
2. **Spurious state output**: External hardware sees one clock of T1 before T1I
3. **Possible mid-instruction interrupt**: May sample during non-PCI cycles
4. **PC increment ambiguity**: PC may increment before interrupt recognized

### Also Incorrect (b8008's own first attempt): Checking at Every Fetch T3

Sampling INT at each fetch-cycle T3 looks right but still permits
hijacking a multi-cycle instruction between its machine cycles. On
silicon this produced the interrupt-storm crash: the post-handler resume
skidded one byte past a taken jump target.

### Correct: Check Only at Instruction Completion (Figure 2)

The state machine distinguishes "this machine cycle is done" from "this
instruction is done." Only the latter consults the interrupt latch:

```vhdl
-- end of an instruction (advance_state: last T-state of last cycle)
if int_pending = '1' then
    next_state <= T1I;    -- interrupt honored at the boundary
else
    next_state <= T1;
end if;

-- end of a machine cycle mid-instruction (cycle_done)
next_state <= T1;         -- NO interrupt check here, per Figure 2
```

See `src/b8008/state_timing_generator.vhdl` and the Phase-4 storm test in
`sim/b8008/interrupt_test_tb.vhdl`, which fires RST 7s into a spinning
taken-jump loop and asserts the exact iteration count survives.

---

## Debugging Interrupt Issues

### Symptom: Simulation works, hardware freezes
- **Cause**: Improper INT sampling point (T1 instead of T3)
- **Cause**: Missing interrupt synchronization
- **Cause**: PC incremented during T1I

### Symptom: Continuous interrupt loop
- **Cause**: Interrupt latch not cleared on acknowledge
- **Cause**: External hardware not seeing T1I state

### Symptom: Random instruction execution
- **Cause**: Interrupt during non-PCI cycle
- **Cause**: External hardware not properly injecting instruction

### Symptom: State machine lockup
- **Cause**: T1/T1I exclusivity violated
- **Cause**: Microcode state corruption

---

## Testing Checklist (all covered)

- [x] Assert INT at various states, verify boundary-only recognition
      (`interrupt_test_tb` + state-timing TB Figure-2 counter-case)
- [x] Verify T1I appears with no intermediate T1
- [x] Confirm the PC slot doesn't increment during T1I
- [x] Simulate external controller jamming RST instructions (all vectors)
- [x] Verify RET returns to the correct address after the handler
- [x] Fire interrupts into a running taken-jump loop; exact iteration
      count survives (Phase-4 storm, 10/10, silicon-validated)
- [x] Apply asynchronous INT via physical DIP switch (debounced one-shot,
      selectable vector) — silicon-validated, including HLT wake

---

## References

- Intel 8008 Datasheet, Revision 1 (April 1972)
- Intel 8008 Datasheet, Revision 2 (November 1972)
- Intel SIM8-01 Reference Design Schematic (Section VII: Interrupt Synchronizer)
