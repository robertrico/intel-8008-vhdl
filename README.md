# b8008 - Block-Based Intel 8008 in VHDL

A modular VHDL implementation of the Intel 8008 microprocessor (1972) following the original block diagram architecture.

[![Status](https://img.shields.io/badge/status-verification-yellow)]()
[![Tests](https://img.shields.io/badge/tests-11%2F11%20passing-green)]()
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE.txt)

## Quick Start

```bash
# Run all verification tests
./test_programs/verification_scripts/run_all_tests.sh

# Run a specific test
make test-b8008-top PROG=alu_test_as SIM_TIME=30ms

# See all available tests
make show-programs
```

## Project Status

**All 28 instruction categories implemented. 11/11 automated tests passing.**

See [TODO.md](TODO.md) for verification roadmap before hardware deployment.

| Component | Status |
|-----------|--------|
| Instruction Decoder | Complete |
| ALU (8 operations + 4 rotates) | Complete |
| Register File (A,B,C,D,E,H,L) | Complete |
| Program Counter | Complete |
| 8-Level Stack | Complete |
| Condition Flags (C,Z,S,P) | Complete |
| I/O (INP/OUT) | Complete |
| Interrupts | Implemented, untested |

## Architecture

b8008 follows the Intel 8008 block diagram with explicit, simple modules:

```
┌─────────────────────────────────────────┐
│         Timing & Control Unit            │
│  (State Machine: T1→T2→T3→T4→T5)        │
└──────────┬──────────────────────────────┘
           │ control signals
           ↓
┌──────────────────┐  ┌─────────────────┐
│  Program Counter │  │ Instruction Reg │
│  14-bit          │  │ & Decoder       │
└──────────────────┘  └─────────────────┘

┌──────────────────┐  ┌─────────────────┐
│   Address Stack  │  │  Register File  │
│   (8 x 14-bit)   │  │  (A,B,C,D,E,H,L)│
└──────────────────┘  └─────────────────┘

                      ┌─────────────────┐
                      │      ALU        │
                      │  (8 ops + rot)  │
                      └─────────────────┘
```

**Design Principles:**
- Each module is simple (~50-100 lines)
- Modules are "dumb" - no instruction knowledge
- Control unit is the only smart component
- Explicit control signals, no boolean soup

## Directory Structure

```
intel-8008-vhdl/
├── src/b8008/              # Core implementation (25 VHDL files)
│   ├── b8008.vhdl          # Top-level integration
│   ├── instruction_decoder.vhdl
│   ├── alu.vhdl
│   ├── register_file.vhdl
│   ├── program_counter.vhdl
│   └── ...
├── sim/b8008/              # Testbenches
├── test_programs/          # Assembly test programs
│   └── verification_scripts/  # Automated test runners
├── docs/                   # Documentation
│   ├── instruction_coverage.md
│   ├── INTERRUPTS.md
│   └── LEGACY.md
├── TODO.md                 # Verification roadmap
└── CLAUDE.md               # AI assistant instructions
```

## Building and Testing

### Prerequisites

- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) (includes GHDL)
- [AS Assembler](http://john.ccac.rwth-aachen.de:8000/as/) for 8008 assembly
- macOS (tested on Sequoia 15.6.1)

### Make Targets

```bash
# Run main system test
make test-b8008-top

# Run with specific program
make test-b8008-top PROG=search_as

# Test individual modules
make test-pc              # Program counter
make test-alu             # ALU
make test-instr-decoder   # Instruction decoder

# Clean build
make clean
```

### Verification Scripts

```bash
# Run ALL verification tests (regression suite)
./test_programs/verification_scripts/run_all_tests.sh

# Run individual tests
./test_programs/verification_scripts/check_alu_test.sh
./test_programs/verification_scripts/check_rotate_test.sh
./test_programs/verification_scripts/check_rst_test.sh
```

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

## Intel 8008 Specifications

- **Year**: 1972 (world's first 8-bit microprocessor)
- **Clock**: 500-800 kHz
- **Registers**: 7 × 8-bit (A, B, C, D, E, H, L)
- **Stack**: 8-level internal (14-bit addresses)
- **Address Space**: 16 KB (14-bit)
- **Instructions**: 48 opcodes in 28 categories

## Documentation

- [TODO.md](TODO.md) - Verification roadmap and completion checklist
- [docs/instruction_coverage.md](docs/instruction_coverage.md) - Opcode test coverage matrix
- [docs/INTERRUPTS.md](docs/INTERRUPTS.md) - Interrupt system details
- [docs/LEGACY.md](docs/LEGACY.md) - Previous implementations (s8008, v8008)

## Legacy Note

This is the third implementation iteration:
- **b8008** - Current, block-based design
- **v8008** - Abandoned (too complex)
- **s8008** - Worked on FPGA but had timing issues

See [docs/LEGACY.md](docs/LEGACY.md) for details on previous versions.

## Resources

- [Intel 8008 Datasheet (1972)](docs/8008_1972.pdf)
- [Intel 8008 User Manual](docs/8008UM.pdf)
- [SIM8-01 Reference Design](docs/SIM8_01_Schematic.pdf)

## License

MIT - See [LICENSE.txt](LICENSE.txt)

## Attribution

- **Robert Rico** (2025) - VHDL implementation
- **Michael Kohn** (2022-2024) - Original Verilog reference
- **Intel Corporation** - Original 8008 design

See [ATTRIBUTION.md](ATTRIBUTION.md) for full credits.
