# Sample Programs

This directory contains "real world" Intel 8008 programs collected from historical sources. These are used to validate that the b8008 implementation can run actual period software, not just synthetic test cases.

## Programs

### calc.asm - SCELBI Floating Point Calculator (1974)

A 4-function floating point calculator demonstrated by Nat Wadsworth and Robert Findley to potential investors for SCELBI Computer Consulting. Published in "Machine Language Programming for the '8008' and Similar Microcomputers".

**Features:**
- Floating point add, subtract, multiply, divide
- Decimal input/output conversion
- Complete floating point library in under 2KB

**Testing without serial hardware:**

This program uses bit-banged serial I/O at 2400 bps N-8-1. To test in simulation without serial hardware, replace the `INPUT` and `ECHO` routines (at addresses 0x720 and 0x740) with simple port-based I/O:

```asm
INPUT:  in 0        ; read character from port 0
        ori 80h     ; set MSB (program expects this)
        ret

ECHO:   ani 7fh     ; clear MSB
        out 08h     ; write character to port 8
        ret
```

Then modify the testbench to:
1. Provide input characters on port 0 reads
2. Capture output characters from port 8 writes

Alternatively, create a standalone test that hardcodes two floating point values in FPACC (0x54-0x57) and FPOP (0x5C-0x5F), calls the math routines directly, and halts with the result.

---

### mandelbrot.asm - 1K Floating-Point Mandelbrot Grapher (2013)

Written by Mark G. Arnold using floating point routines from SCELBAL. Renders an ASCII Mandelbrot set in under 1KB of code.

**Features:**
- Uses SCELBAL floating point library (add, subtract, multiply)
- Outputs 21 rows x 61 columns of ASCII art
- Entry point at 0x0040, halts when complete

**Testing without serial hardware:**

This program is **output-only** - it only uses `ECHO` to print characters (no `INPUT` required). Replace the bit-banged `ECHO` routine with a simple port write:

```asm
ECHO:   ani 7fh     ; clear MSB
        out 08h     ; write character to port 8
        ret
```

The testbench can capture characters written to port 8. Expected output is ASCII art with:
- Letters A-U for row labels
- Spaces for points that escape
- Asterisks (*) for points in the Mandelbrot set
- CR/LF at end of each row

**Note:** Requires `bitfuncs.inc` from the AS assembler include directory. Assemble with:
```bash
asl -cpu 8008new -i ~/Development/asl-current/include mandelbrot.asm
```

---

### pi.asm - SCELPie 1000 Digit Pi Calculator (2013)

Written by Egan Ford. Computes 1000 decimal digits of Pi (or e) using Machin's arctan formula with multiprecision arithmetic.

**Features:**
- Computes Pi = 4 * (4 * atan(1/5) - atan(1/239))
- Base-256 multiprecision arithmetic with BCD output conversion
- Uses "old" 8008 mnemonics (Lrr, etc.) with macros
- Entry point at 0x0040, halts when complete
- Configurable precision (edit `dec_len`/`bin_len` constants)
- Default: 50 digits (~75 sec at 500 KHz), original: 1000 digits (~25 min)

**Testing without serial hardware:**

This program is **output-only** - uses `cout` to print characters. Replace the bit-banged `cout` routine with a simple port write:

```asm
cout:   ani 7fh     ; clear MSB
        out 08h     ; write character to port 8
        ret
```

Expected output (50 digits):
```
50 DIGITS OF PI =
3.14159265358979323846264338327950288419716939937510
```

**Note:** Uses "old" 8008 mnemonics (pre-8080 style). Assemble with:
```bash
asl -cpu 8008 pi.asm
```

---

### stars.asm - Shooting Stars Game (Byte Magazine, 1976)

A puzzle game published in Byte Magazine May 1976. The player shoots "stars" to transform a universe of stars and black holes.

**Features:**
- Interactive text-based puzzle game
- 9-position universe (3x3 grid) with stars (*) and black holes (.)
- Each shot toggles the star and its "galaxy" neighbors
- Goal: Transform initial pattern to all stars with empty center
- Entry point at 0x0000, halts on game end

**Testing without serial hardware:**

This program requires **both input and output**. Replace the bit-banged I/O routines:

```asm
INCHAR: in 0        ; read character from port 0
        ret

OUTCHAR: ani 7fh    ; clear MSB
         out 08h    ; write character to port 8
         ret
```

The testbench needs to:
1. Capture output on port 8 writes
2. Provide input characters on port 0 reads (game expects digits 1-9, Y/N, CR)

For automated testing, pre-program a winning sequence of moves.

---

### hexspawn.asm - Hexpawn Game

A learning game similar to simplified chess pawns. The computer learns from its mistakes by removing losing moves from its strategy.

**Features:**
- 3x3 board with 3 pawns per player (X vs O)
- Pawns move forward or diagonally to capture
- Computer uses adaptive strategy (learns from losses)
- Entry point at 0x0100, loops on game end

**Testing without serial hardware:**

This program requires **both input and output**. Replace the bit-banged I/O routines:

```asm
INPUT:  in 0        ; read character from port 0
        ori 80h     ; set MSB
        ret

PRINT:  ani 7fh     ; clear MSB
        out 08h     ; write character to port 8
        ret
```

The testbench needs to:
1. Capture output on port 8 writes
2. Provide input characters on port 0 reads (digits 1-9 for moves)
