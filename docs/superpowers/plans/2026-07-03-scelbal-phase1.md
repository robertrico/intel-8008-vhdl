# SCELBAL Phase 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** SCELBI BASIC (SCELBAL) running RAM-resident under the b8008_monitor — `G 2000` → BASIC prompt on silicon.

**Architecture:** Grow RAM to cover 0x1000-0x3FFF (decoder generics + 16K BRAM), port Jim Loos's AS-assembler SCELBAL as the seventh loadable sample: variable-page EQUs retargeted to 0x1000-0x13FF, program buffer 0x1400-0x1FFF, bitbang I/O replaced with the monitor USART shims, init-image pages re-ORG'd clear of monitor scratch. Emulator oracle runs full BASIC sessions before silicon.

**Tech Stack:** VHDL-2008/GHDL via make targets only; AS macro-assembler via `make assemble-sample`; Python emulator oracle at scratchpad `emu8008.py`; source `scelbal_jim.asm` already downloaded to the scratchpad from github.com/jim11662418/8008-SBC.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-07-03-scelbal-design.md`
- NEVER run GHDL directly — make targets only (CLAUDE.md).
- SCELBAL I/O contract (from the source header): I/O routines may use ONLY A and B, at most two nesting levels, and CPRINT must preserve the character in A. CINP must ECHO input and return the char with MSB set.
- Monitor scratch page 0x3F00-0x3FFF must stay untouched by SCELBAL content.
- Commit-only-proven: RTL/gateware commits marked SILICON QA PENDING until the user flashes; sim-only artifacts commit normally.

---

### Task 1: Grow RAM to 0x1000-0x3FFF (12K usable)

**Files:**
- Modify: `src/b8008/b8008_top.vhdl` (u_ram ~line 391, u_decode ~line 424, rom comment)
- Test: existing suite (`run_all_tests.sh`), boot sim

**Interfaces:**
- Produces: address map ROM 0x0000-0x0FFF, RAM 0x1000-0x3FFF. All existing programs (ORG ≤ 0x0FFF ROM tests, ORG ≥ 0x2000 RAM samples) unaffected.

- [ ] **Step 1: Decoder + RAM generics.** In `b8008_top.vhdl`:

```vhdl
    u_ram : ram_sync
        generic map (
            ADDR_BITS => 14        -- 16K array; decoder exposes 0x1000-0x3FFF
        )
        port map (
            CLK      => clk_in,
            ADDR     => latched_address(13 downto 0),
            ...
```

```vhdl
    u_decode : address_decoder
        generic map (
            ROM_LAST => 16#0FFF#,  -- firmware is 1.5K in a 4K BRAM ROM
            RAM_BASE => 16#1000#,
            RAM_LAST => 16#3FFF#
        )
```

Also update the ram_byte_0 shadow compare to `latched_address(13 downto 0) = "00000000000000"` and the header comments (RAM now 0x1000-0x3FFF).

- [ ] **Step 2: Full regression.** `./test_programs/verification_scripts/run_all_tests.sh` → 28/28 (ROM tests live below 0x1000, RAM tests at 0x2000+ — nothing moves).

- [ ] **Step 3: Monitor boot sim.** `cd projects/b8008_monitor && make sim TEST=monitor_boot_tb WAVE=0` → PASSED.

- [ ] **Step 4: Commit** (`SILICON QA PENDING` note in message):

```bash
git add src/b8008/b8008_top.vhdl
git commit -m "b8008: RAM grows to 0x1000-0x3FFF (12K) for SCELBAL"
```

### Task 2: Create scelbal_ram.asm (the port)

**Files:**
- Create: `test_programs/samples/scelbal_ram.asm` (from scratchpad `scelbal_jim.asm`)

**Interfaces:**
- Consumes: Task 1's map.
- Produces: `make assemble-sample PROG=scelbal_ram` → hex loadable at 0x2000-0x3EFF, entry `G 2000`.

- [ ] **Step 1: Copy source in.** `cp <scratchpad>/scelbal_jim.asm test_programs/samples/scelbal_ram.asm`, add a provenance header (jim11662418/8008-SBC, b8008 port transformations listed).

- [ ] **Step 2: Retarget the memory EQUs** (around line 273):

```asm
OLDPG1      EQU 1000H             ; b8008: RAM begins at 0x1000
OLDPG26     EQU 1100H
OLDPG27     EQU 1200H
OLDPG57     EQU 1300H
BGNPGRAM    EQU 14H               ; user BASIC programs 0x1400-0x1FFF (3KB)
ENDPGRAM    EQU 20H
```

- [ ] **Step 3: Re-ORG the init images clear of monitor scratch.** `page1: ORG 3D00H` stays, `page26: ORG 3E00H` stays, `page27: ORG 3F00H` → **`ORG 3C00H`** (verify from the .lst that interpreter code ends below 0x3C00 — if not, shift all three images down one page and re-verify). The entry copy loops use `hi(page27)` so no other edit.

- [ ] **Step 4: Replace the I/O block.** Delete the bitbang block (CINP/getbitecho/delay/delay1/CPRINT/putbit and the `out 08/09` serial init at entry) and substitute the monitor idiom, honoring the A/B-only contract:

```asm
INPORT      equ 1                   ; monitor USART RX: bit7=ready, bits6:0=data
OUTPORT     equ 09H                 ; monitor USART TX

; character input for SCELBAL: wait, ECHO, return char with MSB set.
; uses A only (B untouched - exceeds the A+B contract).
CINP:       in INPORT
            rlc                     ; ready flag into carry
            jnc CINP                ; not ready - poll
            rrc                     ; undo rotate, byte intact
            ori 80H                 ; SCELBAL wants MSB set
            mov b,a                 ; keep char (B is ours by contract)
            ani 7FH
            out OUTPORT             ; echo
            mov a,a                 ; pacing: ~45us/instr vs 87us frame
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,b                 ; return MSB|char in A
            ret

; character output for SCELBAL: print A, PRESERVE A. uses A and B.
CPRINT:     mov b,a                 ; save (contract: CPRINT preserves A)
            ani 7FH
            out OUTPORT
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,b                 ; restore the character
            ret
```

Wire whatever names the interpreter body calls (`CINPUT: JMP CINP` style vectors already exist ~line 542 — keep them; also `puts` for the banner must route through CPRINT). Entry keeps the title print and page copies; drop the `out 08`/`out 09` LED+mark init lines.

- [ ] **Step 5: Audit every caller of the replaced routines.** `grep -n 'CINP\|CPRINT\|puts' scelbal_ram.asm` — confirm no caller expects side effects of the old routines beyond the documented contract (the pi-cout lesson). Note findings as comments in the file header.

- [ ] **Step 6: Assemble.** `make assemble-sample PROG=scelbal_ram` → hex + lst produced; grep the .lst: no code above 0x3EFF except nothing; images at 0x3C00-0x3EFF; entry at 0x2000.

- [ ] **Step 7: Commit** (sim-only artifact so far):

```bash
git add test_programs/samples/scelbal_ram.asm
git commit -m "samples: SCELBAL port - RAM-resident BASIC under the monitor"
```

### Task 3: Emulator oracle - full BASIC session

**Files:**
- Modify: scratchpad `emu8008.py` only if gaps surface (16K MEM already).
- Create: scratchpad `scelbal_session.py` (throwaway driver, not committed).

**Interfaces:**
- Consumes: `scelbal_ram.hex`, emulator CPU class (IN 1 = 0x80|char pop, OUT 9 capture).

- [ ] **Step 1: Write the session driver.**

```python
import sys
sys.path.insert(0, '<scratchpad>')
import emu8008 as E
E.load_hex('test_programs/samples/scelbal_ram.hex')
session = 'SCR\r10 PRINT "HELLO WORLD"\r20 GOTO 10\rLIST\rRUN\r'
cpu = E.CPU(0x2000, session)
while not cpu.halted and cpu.cycles < 60_000_000:
    if not cpu.inbuf and len(cpu.out) > 2000:
        break     # RUN loop streaming - enough evidence
    cpu.step()
print(''.join(chr(c) if 32 <= c < 127 or c in (10,13) else '' for c in cpu.out))
```

- [ ] **Step 2: Run and iterate.** Expected transcript: title banner, `READY` prompts, LIST shows both lines, RUN prints `HELLO WORLD` repeatedly. Any failure: diff emulator behavior against the port edits (EQUs, shims) — the oracle isolates port bugs from CPU bugs by definition. Fix `scelbal_ram.asm`, reassemble, rerun until the session is clean.

- [ ] **Step 3: Arithmetic smoke.** Second session: `SCR\rPRINT 2+2\rPRINT 355/113\rPRINT INT(10*RND(1))\r` — expect `4`, `3.14159...`-ish, digit. Exercises the FP package end to end.

- [ ] **Step 4: Amend the Task 2 commit** with any port fixes; record the passing transcript (trimmed) in the asm header comment.

### Task 4: Regression + bitstream

**Files:** build artifacts only.

- [ ] **Step 1:** `./test_programs/verification_scripts/run_all_tests.sh` → 28/28.
- [ ] **Step 2:** `cd projects/b8008_monitor && make clean && make build` + the three distrust greps (EHXPLLL=1, timing PASS, no ERROR).
- [ ] **Step 3:** Boot + load sims: `make sim TEST=monitor_boot_tb WAVE=0`, `make sim TEST=monitor_load_tb SIM_TIME=1000ms WAVE=0` → both PASSED.

### Task 5: Silicon handoff (user)

- [ ] **Step 1:** Hand over:

```
cd projects/b8008_monitor && make prog-flash          # 12K-RAM bitstream
./send_hex.py test_programs/samples/scelbal_ram.hex   # ~2 min, period-appropriate
# minicom: G 2000
SCR
10 PRINT "HELLO WORLD"
20 GOTO 10
RUN
```

Expected: banner → READY → the loop streaming until any key/reset. Then the sample set spot-check (calc `G 2100`, pi `G 2040`) to confirm the map change broke nothing.

- [ ] **Step 2:** On user confirmation: mark commits silicon-validated, update memory, close Phase 1. Phase 2 (`b8008_basic`, boot-to-BASIC + MON keyword) gets its own spec.

## Self-Review Notes

- Spec coverage: map change = Task 1; port = Task 2; oracle ladder = Task 3; regression/build = Task 4; silicon = Task 5. Phase 2 explicitly out of scope.
- The 0x3C00 image placement carries a verify-from-lst gate rather than a trusted assumption.
- CINP echo requirement (SCELBAL expects echo-on-input) is encoded in the shim, not left to memory.
