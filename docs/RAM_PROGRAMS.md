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
| 0x3FC0 - 0x3FFF | RST vector slots | Yours to install handlers in (see below).  |

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

**LEDs** - `OUT 8` drives the LED bank (active low).

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

# stream it into RAM (kill minicom first - one process owns the port)
./send_hex.py test_programs/samples/myprog.hex

# reattach minicom, then at the monitor prompt:
G 2000
```

`send_hex.py` paces characters (the USART buffers exactly one RX byte),
prints the monitor's `.` per record and the OK/ERR verdict, and refuses to
proceed if any record failed - just rerun it (records are
absolute-addressed, reloading is idempotent). `D addr,n` dumps memory to
spot-check the load; `W addr,val` patches single bytes.
