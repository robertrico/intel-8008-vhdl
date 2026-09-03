# Writing, Loading, and Running RAM Programs on the b8008 Monitor

The monitor turns the b8008 into a classic load-and-go machine: write an
assembly program against the memory map below, assemble it to Intel HEX,
stream it into RAM over serial with `L`, and run it with `G addr`. This is
how the SCELBI Mandelbrot and the other `test_programs/samples/*_ram.asm`
ports run.

## Memory map

| Range           | Owner        | Notes                                          |
|-----------------|--------------|------------------------------------------------|
| 0x0000 - 0x1FFF | Monitor ROM  | Read-only. RST 0 boots the monitor.            |
| 0x2000 - 0x3EFF | **Your program** | Code + data, loaded via `L`.               |
| 0x3F00 - 0x3FBF | Monitor scratch | Reserved (command buffer, parser, loader vars, G trampoline at 0x3F80). |
| 0x3FC0 - 0x3FFE | RST vector slots | Yours to install handlers in (see below).  |
| 0x3FFF          | **LED register** | Plain RAM, also shadowed to the LEDs: bit n -> LED n, 1 = on, bit 0 unused (LED0/D25 = CPU running). `W 3FFF,FE` / `W 3FFF,00`. |

Programs execute from RAM, so self-modifying code and inline data (the
SCELBI style) work fine.

## I/O conventions

**Output** - `OUT 9` sends one byte through the USART at 115200 baud
immediately. The USART has no TX queue: pace successive characters with a
~40-instruction delay loop (one 115200 frame is ~87 us; the 8008 runs at
~45 us/instruction):

```asm
ECHO:   ANI     7FH             ; optional: strip MSB (SCELBI convention)
        OUT     09H
        MVI     B,14H           ; ~40 instructions > one character frame
ECHODLY:DCR     B
        JNZ     ECHODLY
        RET
```

**Input** - `IN 1` reads the USART receiver: bit 7 = ready flag (cleared
by the read itself), bits 6:0 = the character. Poll until ready:

```asm
GETCH:  IN      1
        MOV     B,A
        ANI     80H
        JZ      GETCH
        MOV     A,B
        ANI     7FH             ; A = 7-bit character
        RET                     ; add ORI 80H if your code expects MSB set
```

**LEDs** - write RAM `0x3FFF`: bit n lights LED n (1 = on); bit 0 is
ignored because LED0 (D25) is the CPU-running light. From the monitor,
`W 3FFF,FE` turns all seven on, `W 3FFF,F0` the four reds, `W 3FFF,00`
off; `D 3FFF` reads back. `OUT 8` is latched by the core but not displayed
on this board.

## RST instructions

RST 1-7 call fixed ROM addresses the monitor owns; each ROM vector
forwards to an 8-byte RAM slot at `0x3FC0 + n*8`:

RST1=0x3FC8, RST2=0x3FD0, RST3=0x3FD8, RST4=0x3FE0,
RST5=0x3FE8, RST6=0x3FF0, RST7=0x3FF8.

Install a handler before using one (RST pushes the return PC like a CALL,
so a handler ending in RET just works):

```asm
        MVI     H,3FH           ; RST 7 slot
        MVI     L,0F8H
        MVI     M,44H           ; JMP opcode
        INR     L
        MVI     M,HANDLER&0FFH
        INR     L
        MVI     M,(HANDLER>>8)&0FFH
```

Uninstalled slots read as 0x00 = HLT, so a stray RST freezes the CPU
instead of running wild. Smallest working example:
`test_programs/samples/rst_probe_ram.asm` (prints "RQ").

## Entry and exit

- Entry: whatever address you `G`. No reset vector needed in your program.
- Exit: `JMP 0` restarts the monitor (banner + prompt). `HLT` freezes the
  CPU until the reset switch.
- The 8008 stack is an 8-deep ring inside the CPU; you arrive from the
  monitor with a couple of abandoned frames on it. Only relative call
  depth matters - stay within ~6 nested calls.

## Skeleton

```asm
        cpu     8008new
        page    0

OUTPORT equ     09H

        org     2000h           ; anywhere in 0x2000-0x3EFF
START:
        MVI     A,'!'
        CALL    ECHO
        JMP     0               ; back to the monitor

ECHO:   ANI     7FH
        OUT     OUTPORT
        MVI     B,14H
ECHODLY:DCR     B
        JNZ     ECHODLY
        RET

        end
```

If your code addresses data page-locally (`MVI H,page` once, then
`MVI L,offset`), keep each data block within one 256-byte page - see
`mandelbrot_ram.asm` (org 0x2040 preserves the original's page offsets).

## Assemble, load, run

```sh
# assemble (file in test_programs/samples/)
make assemble-sample PROG=myprog

# from projects/b8008_monitor: kill minicom, stream into RAM, jump
make send-hex HEX=myprog.hex GO=2000

# reattach the console
make monitor
```

Or by hand: `./send_hex.py test_programs/samples/myprog.hex --go 2000` from
the repo root, with minicom closed first (one process owns the port;
`make kill-monitor` in `projects/b8008_monitor` does that). Without `--go`,
type `G 2000` at the monitor prompt after reattaching.

`send_hex.py` paces characters (the USART buffers exactly one RX byte),
prints the monitor's `.` per record and the OK/ERR verdict, and refuses to
proceed if any record failed - just rerun it (records are
absolute-addressed, reloading is idempotent). `D addr,n` dumps memory to
spot-check the load; `W addr,val` patches single bytes.

## Front-panel switches (SW3 DIP bank)

**Only DIP1 is connected: ON = run, OFF = reset.** (DIP ON = logic '0'.)
Since 2026-09-03 `sw(1..7)` are no-connects in both board tops: no LED
debug-capture modes, no switch-driven interrupts, no READY hold, no
post-bootstrap break. The interrupt and READY hardware tests that used
sw(5)/sw(6)/sw(7) need those lines re-wired in the top to run again.

Front-panel demo:

- `cylon_ram` - `G 2100`, Knight Rider sweep across the seven user LEDs via
  the memory-mapped LED byte at 0x3FFF. Any typed character exits to the monitor.

Interrupt test programs (install their own RST 5/7 slot handlers):

- `hltwake_ram` - `G 2100`, prints `SLEEP`, HLTs; flip sw(5) ->
  `W5RESUM` (or `W7RESUM` with sw(7) on) and back to the monitor.
- `intstorm_ram` - `G 2100`, streams a hex counter; each sw(5) flip
  interleaves a `!` with the counter sequence unbroken. Any typed
  character exits to the monitor.
- `stackwrap_ram` - `G 2100`, no switches: prints which address-stack
  architecture the CPU has (`STK 12345678 WRAP OK` = real-8008 wrap,
  `STK 123456788RET` = b8008's current split-PC design).
