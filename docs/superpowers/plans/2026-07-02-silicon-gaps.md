# Silicon Test-Coverage Gaps Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the 5 untested-silicon gaps: rotate flag fidelity, 8-level stack wraparound, READY/WAIT states, HLT-wake and runtime interrupts via front-panel switch.

**Architecture:** Fix rotate flags in `condition_flags` (new `carry_only` control, same pattern as the INR/DCR carry fix). Add a real S_WAIT state to the state timing generator, expose `ready_in` through `b8008_top`, drive from DIP sw(6). New `int_button.vhdl` turns DIP sw(5) flips into single interrupt requests with sw(7) vector select, OR'd with the bootstrap interrupt. Three new RAM test programs validate on silicon; testbenches validate first in sim.

**Tech Stack:** VHDL-2008 via GHDL (Makefile targets only — NEVER run ghdl directly), AS macro-assembler via `make assemble-sample`, Python 8008 emulator (scratchpad `emu8008.py`) for program pre-verification, Yosys/nextpnr via `projects/project.mk`.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-02-silicon-gaps-design.md`
- NEVER run GHDL directly — always `make` targets (CLAUDE.md).
- Modules stay dumb: no instruction knowledge inside condition_flags/int_button; control signals tell them what to do.
- RAM programs live in 0x2000-0x3EFF, exit `jmp 0`, OUT 9 output with one-frame pacing, IN 1 poll input (docs/RAM_PROGRAMS.md).
- Monitor scratch page 0x3F00-0x3FFF is reserved; RST slots at 0x3FC0+n*8.
- Switch polarity per existing convention: DIP ON = pin low (see `sw(1)` usage at `b8008_monitor_top.vhdl:502`).
- Implementation order: Task 1-3 (rotates) → 4-5 (stack wrap) → 6-8 (READY) → 9-13 (button INT, last per user) → 14 (final build + handoff).
- User is AFK: build everything; the user flashes and runs the silicon checklist afterward. Firmware-only changes use `make rom-update && make prog-flash`; RTL changes need full build.
- Full sim regression `./test_programs/verification_scripts/run_all_tests.sh` must pass before any build is declared ready.

---

### Task 1: Rotate flag fix in condition_flags (RTL + unit TB)

**Files:**
- Modify: `src/b8008/condition_flags.vhdl` (entity port list ~line 45, update process ~line 91)
- Modify: `src/b8008/b8008.vhdl` (component decl ~line 534, instantiation ~line 1316)
- Test: `sim/b8008/condition_flags_tb.vhdl`

**Interfaces:**
- Produces: `condition_flags` port `carry_only : in std_logic` — when '1' during `update_flags`, only `carry_ff` is written; Z/S/P hold. Wired to existing signal `instr_is_rotate` in b8008.vhdl.

- [ ] **Step 1: Write the failing test.** Add to `sim/b8008/condition_flags_tb.vhdl` after the existing update test cases (follow the file's stimulus/assert style, driving `phi2_rising` pulses the way existing cases do):

```vhdl
        -- Rotate fidelity: carry_only='1' must write carry and preserve Z/S/P
        -- Preload flags: C=0 Z=1 S=0 P=1 via a normal update
        flag_carry_in <= '0'; flag_zero_in <= '1'; flag_sign_in <= '0'; flag_parity_in <= '1';
        carry_only <= '0'; update_flags <= '1';
        wait until rising_edge(clk) and phi2_rising = '1'; wait for 1 ns;
        update_flags <= '0';
        -- Rotate-style update: new carry=1, ALU happens to present Z=0 S=1 P=0
        flag_carry_in <= '1'; flag_zero_in <= '0'; flag_sign_in <= '1'; flag_parity_in <= '0';
        carry_only <= '1'; update_flags <= '1';
        wait until rising_edge(clk) and phi2_rising = '1'; wait for 1 ns;
        update_flags <= '0'; carry_only <= '0';
        assert flag_carry = '1' report "carry_only: carry not updated" severity error;
        assert flag_zero = '1'  report "carry_only: zero clobbered" severity error;
        assert flag_sign = '0'  report "carry_only: sign clobbered" severity error;
        assert flag_parity = '1' report "carry_only: parity clobbered" severity error;
```

Also add `carry_only : in std_logic` to the TB's component declaration + a `signal carry_only : std_logic := '0';` + port map entry, mirroring `update_flags`.

- [ ] **Step 2: Add the port to the entity so the TB compiles, with pass-through NOT yet implemented.** In `condition_flags.vhdl` entity, after `update_flags`:

```vhdl
        -- When '1' with update_flags: write carry only, hold Z/S/P
        -- (8008 rotates affect carry alone - control tells us, we stay dumb)
        carry_only : in std_logic;
```

- [ ] **Step 3: Run test to verify it fails.** `make test-condition-flags` — expect the four new asserts: carry updated but "zero clobbered"/"sign clobbered" failures (all four FFs still written).

- [ ] **Step 4: Implement.** In the update process replace the four assignments:

```vhdl
            if phi2_rising = '1' and update_flags = '1' then
                carry_ff <= flag_carry_in;
                if carry_only = '0' then
                    zero_ff   <= flag_zero_in;
                    sign_ff   <= flag_sign_in;
                    parity_ff <= flag_parity_in;
                end if;
```

(keep the report line, move it inside the outer `if`).

- [ ] **Step 5: Run test to verify it passes.** `make test-condition-flags` — all asserts silent, TB reports its normal PASS summary.

- [ ] **Step 6: Wire in b8008.vhdl.** Component declaration for `condition_flags` gains `carry_only : in std_logic;` after `update_flags`; instantiation `u_condition_flags` gains `carry_only => instr_is_rotate,` (signal already exists, declared ~line 654, driven by the instruction decoder).

- [ ] **Step 7: Full unit + system sim check.** `make test-b8008-top` and `./test_programs/verification_scripts/check_rotate_test.sh` — both must pass (existing rotate test checks A + carry values, which are unchanged).

- [ ] **Step 8: Commit.**

```bash
git add src/b8008/condition_flags.vhdl src/b8008/b8008.vhdl sim/b8008/condition_flags_tb.vhdl
git commit -m "b8008: rotates write carry only, Z/S/P preserved per 8008 spec"
```

### Task 2: Rotate-flag assembly regression test

**Files:**
- Create: `test_programs/rotate_flags_test_as.asm`
- Create: `test_programs/verification_scripts/check_rotate_flags_test.sh` (copy structure from `check_rotate_test.sh`)
- Modify: `test_programs/verification_scripts/run_all_tests.sh` (add the new script to the list)

**Interfaces:**
- Consumes: Task 1's RTL fix.
- Produces: regression script name `check_rotate_flags_test.sh` used by Task 14.

- [ ] **Step 1: Write the test program.** The period idiom: set Z with arithmetic, rotate, branch on the preserved Z. Result markers land in registers checked by the verification script. Look at `test_programs/rotate_test_as.asm` first and copy its header/ORG/HLT conventions exactly, then the body:

```asm
; rotate_flags_test: rotates must preserve Z/S/P, update only carry.
        xra a           ; A=0: Z=1 S=0 P=1 C=0
        mvi a,80h       ; MVI does not touch flags; Z still 1
        rlc             ; A=01h, C=1. Broken RTL recomputes Z=0 here.
        jnz FAIL1       ; Z must still be 1
        jnc FAIL1       ; C must be 1 (rotate DID update carry)
        mvi b,0AAh      ; pass marker 1
        jmp T2
FAIL1:  mvi b,0EEh
T2:     mvi a,0FFh
        adi 01h         ; A=0: Z=1 C=1 P=1 S=0
        mvi a,01h
        rar             ; A=80h C=1. Broken RTL: S=1 Z=0 written.
        jnz FAIL2       ; Z preserved?
        jm  FAIL2       ; S preserved (0)?
        mvi c,0AAh      ; pass marker 2
        jmp DONE
FAIL2:  mvi c,0EEh
DONE:   hlt
```

- [ ] **Step 2: Assemble + run + verify fails on old RTL is NOT possible (fix already in) — instead verify the test catches the bug by temporarily reverting.** `make assemble PROG=rotate_flags_test_as.asm`, then run `make test-b8008-top PROG=rotate_flags_test_as` and confirm from the debug register dump B=0xAA, C=0xAA. Then `git stash` (stashes Task 1), rerun, confirm B or C = 0xEE (test proves it detects the bug), `git stash pop`.

- [ ] **Step 3: Write `check_rotate_flags_test.sh`.** Copy `check_rotate_test.sh` verbatim, change PROG name and the expected-value greps to assert `reg_b = 0xAA` and `reg_c = 0xAA` (match the exact debug-output format the other scripts grep for).

- [ ] **Step 4: Run the script + add to `run_all_tests.sh`.** `./test_programs/verification_scripts/check_rotate_flags_test.sh` → PASS. Add one line to `run_all_tests.sh` alongside the other check_* invocations.

- [ ] **Step 5: Full regression.** `./test_programs/verification_scripts/run_all_tests.sh` → all PASS.

- [ ] **Step 6: Commit.**

```bash
git add test_programs/rotate_flags_test_as.asm test_programs/verification_scripts/check_rotate_flags_test.sh test_programs/verification_scripts/run_all_tests.sh
git commit -m "test: rotate flag-preservation regression (asm + script)"
```

### Task 3: Extend hardware selftest ROM (rotate flags + INR carry)

**Files:**
- Modify: `projects/b8008_monitor/selftest_as.asm` (append new group before the final report; helpers `check_a`, `REPORT_PASS` pattern already exist)

**Interfaces:**
- Consumes: `check_a` helper (compares A to expected in E), test auto-numbering via TESTNUM.
- Produces: selftest total goes from 42 to 46; user expects "F=00" on silicon.

- [ ] **Step 1: Read the end of the existing test list** (around T42) and append following the same comment style:

```asm
        ; T43: RLC preserves Z (set via XRA), updates C
        xra a                   ; Z=1 C=0
        mvi a,80h
        rlc                     ; C=1, Z must stay 1
        mvi a,00h
        jnz t43f                ; Z clobbered -> fail
        jnc t43f                ; C not set -> fail
        mvi a,55h
t43f:   mvi e,55h
        call check_a

        ; T44: RAR preserves S=0 and Z=1 from prior ADD
        mvi a,0FFh
        adi 01h                 ; A=0 Z=1 S=0 C=1
        mvi a,01h
        rar                     ; A=80h C=1; S/Z must hold
        mvi a,00h
        jnz t44f
        jm  t44f
        mvi a,55h
t44f:   mvi e,55h
        call check_a

        ; T45: carry survives INR (SCELBAL ADC/INR interleave)
        mvi a,0FFh
        adi 01h                 ; C=1
        mvi l,10h
        inr l                   ; must NOT touch C
        mvi a,00h
        jnc t45f
        mvi a,55h
t45f:   mvi e,55h
        call check_a

        ; T46: carry survives DCR (RAL/DCR rotate-loop idiom)
        xra a                   ; C=0
        mvi a,80h
        ral                     ; C=1
        mvi b,05h
        dcr b                   ; must NOT touch C
        mvi a,00h
        jnc t46f
        mvi a,55h
t46f:   mvi e,55h
        call check_a
```

- [ ] **Step 2: Rebuild selftest ROM in sim.** Find the selftest sim/apply flow: `grep -n selftest projects/b8008_monitor/Makefile`. Assemble per that flow; run the selftest in simulation the same way it was validated for commit 671f680 (monitor Makefile has the rom-freeze/sim path — check `monitor_boot_tb` usage). Expected: `DN P=2E F=00` (46 decimal = 0x2E).

- [ ] **Step 3: Commit.**

```bash
git add projects/b8008_monitor/selftest_as.asm
git commit -m "selftest: T43-T46 rotate flag-preservation + INR/DCR carry cases"
```

### Task 4: Extend Python emulator with 8-slot stack + rotate-flag fidelity

**Files:**
- Modify: scratchpad `emu8008.py` (path: `/private/tmp/claude-501/-Users-hambook-Development-intel-8008-vhdl/bf05ff26-070d-4d4b-9f8d-4ddf3c887565/scratchpad/emu8008.py`) — NOT committed, it's the prediction oracle.

**Interfaces:**
- Produces: emulator models `self.stack` as 8-slot circular buffer (7 usable return slots + PC), so stackwrap predictions match real silicon.

- [ ] **Step 1: Replace the unbounded list stack.** In `CPU.__init__`: `self.stack = [0]*8; self.sp = 0`. Replace every `self.stack.append(x)` with:

```python
    def push(self, x):
        self.sp = (self.sp + 1) % 8
        self.stack[self.sp] = x
    def pop(self):
        v = self.stack[self.sp]
        self.sp = (self.sp - 1) % 8
        return v
```

and `self.stack.pop()` with `self.pop()`. (8008: PC is stack level 0; 7 nested calls safe, 8th wraps onto the oldest.)

- [ ] **Step 2: Sanity check nothing regressed.** Run the calc verification one-liner from this session: `python3 emu8008.py <repo>/test_programs/samples/calc_ram.hex '2 +4 '` → still `+0.6000000E+01`.

### Task 5: Stack wraparound RAM program

**Files:**
- Create: `test_programs/samples/stackwrap_ram.asm`
- Test: emulator run first, then `make sim TEST=monitor_load_tb`-style silicon-equivalent is deferred to user (runs on ANY bitstream).

**Interfaces:**
- Consumes: monitor L/G conventions (ORG 2100H, OUT 9 pacing idiom, jmp 0 exit).
- Produces: silicon checklist item: `G 2100` prints `STACKWRAP 1234567` + `WRAP OK` (exact strings below).

- [ ] **Step 1: Write the program.** Behavior: 8 nested CALLs. Levels 1-7 unwind normally (their returns fit the 7 slots). The 8th CALL overwrites the oldest slot — the return-to-main — so after level 8's RET chain unwinds 7 levels, the final RET lands back at level-8's return point a second time instead of main. A RAM flag detects the second arrival and prints `WRAP OK`.

```asm
            PAGE 0
            cpu 8008new
CR          EQU 0Dh
LF          EQU 0Ah

            ORG 2100H
; STACKWRAP - proves the 8-level (PC + 7 return slots) address stack
; wraps per 8008 spec on the 8th nested CALL.
START:      mvi h,20h            ; flag byte at 0x2000
            mvi l,00h
            mvi m,0
            call PUTS_HDR        ; "STACKWRAP "
            call L1              ; nest 8 deep
; With a wrapping stack we NEVER get here; a too-deep (wrong) stack would.
            mvi a,'B'            ; "BAD" marker - stack deeper than spec
            call PUTC
            mvi a,'A'
            call PUTC
            mvi a,'D'
            call PUTC
            call PUTCRLF
            jmp 0

L1:         mvi a,'1'
            call PUTC
            call L2
            ret
L2:         mvi a,'2'
            call PUTC
            call L3
            ret
L3:         mvi a,'3'
            call PUTC
            call L4
            ret
L4:         mvi a,'4'
            call PUTC
            call L5
            ret
L5:         mvi a,'5'
            call PUTC
            call L6
            ret
L6:         mvi a,'6'
            call PUTC
            call L7
            ret
L7:         mvi a,'7'
            call PUTC
            call L8             ; 8th nested CALL: overwrites return-to-START
RET8:       mvi h,20h           ; we arrive here TWICE: once popping L8's own
            mvi l,00h           ; return, once when the wrapped chain lands
            mov a,m
            ana a
            jnz SECOND
            mvi m,1             ; first arrival: mark and unwind
            ret
SECOND:     mvi a,'W'
            call PUTC
            mvi a,'R'
            call PUTC
            mvi a,'A'
            call PUTC
            mvi a,'P'
            call PUTC
            mvi a,' '
            call PUTC
            mvi a,'O'
            call PUTC
            mvi a,'K'
            call PUTC
            call PUTCRLF
            jmp 0
L8:         mvi a,'8'
            call PUTC
            ret

PUTS_HDR:   mvi a,'S'
            call PUTC
            mvi a,'T'
            call PUTC
            mvi a,'K'
            call PUTC
            mvi a,' '
            call PUTC
            ret
PUTCRLF:    mvi a,CR
            call PUTC
            mvi a,LF
; fall through
PUTC:       out 09h
            mov a,a              ; pacing: ~45us/instr vs 87us frame
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            ret
```

CAREFUL, verify before accepting this analysis: PUTC itself is a CALL — it consumes a stack slot too. At maximum depth (inside L8's PUTC) the nesting is START→L1..L8→PUTC = 9 return addresses against 7 slots. That is deliberate — the emulator (Task 4) is the oracle: run it, observe the actual output pattern, and lock THAT as the expected string in the verification. Adjust the program (e.g., inline the OUT in L7/L8 instead of calling PUTC) until the emulator shows the clean signature: digits `12345678`, then `WRAP OK` reachable ONLY via wraparound, and `BAD` unreachable. The invariant that must hold whatever the final shape: output distinguishes {spec-correct wrap} from {unbounded stack} from {corrupted unwind}.

- [ ] **Step 2: Predict with the emulator.** `python3` + `emu8008.py` load `stackwrap_ram.hex` (after `make assemble-sample PROG=stackwrap_ram`), PC=0x2100, empty input; capture OUT 9. Iterate on Step 1 until the signature is clean. Record the exact expected output string in the asm header comment.

- [ ] **Step 3: Sim on the real RTL.** Follow the `monitor_load_tb` pattern (it loads hex over sim-UART and G-runs it — see `projects/b8008_monitor/sim/monitor_load_tb.vhdl` and its Makefile target). If wiring the new hex in is disproportionate, acceptable fallback: `make test-b8008-top PROG=...` path with the program relocated to ROM org — but then keep the RAM version too; silicon runs the RAM one.

- [ ] **Step 4: Commit.**

```bash
git add test_programs/samples/stackwrap_ram.asm
git commit -m "test: stackwrap_ram - 8-level address-stack wraparound on silicon"
```

### Task 6: S_WAIT state in state timing generator (RTL + TB)

**Files:**
- Modify: `src/b8008/state_timing_generator.vhdl`
- Test: `sim/b8008/state_timing_generator_tb.vhdl`

**Interfaces:**
- Consumes: existing `ready` input port (line 33 — currently ignored by the process).
- Produces: T2→S_WAIT when `ready='0'` at the T2→T3 transition; S_WAIT→T3 when `ready='1'`. Status encoding S2,S1,S0 = 000 in S_WAIT (already documented at line 88). New output unchanged — status lines express WAIT.

- [ ] **Step 1: Failing TB case.** In `state_timing_generator_tb.vhdl` add after existing transition tests (follow the TB's advance/assert helpers):

```vhdl
        -- READY=0 at end of T2 must park the FSM in WAIT (status 000)
        ready <= '0';
        -- ... drive to T2 using the TB's existing sequencing helpers ...
        -- advance one state: expect WAIT, i.e. s2=0 s1=0 s0=0, not T3
        assert (status_s2 = '0' and status_s1 = '0' and status_s0 = '0')
            report "READY=0: expected WAIT after T2" severity error;
        -- hold 3 more advances: still WAIT
        -- release:
        ready <= '1';
        -- advance: expect T3 (s2=0 s1=0 s0=1? use the T3 encoding asserted elsewhere in this TB)
```

Use the exact drive/assert idiom already in the file (it has per-state checks — copy one T2→T3 block and modify).

- [ ] **Step 2: Run to fail.** `make test-state-timing` — WAIT assert fires (FSM goes straight to T3, ready ignored).

- [ ] **Step 3: Implement.** In `state_timing_generator.vhdl`: add `S_WAIT` to `state_t`; in the T2 arm of the next-state process, gate the T3 transition:

```vhdl
            when S_T2 =>
                if advance_state = '1' then
                    if ready = '0' then
                        next_state <= S_WAIT;
                    else
                        next_state <= S_T3;
                    end if;
                end if;

            when S_WAIT =>
                -- Park until memory says ready; status lines read 000 (WAIT)
                if advance_state = '1' and ready = '1' then
                    next_state <= S_T3;
                end if;
```

Add `ready` to the process sensitivity list. Status outputs: S_WAIT must NOT appear in any of the three `status_s*` '1' conditions (000 falls out naturally — verify none of the three lines list S_WAIT). Check every `state_*` output and downstream consumer of the state for completeness (`state_stopped`, `state_t3`, etc. — S_WAIT belongs to none of them).

- [ ] **Step 4: Run to pass.** `make test-state-timing` → PASS including new case.

- [ ] **Step 5: System regression.** `make test-b8008-top` + `./test_programs/verification_scripts/run_all_tests.sh` — ready is tied '1' system-wide today, so nothing may change. All PASS.

- [ ] **Step 6: Commit.**

```bash
git add src/b8008/state_timing_generator.vhdl sim/b8008/state_timing_generator_tb.vhdl
git commit -m "b8008: implement WAIT state - T2 parks while READY low"
```

### Task 7: Expose ready_in through b8008_top

**Files:**
- Modify: `src/b8008/b8008_top.vhdl` (entity ~line 39, hardwire at line 359)

**Interfaces:**
- Produces: `b8008_top` port `ready_in : in std_logic := '1';` — all existing instantiations (testbenches, monitor top) compile unchanged via the default.

- [ ] **Step 1: Add the port.** In the `b8008_top` entity next to `interrupt`:

```vhdl
        ready_in    : in std_logic := '1';  -- READY: '0' parks CPU in WAIT after T2
```

Change line 359 from `ready_in => '1',` to `ready_in => ready_in,`.

- [ ] **Step 2: Verify nothing breaks.** `make test-b8008-top` (uses default) → PASS.

- [ ] **Step 3: System-level WAIT test.** In `sim/b8008/b8008_top_tb.vhdl` add a stimulus: mid-program drop `ready_in` low for 100 us, then raise. Assert: program still completes with correct final register values (reuse whatever end-state check the TB already performs), and during the low window the status lines showed 000 at least once. Run `make test-b8008-top` → PASS.

- [ ] **Step 4: Commit.**

```bash
git add src/b8008/b8008_top.vhdl sim/b8008/b8008_top_tb.vhdl
git commit -m "b8008: expose ready_in on b8008_top (default '1')"
```

### Task 8: Monitor READY wiring — sw(6) freeze switch

**Files:**
- Modify: `projects/b8008_monitor/src/b8008_monitor_top.vhdl` (component decl of b8008_top ~line 96 region, instantiation ~line 555, new sync process near the sw(0) reset sync at ~line 376)

**Interfaces:**
- Consumes: Task 7's port. Polarity: DIP ON = pin low = freeze (matches sw(1) convention).
- Produces: silicon behavior — sw(6) ON freezes CPU mid-instruction, OFF resumes.

- [ ] **Step 1: Wire it.** Add to the b8008_top component declaration in the monitor top: `ready_in : in std_logic := '1';`. Add a 2-FF synchronizer (copy the `reset_sync` process shape at line 376):

```vhdl
    signal ready_sync : std_logic_vector(1 downto 0) := "11";
```

```vhdl
    -- sw(6) = READY hold: ON (low) parks the CPU in WAIT
    process(clk_sys)
    begin
        if rising_edge(clk_sys) then
            ready_sync <= ready_sync(0) & sw(6);
        end if;
    end process;
```

Instantiation: `ready_in => ready_sync(1),`.

- [ ] **Step 2: Confirm sw(6) exists in the LPF and the `sw` port is wide enough.** `grep -n 'sw\[6\]' projects/b8008_monitor/constraints/b8008_monitor.lpf` (present, site per LPF) and check the top's `sw : in std_logic_vector(...)` range covers index 6 — widen if needed (LPF already locates up to sw[7]).

- [ ] **Step 3: Sim smoke.** `make sim TEST=monitor_boot_tb WAVE=0` (or the lightest monitor TB) — boots to banner as before (ready_sync powers up "11" = ready). PASS = unchanged behavior.

- [ ] **Step 4: Commit.**

```bash
git add projects/b8008_monitor/src/b8008_monitor_top.vhdl
git commit -m "monitor: sw(6) READY hold - front-panel WAIT-state freeze"
```

### Task 9: int_button module (RTL + unit TB)

**Files:**
- Create: `src/b8008/int_button.vhdl`
- Create: `sim/b8008/int_button_tb.vhdl`
- Modify: `Makefile` (add `test-int-button` target — copy the `test-condition-flags` recipe shape, and add the new source to the b8008 compile list where the other src/b8008 files are listed)

**Interfaces:**
- Produces:

```vhdl
entity int_button is
    generic (
        CLK_FREQ_HZ : integer := 25_000_000;
        DEBOUNCE_MS : integer := 20
    );
    port (
        clk         : in  std_logic;
        reset       : in  std_logic;                     -- active high
        sw_raw      : in  std_logic;                     -- raw DIP level (async)
        vector_sel  : in  std_logic;                     -- sw(7) sync'd: 0=RST5, 1=RST7
        armed       : in  std_logic;                     -- bootstrap_done: ignore flips before boot
        t1i_ack     : in  std_logic;                     -- '1' during T1I (clears request)
        int_req     : out std_logic;                     -- level, held until t1i_ack
        int_vector  : out std_logic_vector(2 downto 0)   -- "101" or "111", stable while int_req='1'
    );
end entity int_button;
```

Behavior: 2-FF sync sw_raw → debounce (counter, DEBOUNCE_MS) → ANY stable-level change (both flip directions) while `armed='1'` sets the request latch and freezes `int_vector` from `vector_sel`; `t1i_ack='1'` clears the latch. Flips while a request is pending are ignored (no queueing — dumb module).

- [ ] **Step 1: Write the TB first.** `sim/b8008/int_button_tb.vhdl`, clk 25 MHz, generic map `DEBOUNCE_MS => 1` to keep sim short. Cases:

```
1. reset high then low; sw flips 0->1 with armed='0'  -> int_req stays '0'
2. armed='1'; sw flips 1->0 (with 200ns bounce glitches around the edge)
   -> exactly one int_req rise, after the debounce time; vector = "101" (vector_sel=0)
3. int_req stays '1' for >1ms until t1i_ack pulse -> int_req drops
4. sw flips again 0->1 with vector_sel='1' -> int_req rises once, vector "111"
5. two rapid flips inside the debounce window -> still exactly one request
```

Write asserts per case in the style of `interrupt_ready_ff_tb.vhdl` (same directory, same clock-driving idiom).

- [ ] **Step 2: Makefile target.** Copy the `test-condition-flags:` block, rename to `test-int-button`, point at `int_button_tb`, add `int_button.vhdl` to the compile-order list next to `interrupt_ready_ff.vhdl`. Add `test-int-button` to the `.PHONY` line and to `make help` text.

- [ ] **Step 3: Run to fail.** `make test-int-button` — compile error (entity missing) is the expected failure.

- [ ] **Step 4: Implement `int_button.vhdl`.**

```vhdl
library ieee;
use ieee.std_logic_1164.all;

entity int_button is
    generic (
        CLK_FREQ_HZ : integer := 25_000_000;
        DEBOUNCE_MS : integer := 20
    );
    port (
        clk        : in  std_logic;
        reset      : in  std_logic;
        sw_raw     : in  std_logic;
        vector_sel : in  std_logic;
        armed      : in  std_logic;
        t1i_ack    : in  std_logic;
        int_req    : out std_logic;
        int_vector : out std_logic_vector(2 downto 0)
    );
end entity int_button;

architecture rtl of int_button is
    constant DEBOUNCE_CYCLES : integer := (CLK_FREQ_HZ / 1000) * DEBOUNCE_MS;
    signal sw_sync   : std_logic_vector(1 downto 0) := "11";
    signal sw_stable : std_logic := '1';
    signal counter   : integer range 0 to DEBOUNCE_CYCLES := 0;
    signal req_ff    : std_logic := '0';
    signal vec_ff    : std_logic_vector(2 downto 0) := "101";
begin
    process(clk, reset)
    begin
        if reset = '1' then
            sw_sync   <= "11";
            sw_stable <= '1';
            counter   <= 0;
            req_ff    <= '0';
        elsif rising_edge(clk) then
            sw_sync <= sw_sync(0) & sw_raw;

            if sw_sync(1) = sw_stable then
                counter <= 0;
            elsif counter < DEBOUNCE_CYCLES then
                counter <= counter + 1;
            else
                sw_stable <= sw_sync(1);   -- accepted flip (either direction)
                counter   <= 0;
                if armed = '1' and req_ff = '0' then
                    req_ff <= '1';
                    if vector_sel = '1' then
                        vec_ff <= "111";   -- RST 7
                    else
                        vec_ff <= "101";   -- RST 5
                    end if;
                end if;
            end if;

            if t1i_ack = '1' then
                req_ff <= '0';
            end if;
        end if;
    end process;

    int_req    <= req_ff;
    int_vector <= vec_ff;
end architecture rtl;
```

- [ ] **Step 5: Run to pass.** `make test-int-button` → all 5 cases PASS.

- [ ] **Step 6: Commit.**

```bash
git add src/b8008/int_button.vhdl sim/b8008/int_button_tb.vhdl Makefile
git commit -m "b8008: int_button - debounced DIP flip to one-shot interrupt request"
```

### Task 10: Monitor wiring — button INT into the CPU

**Files:**
- Modify: `projects/b8008_monitor/src/b8008_monitor_top.vhdl` (bootstrap interrupt area ~line 512-560)

**Interfaces:**
- Consumes: `int_button` entity (Task 9), existing signals `bootstrap_int`, `bootstrap_done`, `s0_sig/s1_sig/s2_sig`, `clk_sys`, `reset_int`, `sw`.
- Produces: CPU `interrupt` = bootstrap OR button; `int_vector` = "000" during bootstrap else button vector.

- [ ] **Step 1: Determine the T1I status decode.** T1I ack: same term `b8008_top.vhdl:594` uses for the jam: `s2='1' and s1='1' and s0='0'`. Build it from the monitor's `s0_sig/s1_sig/s2_sig` copies:

```vhdl
    signal t1i_ack_sig : std_logic;
    signal btn_int_req : std_logic;
    signal btn_int_vec : std_logic_vector(2 downto 0);
```

```vhdl
    t1i_ack_sig <= '1' when (s2_sig = '1' and s1_sig = '1' and s0_sig = '0') else '0';

    u_int_button : entity work.int_button
        generic map ( CLK_FREQ_HZ => 25_000_000, DEBOUNCE_MS => 20 )
        port map (
            clk        => clk_sys,
            reset      => reset_int,
            sw_raw     => sw(5),
            vector_sel => sw(7),
            armed      => bootstrap_done,
            t1i_ack    => t1i_ack_sig,
            int_req    => btn_int_req,
            int_vector => btn_int_vec
        );
```

VERIFY the T1I encoding against `state_timing_generator.vhdl` status tables before trusting line 594's term (S_T1I: check which of `status_s0/s1/s2` list S_T1I — derive the 3-bit code from lines 88-91) — if they disagree, the state_timing table is the truth.

- [ ] **Step 2: Mux into the CPU instantiation.** Replace `interrupt => bootstrap_int,` / `int_vector => "000",` with:

```vhdl
            interrupt   => bootstrap_int or btn_int_req,
            int_vector  => btn_int_vec when bootstrap_done = '1' else "000",
```

If the tool rejects a conditional in a port map, introduce `signal cpu_int_vec : std_logic_vector(2 downto 0);` + concurrent assignment above and map that.

- [ ] **Step 3: Sim: HLT wake + mid-execution.** Extend `sim/b8008/interrupt_test_tb.vhdl` (it already drives the CPU `interrupt` input): add a case where the ROM program executes HLT, TB waits 50 us, asserts the CPU is in STOPPED (status 011 per state_timing line 81), pulses interrupt with `int_vector => "101"`, then asserts execution resumed and the RST 5 handler ran (check via the RAM byte the handler writes — extend the TB's existing program/checks in the same style). Run via its make target (`grep interrupt_test Makefile` for the target name; add one if missing, copying test-b8008-top's shape).

- [ ] **Step 4: Monitor boot regression.** `make sim TEST=monitor_boot_tb WAVE=0` — bootstrap must still jam RST 0 exactly as before (button unarmed until bootstrap_done). PASS = banner unchanged.

- [ ] **Step 5: Commit.**

```bash
git add projects/b8008_monitor/src/b8008_monitor_top.vhdl sim/b8008/interrupt_test_tb.vhdl
git commit -m "monitor: sw(5) front-panel interrupt, sw(7) vector select (RST5/RST7)"
```

### Task 11: hltwake_ram test program

**Files:**
- Create: `test_programs/samples/hltwake_ram.asm`

**Interfaces:**
- Consumes: monitor RST slots (RST5=0x3FE8, RST7=0x3FF8 — 0x3FC0+n*8), OUT 9 pacing idiom, jmp 0 exit.
- Produces: silicon checklist: `G 2100` → `SLEEPING`, flip sw(5) → `WOKE5 RESUMED` (sw(7) OFF) / `WOKE7 RESUMED` (ON).

- [ ] **Step 1: Write it.**

```asm
            PAGE 0
            cpu 8008new
CR          EQU 0Dh
LF          EQU 0Ah

            ORG 2100H
; HLTWAKE - HLT parks the CPU in STOPPED; a front-panel interrupt (sw5)
; jams RST 5/7, the handler prints its identity, RET resumes at HLT+1.
START:      mvi h,3Fh            ; install RST 5 slot: jmp H5
            mvi l,0E8h           ; 0x3FC0 + 5*8
            mvi m,44h            ; JMP
            inr l
            mvi m,H5 & 0FFh
            inr l
            mvi m,H5 / 100h
            mvi l,0F8h           ; RST 7 slot: jmp H7
            mvi m,44h
            inr l
            mvi m,H7 & 0FFh
            inr l
            mvi m,H7 / 100h

            mvi a,'S'
            call PUTC
            mvi a,'L'
            call PUTC
            mvi a,'E'
            call PUTC
            mvi a,'E'
            call PUTC
            mvi a,'P'
            call PUTC
            hlt                  ; <- flip sw(5) to wake
            mvi a,'R'            ; resumes HERE (HLT+1) after handler RET
            call PUTC
            mvi a,'E'
            call PUTC
            mvi a,'S'
            call PUTC
            mvi a,'U'
            call PUTC
            mvi a,'M'
            call PUTC
            call PUTCRLF
            jmp 0

H5:         mvi a,'W'
            call PUTC
            mvi a,'5'
            call PUTC
            ret                  ; return address = HLT+1 (pushed by jammed RST)
H7:         mvi a,'W'
            call PUTC
            mvi a,'7'
            call PUTC
            ret

PUTCRLF:    mvi a,CR
            call PUTC
            mvi a,LF
PUTC:       out 09h
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            ret
```

Expected serial output: `SLEEP` … (flip) … `W5RESUM` (or `W7RESUM`).

- [ ] **Step 2: Emulator check of everything except the interrupt** (emulator has no INT): temporarily assemble a variant with `hlt` replaced by `rst 5` to prove handler/slot/RET plumbing, run in emulator, expect `SLEEPW5RESUM`. Revert to `hlt`.

- [ ] **Step 3: Assemble the real one.** `make assemble-sample PROG=hltwake_ram` → hex exists. Full interrupt path is covered by Task 10's sim TB; silicon run is the user's checklist item.

- [ ] **Step 4: Commit.**

```bash
git add test_programs/samples/hltwake_ram.asm
git commit -m "samples: hltwake_ram - front-panel HLT wake test (RST5/RST7)"
```

### Task 12: intstorm_ram test program

**Files:**
- Create: `test_programs/samples/intstorm_ram.asm`

**Interfaces:**
- Consumes: same conventions as Task 11.
- Produces: silicon checklist: counter stream `00 01 02 ...` (hex), `!` interleaves on each sw(5) flip, sequence unbroken; any UART char exits.

- [ ] **Step 1: Write it.**

```asm
            PAGE 0
            cpu 8008new
CR          EQU 0Dh
LF          EQU 0Ah

            ORG 2100H
; INTSTORM - main loop prints an incrementing hex counter; sw(5) flips
; interrupt mid-loop, handler prints '!' and returns. Unbroken counter
; sequence proves register/PC preservation across jammed RSTs.
; NOTE: handler clobbers nothing - it saves/restores A via RAM because
; the 8008 has no push. B holds the counter and is never touched by PUTC.
START:      mvi h,3Fh            ; RST 5 slot -> BANG
            mvi l,0E8h
            mvi m,44h
            inr l
            mvi m,BANG & 0FFh
            inr l
            mvi m,BANG / 100h
            mvi l,0F8h           ; RST 7 slot -> BANG too
            mvi m,44h
            inr l
            mvi m,BANG & 0FFh
            inr l
            mvi m,BANG / 100h
            mvi b,0              ; the counter

LOOP:       in 1                 ; any typed char = exit
            rlc
            jc DONE
            mov a,b              ; print B as two hex digits
            rrc
            rrc
            rrc
            rrc
            call NIB
            mov a,b
            call NIB
            mvi a,' '
            call PUTC
            inr b
            mvi c,0FFh           ; ~0.1s pause so the stream is readable
PAUSE:      mvi d,0FFh
P2:         dcr d
            jnz P2
            dcr c
            jnz PAUSE
            jmp LOOP

DONE:       jmp 0

NIB:        ani 0Fh
            adi '0'
            cpi '9'+1
            jc PUTC              ; jc = jump if <= '9' ... carry from cpi
            adi 7                ; 'A'-'9'-1
PUTC:       out 09h
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            ret

; interrupt handler: A is live in the main loop - preserve it in RAM.
BANG:       mvi h,20h            ; scratch at 0x2000 (program is at 0x21xx)
            mvi l,00h
            mov m,a              ; save A
            mvi a,'!'
            out 09h
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,m              ; restore A
            ret
```

CAREFUL: the handler also clobbers H and L (needed for the RAM save). The main loop uses H/L only inside START (slot install). Verify that holds — if a future edit adds H/L use to the loop, the handler must save them too (to 0x2001/0x2002 via a different addressing dance). Also NIB's `jc PUTC` after `cpi '9'+1`: 8008 CPI sets carry when A < operand — digits 0-9 take the jump, A-F fall through to the +7 adjust. Verify in the emulator (Step 2), not by trusting this comment.

- [ ] **Step 2: Emulator verification.** Assemble; in the emulator run with empty input for ~200k cycles: expect `00 01 02 03 ...` sequence. Then a variant run injecting `rst 5` semantics is not possible without an INT model — instead temporarily insert `rst 5` between `inr b` and the pause in a scratch copy, rerun: expect `!` between counts AND the count sequence unbroken. Discard the scratch copy.

- [ ] **Step 3: Assemble final.** `make assemble-sample PROG=intstorm_ram`.

- [ ] **Step 4: Commit.**

```bash
git add test_programs/samples/intstorm_ram.asm
git commit -m "samples: intstorm_ram - runtime interrupt storm test"
```

### Task 13: LPF + docs touch-up

**Files:**
- Modify: `projects/b8008_monitor/constraints/b8008_monitor.lpf` (verify only — sw[5..7] already located)
- Modify: `docs/RAM_PROGRAMS.md` (document sw(5)/sw(6)/sw(7) and the two new INT test programs)
- Modify: `projects/b8008_monitor/src/b8008_monitor_top.vhdl` header comment block (the port-map comment at the top listing IN 1/OUT 9 etc. — add the switch table)

**Interfaces:** none new.

- [ ] **Step 1:** Confirm `sw[5]`, `sw[6]`, `sw[7]` LOCATE lines exist in the LPF and the top-level `sw` port width covers them (should already: LPF locates 8). No change expected; fix if reality disagrees.

- [ ] **Step 2:** Append to `docs/RAM_PROGRAMS.md`:

```markdown
## Front-panel switches (SW3 DIP bank)

| Switch | Function |
|---|---|
| sw(5) | Interrupt trigger: any flip = one debounced interrupt (armed after boot) |
| sw(6) | READY hold: ON = CPU parked in WAIT state, OFF = resume |
| sw(7) | Interrupt vector: OFF = RST 5, ON = RST 7 |

Interrupt test programs: `hltwake_ram` (G 2100 - HLT wake), `intstorm_ram`
(G 2100 - mid-execution interrupts; any typed char exits).
```

- [ ] **Step 3: Commit.**

```bash
git add docs/RAM_PROGRAMS.md projects/b8008_monitor/src/b8008_monitor_top.vhdl projects/b8008_monitor/constraints/b8008_monitor.lpf
git commit -m "docs: front-panel switch map + INT test program usage"
```

### Task 14: Final build + silicon handoff

**Files:** none new — build artifacts.

- [ ] **Step 1: Full regression one more time.** `./test_programs/verification_scripts/run_all_tests.sh` → all PASS. `make test-int-button test-state-timing test-condition-flags test-b8008-top` → PASS.

- [ ] **Step 2: Build the bitstream.** `cd projects/b8008_monitor && make clean && make build 2>&1 | tail -40`. Then the mandatory distrust-the-quiet-build greps (2026-07-02 next-steps lesson):

```bash
grep -c EHXPLLL reports/pnr.txt          # expect 1
grep -E 'Max frequency|FAIL' reports/timing.txt   # all PASS
grep -m3 -iE '^ERROR' reports/synthesis.txt       # nothing
```

- [ ] **Step 3: Assemble all new programs fresh.** `make assemble-sample PROG=stackwrap_ram`, `PROG=hltwake_ram`, `PROG=intstorm_ram` — hex files present.

- [ ] **Step 4: Write the handoff message** with the user's silicon checklist (spec section "Validation checklist"): flash command, selftest expectation `DN P=2E F=00`, calc spot-check, the three G-runs with expected strings, sw(6) freeze demo. Do NOT flash — user does hardware actions.

- [ ] **Step 5: Commit anything outstanding; do not push.**

## Self-Review Notes

- Spec coverage: gap 4 = Tasks 1-3; gap 3 = Tasks 4-5; gap 5 = Tasks 6-8; gaps 1-2 = Tasks 9-12; batching/handoff = Task 14. Build 1/Build 2 split from the spec collapsed into one final build per the user's "all built right away" — isolation preserved by per-task sim regressions instead.
- Stack-wrap program marked explicitly as oracle-driven (Task 5 Step 1 caveat) because PUTC calls consume stack slots; the emulator decides the final expected string.
- T1I status decode flagged for verification against state_timing tables (Task 10 Step 1) rather than trusted from one line.
- Type consistency: `int_button` port names used identically in Tasks 9/10; `ready_in` name identical in Tasks 7/8.
