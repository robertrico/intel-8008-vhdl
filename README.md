# b8008 - Block-Based Intel 8008 in VHDL

A modular VHDL implementation of the Intel 8008 microprocessor (1972) following the original block diagram architecture — cycle-exact, silicon-validated, and running real 1970s software.

[![Status](https://img.shields.io/badge/status-silicon%20validated-brightgreen)]()
[![Tests](https://img.shields.io/badge/regression-28%2F28%20passing-green)]()
[![Timing](https://img.shields.io/badge/T--states-cycle--exact%2027%2F27-green)]()
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE.txt)

## It boots into BASIC

![SCELBAL booting on b8008 — the tiny OS](docs/images/tiny_os_scelbal.png)

That's the board powering on straight into Jim Loos's SCELBAL (SCELBI BASIC, 1976) from ROM, running a FOR/NEXT loop, dropping to a machine monitor with `MON` (dumping the tokenized BASIC program straight out of RAM), and warm-returning with `G 1FB6` — program intact. Apple II workflow, five years early, on the world's first 8-bit microprocessor.

## What runs on it

All period software below runs on the FPGA, loaded over serial through the monitor or resident in ROM — each ported with a minimal, documented change ledger (see the commit history):

| Program | Year | Notes |
|---------|------|-------|
| SCELBAL (SCELBI BASIC) | 1976 | ROM-resident with `MON` escape to monitor, or RAM-loaded |
| Mandelbrot renderer | — | Correct anatomy at full resolution |
| Pi digit generator | — | 49/50 digits (the 50th is the original's guard-byte truncation) |
| HEXPAWN | 1973 | Self-modifying learning game — plays, learns, improves |
| SCELBI FP Calculator | 1974 | 23-bit floating point; `12.2 X 2.2 = 26.84` |
| STARS | Byte 5/1976 | Interactive game via RST-vector I/O |

## Project Status

**Silicon-validated on a Lattice ECP5-5G Versa.** 28/28 regression tests, 46/46 hardware ISA self-tests on the board, cycle-exact T-states verified against the datasheet for all 27 timing classes.

| Component | Status |
|-----------|--------|
| Instruction set (48 opcodes, 28 categories) | ✅ Silicon validated |
| PC-in-stack architecture (PC = stack slot[SP], per Intel block diagram) | ✅ Silicon validated |
| Cycle-exact T-states (5/8/11 per instruction, `docs/isa.json`) | ✅ 27/27 classes |
| Flags: INR/DCR preserve carry; rotates write carry only | ✅ Per 8008 spec |
| Interrupts at instruction boundaries only (Figure 2, User's Manual) | ✅ Silicon validated |
| Real WAIT state (READY parks CPU between T2/T3) | ✅ Front-panel switch |
| Runtime interrupts (front-panel switch, selectable RST vector) | ✅ Silicon validated |
| Interactive monitor (D/W/L/G/H, Intel HEX loading) | ✅ Silicon validated |
| SCELBAL — RAM-resident and ROM-resident (boot-to-BASIC) | ✅ Silicon validated |

## Architecture

b8008 follows the Intel 8008 block diagram with explicit, simple modules:

```
┌─────────────────────────────────────────┐
│         Timing & Control Unit            │
│  (State Machine: T1→T2→T3→T4→T5)        │
│  Cycle-exact: cycles end where the       │
│  datasheet says (T3 for fetches, etc.)   │
└──────────┬──────────────────────────────┘
           │ control signals
           ↓
┌──────────────────┐  ┌─────────────────┐
│  Address Stack   │  │ Instruction Reg │
│  (8 x 14-bit)    │  │ & Decoder       │
│  slot[SP] = PC   │  └─────────────────┘
│  post-increment  │
└──────────────────┘  ┌─────────────────┐
┌──────────────────┐  │  Register File  │
│  Stack Pointer   │  │  (A,B,C,D,E,H,L)│
│  (3-bit, wraps)  │  └─────────────────┘
└──────────────────┘  ┌─────────────────┐
                      │      ALU        │
                      │  (8 ops + rot)  │
                      └─────────────────┘
```

Like the real chip, there is **no separate program counter** — the PC is whichever of the eight 14-bit address-stack registers SP points at. CALL is just SP moving on (the old slot keeps the return address); RET is SP moving back. Seven nested returns; the eighth CALL wraps onto the oldest.

**Design Principles:**
- Each module is simple (~50-100 lines)
- Modules are "dumb" - no instruction knowledge
- Control unit is the only smart component
- Explicit control signals, no boolean soup

## FPGA Personalities

Two complete system builds share the CPU core via memory-map generics:

| Project | Boot behavior | Memory map |
|---------|--------------|------------|
| `projects/b8008_monitor` | Boots to the machine monitor; load programs over serial (`L`), run them (`G`) | ROM 4KB @ 0x0000, RAM 12KB @ 0x1000 |
| `projects/b8008_basic` | **Boots straight into BASIC** (the tiny OS); `MON` drops to the monitor, `G 1FB6` warm-returns | RAM 4KB @ 0x0000, ROM 12KB @ 0x1000 (monitor + SCELBAL) |

```bash
cd projects/b8008_basic
make build        # synthesize + place & route + bitstream (with real error gates)
make prog-flash   # persist to SPI flash — the board becomes a BASIC machine
```

Serial: 115200 8N1, local echo off, DEL (not BS) for rubout — it's 1976 over there.

## Building and Testing

### Prerequisites

- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (includes GHDL, Yosys, nextpnr)
- [AS Assembler](http://john.ccac.rwth-aachen.de:8000/as/) for 8008 assembly
- macOS (tested on Sequoia 15.6.1)

### Make Targets

```bash
# Run main system test
make test-b8008-top

# Run with specific program
make test-b8008-top PROG=search_as

# Test individual modules
make test-stack-memory    # Address stack (PC-in-stack)
make test-alu             # ALU
make test-instr-decoder   # Instruction decoder

# See everything
make help
make show-programs
```

### Verification Scripts

```bash
# Run ALL verification tests (regression suite, 28/28)
./test_programs/verification_scripts/run_all_tests.sh

# Individual checks
./test_programs/verification_scripts/check_alu_test.sh
./test_programs/verification_scripts/check_cycle_count_test.sh   # cycle-exact T-states
./test_programs/verification_scripts/check_interrupt_test.sh
```

The board also carries a **46-test hardware ISA self-test ROM** (`make` targets under `projects/b8008_monitor`) that runs on silicon and reports over serial.

## Writing Test Programs

This project uses AS Assembler with **8080 syntax**:

```assembly
        cpu     8008new
        org     0000h

        MVI     A,42h       ; Load immediate
        MVI     B,24h
        ADD     B           ; A = A + B
        HLT

        end
```

Assemble and test:
```bash
make assemble PROG=my_test.asm
make test-b8008-top PROG=my_test
```

Period software ports live in `test_programs/samples/` — see `docs/RAM_PROGRAMS.md` for the load-and-go porting recipe.

## Intel 8008 Specifications

- **Year**: 1972 (world's first 8-bit microprocessor)
- **Clock**: 500-800 kHz
- **Registers**: 7 × 8-bit (A, B, C, D, E, H, L)
- **Stack**: 8-level internal, 14-bit addresses — the PC is one of them
- **Address Space**: 16 KB (14-bit)
- **Instructions**: 48 opcodes in 28 categories, 5/8/11 T-states each

## Documentation

- [TODO.md](TODO.md) - Verification roadmap (complete) and history
- [docs/isa.json](docs/isa.json) - Per-instruction T-state mapping (source of truth for cycle exactness)
- [docs/RAM_PROGRAMS.md](docs/RAM_PROGRAMS.md) - Porting recipe for period software
- [docs/INTERRUPTS.md](docs/INTERRUPTS.md) - Interrupt system details
- [docs/instruction_coverage.md](docs/instruction_coverage.md) - Opcode test coverage matrix
- [docs/LEGACY.md](docs/LEGACY.md) - Previous implementations (s8008, v8008)
- [projects/b8008_basic/MEMORY_MAP.md](projects/b8008_basic/MEMORY_MAP.md) - The tiny OS memory map

## Legacy Note

This is the third implementation iteration:
- **b8008** - Current, block-based design
- **v8008** - Abandoned (too complex)
- **s8008** - Worked on FPGA but had timing issues

See [docs/LEGACY.md](docs/LEGACY.md) for details.

## Resources

- [Intel 8008 Datasheet (1972)](docs/8008_1972.pdf)
- [Intel 8008 User Manual](docs/8008UM.pdf)
- [SIM8-01 Reference Design](docs/SIM8_01_Schematic.pdf)
- [Mike Willegal's SCELBI archive](https://www.willegal.net/scelbi/apps8008.html) - source of the period software
- [Jim Loos's 8008-SBC](https://github.com/jim11662418/8008-SBC) - the SCELBAL build this project runs

## License

MIT - See [LICENSE.txt](LICENSE.txt)

## Attribution

- **Robert Rico** (2025-2026) - VHDL implementation
- **Jim Loos** - SCELBAL build for the 8008-SBC (portions copyright 2021)
- **SCELBI Computer Consulting / Mark Arnold & Nat Wadsworth** - SCELBAL (1976)
- **Mike Willegal** - SCELBI software archive
- **Michael Kohn** (2022-2024) - Original Verilog reference
- **Intel Corporation** - Original 8008 design

See [ATTRIBUTION.md](ATTRIBUTION.md) for full credits.
