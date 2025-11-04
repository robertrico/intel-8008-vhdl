# Intel 8008 VHDL Implementation - v1.0

A complete, cycle-accurate VHDL implementation of the Intel 8008 microprocessor with interactive monitor, comprehensive test suite, and FPGA synthesis support.

[![Status](https://img.shields.io/badge/status-v1.0%20simulation-brightgreen)]()
[![FPGA](https://img.shields.io/badge/FPGA-Ready%20for%20Deployment-orange)]()
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE.txt)

> **Platform Note:** This project has been developed and tested exclusively on **macOS Sequoia 15.6.1**. Compatibility with other operating systems has not been verified.

## Overview

This project implements the Intel 8008 microprocessor (introduced April 1972) in VHDL, providing:

- **Complete 8008 CPU core** - All 48 instructions with cycle-accurate behavior
- **Interactive monitor** - Real-time assembly program execution via VHPIDIRECT
- **Memory subsystem** - 2KB ROM + 1KB RAM
- **Comprehensive test suite** - 12+ validated programs with assertion-based verification
- **FPGA synthesis** - Verified synthesis for Lattice ECP5 (hardware deployment pending)

The interactive monitor provides a command-line interface for experimenting with 8008 assembly programs in simulation.

---

## Quick Start

### Prerequisites

#### 1. Install OSS CAD Suite

Install the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) for VHDL simulation, synthesis, and FPGA tools. Follow the installation instructions for your platform on the OSS CAD Suite repository.

Extract to `~/oss-cad-suite` and ensure the tools are in your PATH.

#### 2. Install GHDL (Homebrew) - For Interactive Monitor Only

If you want to use the interactive monitor project, install GHDL via Homebrew (includes VHPIDIRECT support):

```bash
brew install --cask ghdl
```

This is only required for the monitor project's C integration. Standard simulation and synthesis work with OSS CAD Suite alone.

#### 3. Configure Environment

```bash
cp .env.example .env
# Edit .env and set USERNAME to your macOS username
```

### Interactive Monitor

The interactive monitor provides real-time interaction with the simulated 8008 CPU:

```bash
cd projects/monitor_8008
make all
```

You'll see:
```
╔═══════════════════════════════════════════╗
║  Intel 8008 Interactive Monitor           ║
║  Type '?' for help                        ║
║  Press Ctrl+C to stop simulation          ║
╚═══════════════════════════════════════════╝

8008 Monitor v1.0
Type ? for help
8008>
```

Available commands:
- `H` - Print "Hello, World!"
- `?` - Display help text
- `Q` - Quit (executes HLT instruction)

The simulation implements blocking I/O via VHPIDIRECT, allowing the simulated CPU to wait for user input while maintaining cycle-accurate timing.

### Run Test Programs

Run the comprehensive test suite:

```bash
make test              # Main test suite (all instructions)
make test-search       # Run search algorithm
make test-ram-test     # RAM validation
make test-alu          # Arithmetic operations
make test-all          # Everything (comprehensive + units)
```

View waveforms in GTKWave:
```bash
make sim WAVE=1        # Auto-open GTKWave after simulation
```

---

## What's Included

### ✅ v1.0 Features (Working Now)

#### CPU Core
- **All 48 instructions** implemented and tested
- **Cycle-accurate** timing matching real 8008 behavior
- **Complete register set**: A, B, C, D, E, H, L
- **8-level stack** for CALL/RET instructions
- **14-bit addressing** (16KB address space)
- **Two-phase clock** (φ1/φ2) generation

#### Memory & I/O
- **2KB ROM** with program loading from assembled code
- **1KB RAM** with full read/write support
- **I/O console** for simulation testing
- **Interactive terminal** via VHPIDIRECT (monitor project)

#### Test Programs
Over a dozen test programs validating all functionality:

| Program | What It Tests |
|---------|---------------|
| `s8008_tb` | Comprehensive - all instructions |
| `search` | Array search algorithm |
| `ram_test` | RAM read/write operations |
| `ram_intensive` | Stress test with complex patterns |
| `simple_add` | Basic arithmetic |
| `s8008_alu_tb` | All ALU operations |
| `s8008_io_tb` | I/O port operations |
| `s8008_rotate_tb` | Rotate instructions |
| `s8008_stack_tb` | CALL/RET/RST |
| `s8008_conditional_*` | Conditional jumps/calls/returns |
| `s8008_inc_dec_tb` | Increment/decrement |

All tests **pass** with full assertion checking.

#### FPGA Synthesis
- **Synthesis verified** for Lattice ECP5-5G (45k LUTs)
- **Place & Route** with timing and resource reports
- **Hardware deployment pending** - See "Next Steps" section
- Portable to other FPGA families with constraint modifications

---

## Project Structure

```
intel-8008-vhdl/
├── src/components/          # Active v1.0 implementation
│   ├── s8008.vhdl          # Complete 8008 CPU (1795 lines!)
│   ├── i8008_alu.vhdl      # Arithmetic Logic Unit
│   ├── phase_clocks.vhdl   # Two-phase clock generator
│   ├── rom_2kx8.vhdl       # 2KB ROM with program loading
│   ├── ram_1kx8.vhdl       # 1KB RAM
│   └── io_console.vhdl     # I/O console for testing
│
├── sim/                     # Test programs and testbenches
│   ├── s8008_tb.vhdl       # Main comprehensive test
│   ├── s8008_*_tb.vhdl     # Individual test program runners
│   └── units/              # Unit tests for each instruction type
│
├── test_programs/           # 8008 assembly programs
│   ├── *.asm               # Assembly source
│   ├── *.hex               # Assembled hex output
│   └── *.mem               # Memory initialization files
│
├── projects/
│   └── monitor_8008/       # Interactive monitor project
│       ├── monitor.asm     # Monitor program source
│       ├── console_vhpi.c  # C code for real terminal I/O
│       └── Makefile        # Build system with VHPIDIRECT
│
├── docs/                    # Documentation and datasheets
│   ├── 8008_1972.pdf       # Original Intel datasheet
│   ├── 8008UM.pdf          # User manual
│   └── SIM8_01_Schematic.pdf  # Reference design
│
├── Makefile                 # Main build system
├── common.mk                # Shared build rules
└── hex_to_mem.py           # Utility to convert HEX to MEM format
```

---

## Using the 8008

### Writing Assembly Programs

This project uses [naken_asm](https://github.com/mikeakohn/naken_asm) by Michael Kohn for assembling 8008 code.

**Important:** naken_asm uses **8080 syntax** (Intel's later, more common mnemonics) rather than the original 8008 mnemonics. This means:
- Use `MOV` instead of `Lrr` (register-to-register moves)
- Use `MVI` instead of `LrI` (load immediate)
- Use `ADD`, `SUB`, etc. instead of `ADr`, `SUr`

This choice was made because 8080 syntax is more familiar and naken_asm already supports it.

**Example program:**

Create a new program in `test_programs/`:

```assembly
; my_program.asm - Add two numbers
.8008
.org 0x0000

start:
    mvi a, 0x42     ; Load 42 into accumulator (8080 syntax: MVI A)
    mvi b, 0x24     ; Load 24 into B register
    add b           ; Add B to accumulator (42 + 24 = 66)
    hlt             ; Halt

.end
```

**Assemble and load:**

```bash
make asm ROM_PROGRAM=my_program
make load-rom ROM_PROGRAM=my_program
```

**Test your program:**

```bash
make sim TEST=s8008_tb
```

### Assembly Syntax Reference

Common instructions in 8080 syntax (used by naken_asm):

| Instruction | Description | Example |
|-------------|-------------|---------|
| `mvi r, data` | Load immediate into register | `mvi a, 0x42` |
| `mov r1, r2` | Move register to register | `mov a, b` |
| `mov m, r` | Store register to memory [HL] | `mov m, a` |
| `mov r, m` | Load memory [HL] to register | `mov a, m` |
| `add r` | Add register to A | `add b` |
| `sub r` | Subtract register from A | `sub c` |
| `ana r` | AND register with A | `ana d` |
| `ora r` | OR register with A | `ora e` |
| `xra r` | XOR register with A | `xra h` |
| `cmp r` | Compare register with A | `cmp l` |
| `inr r` | Increment register | `inr a` |
| `dcr r` | Decrement register | `dcr b` |
| `jmp addr` | Jump to address | `jmp 0x100` |
| `jz addr` | Jump if zero | `jz LABEL` |
| `call addr` | Call subroutine | `call FUNC` |
| `ret` | Return from subroutine | `ret` |
| `hlt` | Halt | `hlt` |

Registers: `a`, `b`, `c`, `d`, `e`, `h`, `l`, `m` (memory via HL)

See the [test_programs/](test_programs/) directory for complete working examples.

### Available Make Targets

#### Simulation
```bash
make sim                    # Run main test
make sim TEST=<name>        # Run specific test
make sim WAVE=1             # Open GTKWave after simulation
make test-units             # Run all unit tests
make test-all               # Run everything
```

#### Program Management
```bash
make list-programs          # Show available programs
make asm ROM_PROGRAM=<name> # Assemble a program
make load-rom ROM_PROGRAM=<name>  # Load into ROM
make asm-and-load ROM_PROGRAM=<name>  # Assemble and load
```

#### FPGA Build
```bash
make bitstream              # Synthesize for FPGA
make reports                # View resource/timing reports
make program                # Flash to FPGA SRAM (volatile)
make flash                  # Flash to FPGA (persistent)
```

#### Utilities
```bash
make list-tests             # Show available tests
make sim-report             # View last simulation report
make clean                  # Clean simulation files
make clean-all              # Clean everything
make help                   # Show all targets
```

---

## Interactive Monitor (VHPIDIRECT)

The monitor project provides **real interactive I/O** - type commands and the 8008 responds in real-time!

### How It Works

The monitor uses GHDL's **VHPIDIRECT** feature to bridge VHDL simulation with C code:

```
Your Terminal
     ↕
C functions (console_vhpi.c)
     ↕
VHDL I/O peripheral (io_console_interactive.vhdl)
     ↕
8008 CPU (s8008.vhdl)
     ↕
Monitor program in ROM (monitor.asm)
```

When the 8008 executes `INP 2` (read keyboard), the simulation pauses until keyboard input is received. When it executes `OUT 0` (write character), output is immediately displayed to the terminal.

### Running the Monitor

```bash
cd projects/monitor_8008
make all
```

See [projects/monitor_8008/README.txt](projects/monitor_8008/README.txt) for full details on adding commands, extending functionality, and troubleshooting.

---

## Intel 8008 Architecture

### Specifications
- **Year**: 1972 (world's first 8-bit microprocessor)
- **Clock**: 500 kHz (8008-1) to 800 kHz (8008-2)
- **Instructions**: 48 opcodes
- **Registers**: 7 × 8-bit (A, B, C, D, E, H, L)
- **Stack**: 8-level internal (14-bit addresses)
- **Address Space**: 16 KB (14-bit addressing)
- **Data Bus**: 8-bit multiplexed with address
- **I/O Ports**: 8 input + 24 output (8-bit addressing)

### Register Set
- **A (Accumulator)** - Primary arithmetic register
- **B, C, D, E, H, L** - General purpose registers
- **H:L Pair** - 14-bit memory pointer
- **PC** - 14-bit program counter
- **Stack** - 8 levels (return addresses only)

### Instruction Format
- **1-byte**: Register operations (e.g., `LAB`, `ADB`)
- **2-byte**: Immediate data (e.g., `LAI 0x42`)
- **3-byte**: Jumps and calls (14-bit addresses)

### Two-Phase Clock
The 8008 uses non-overlapping clocks:
- **φ1** - First phase (0.8µs high, 0.4µs dead time)
- **φ2** - Second phase (0.6µs high, 0.4µs dead time)
- **Period** - 2.2µs total (φ1 rise to next φ1 rise)

Our implementation generates these from a 100 MHz FPGA clock.

---

## Next Steps - FPGA Deployment

The v1.0 implementation has **verified FPGA synthesis** but has not yet been deployed to hardware. The following steps outline the planned deployment procedure:

### Target Hardware

**Development Board:** Lattice ECP5-5G Versa Kit
- **Device:** LFE5UM5G-45F-8BG381C
- **Package:** 381-ball CABGA
- **Resources:** 45k LUTs, SERDES capable
- **Price:** ~$200 USD

The design is portable to other FPGAs (adjust constraints and Makefile settings).

### Synthesis (Verified)

The design successfully synthesizes. Build the bitstream with:

```bash
make bitstream
```

This runs the full flow:
1. **GHDL synthesis** - VHDL → Verilog
2. **Yosys synthesis** - Verilog → JSON netlist
3. **nextpnr place & route** - Logic placement and routing
4. **ecppack** - Generate bitstream

View resource utilization and timing:

```bash
make reports
```

### Programming the FPGA (Untested)

> **Note:** The following procedure has not been validated on hardware. This represents the planned deployment workflow.

**Setup (one-time):**
1. Connect 12V power adapter
2. Connect USB cable
3. Set DIP switches (SW4) to Master SPI mode: `010`
   - SW4.3: Down (CFG2 = 0)
   - SW4.2: Up (CFG1 = 1)
   - SW4.1: Down (CFG0 = 0)

**Flash to SRAM (for testing - volatile):**
```bash
make program
```

**Flash to persistent memory (survives power cycle):**
```bash
make flash
```

### Pin Constraints

Pin assignments are in [constraints/versa_ecp5.lpf](constraints/versa_ecp5.lpf). Modify this file to:
- Map clock input to your board's oscillator
- Assign LED outputs for status indicators
- Add UART pins for terminal I/O (future)
- Connect switches for control inputs

### FPGA Deployment Roadmap (Planned)

The following tasks are required for hardware validation:

1. **Initial Programming** - Flash bitstream to ECP5 board
2. **LED Test** - Verify synthesis by mapping CPU state to LEDs
3. **Memory Validation** - Run known test programs, observe outputs
4. **UART Interface** - Implement serial communication peripheral
5. **Terminal Integration** - Adapt monitor program for UART I/O
6. **Performance Analysis** - Measure achieved clock frequencies
7. **Optimization** - Reduce resource utilization if necessary

---

## Development

### Toolchain

This project uses the open-source FPGA toolchain:

- **[GHDL](https://ghdl.github.io/ghdl/)** - VHDL simulator and synthesis
  - OSS CAD Suite version: Standard simulation and synthesis
  - Homebrew version: VHPIDIRECT support for monitor project
- **[Yosys](https://yosyshq.net/yosys/)** - Logic synthesis
- **[nextpnr](https://github.com/YosysHQ/nextpnr)** - Place and route
- **[ecppack](https://github.com/YosysHQ/prjtrellis)** - Bitstream generation
- **[openFPGALoader](https://github.com/trabucayre/openFPGALoader)** - Programming
- **[GTKWave](http://gtkwave.sourceforge.net/)** - Waveform viewer

### GHDL Configuration

The monitor project (`projects/monitor_8008/`) requires Homebrew's GHDL for VHPIDIRECT support (C function linking). The main project uses OSS CAD Suite's GHDL. If you don't need the interactive monitor, OSS CAD Suite alone is sufficient.

### Build System

The project uses a **unified Makefile system**:

- [Makefile](Makefile) - Project configuration (source files, test list)
- [common.mk](common.mk) - Shared build rules and tool setup

To add a new test:
1. Create `sim/my_test_tb.vhdl`
2. Add to `ALL_TB_SOURCES` in Makefile
3. Add stop time: `STOP_TIME_my_test_tb = 500us`
4. Run: `make sim TEST=my_test_tb`

### Design Evolution

This project evolved through several architectural approaches:

**Early Iterations** (in `src/iss/`):
- Modular glue-logic approach
- Separate components for address latching (8212), timing, etc.
- Designed to interface with **real 8008 silicon**

**Current v1.0** (in `src/components/`):
- **Monolithic softcore** design
- All logic integrated into `s8008.vhdl`
- Optimized for FPGA synthesis
- Easier to simulate and validate

**Future** (stretch goal):
- Return to glue-logic approach for **real silicon interfacing**
- The 8008 uses PMOS technology (-9V/0V logic levels)
- Requires custom level shifter PCB (3.3V FPGA ↔ -9V 8008)
- Design pending post-FPGA validation

---

## Resources

### Intel 8008 Documentation
- [Intel 8008 Datasheet 1972 (PDF)](http://www.bitsavers.org/components/intel/MCS8/98-153B_Intel_8008_Datasheet_Nov72.pdf)
- [Intel 8008 Datasheet 1978 (PDF)](docs/8008_1978.pdf)
- [Intel 8008 User Manual (PDF)](http://www.bitsavers.org/components/intel/MCS8/MCS-8_Users_Manual_Nov73.pdf)
- [8008 Instruction Set Reference](https://en.wikipedia.org/wiki/Intel_8008#Instruction_set)
- [SIM8-01 Reference Design](docs/SIM8_01_Schematic.pdf)

### FPGA Development
- [GHDL Manual](https://ghdl.github.io/ghdl/)
- [Yosys Documentation](https://yosyshq.net/yosys/)
- [nextpnr Documentation](https://github.com/YosysHQ/nextpnr)
- [ECP5-5G Versa Board Guide](https://www.latticesemi.com/products/developmentboardsandkits/ecp55gversadevkit)
- [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)

### Assembly Tools
- [naken_asm](https://github.com/mikeakohn/naken_asm) - Multi-architecture assembler by Michael Kohn
  - Supports Intel 8008 with 8080 syntax (use `.8008` directive)
  - More familiar mnemonics than original 8008 assembly language
  - Example: `MOV A,B` instead of `LAB`, `MVI A,5` instead of `LAI 5`

---

## Attribution

See [ATTRIBUTION.md](ATTRIBUTION.md) for complete licensing and attribution information.

**Key Credits:**
- **Robert Rico** (2025) - VHDL implementation, system integration, testing
- **Michael Kohn** (2022-2024) - Original i8008 Verilog implementation (converted to VHDL)
- **Intel Corporation** - Original 8008 design and documentation

**License:** MIT (see [LICENSE.txt](LICENSE.txt))

---

## Historical Context

The Intel 8008 was a milestone in computing history:

- **First 8-bit microprocessor** (April 1972)
- Led to the **8080**, which inspired the **x86 architecture**
- Used in early personal computers like the **Mark-8**
- Proved a complete CPU could fit on a single chip

This VHDL implementation serves as:
- **Educational tool** for understanding early microprocessor architecture
- **Preservation** of computing history
- **Foundation** for interfacing with real vintage hardware (future)

---

## Contributing

Contributions welcome! Areas of interest:

- Additional test programs (games, algorithms, utilities)
- FPGA optimizations (reduce LUT usage, increase clock speed)
- UART implementation for real serial I/O
- Support for other FPGA families (Xilinx, Intel, etc.)
- Enhanced monitor commands (memory dump, register display, etc.)

When contributing:
1. Follow existing code style
2. Add comprehensive testbenches
3. Document with references to 8008 datasheet
4. Test in simulation before submitting

---

## Status Summary

| Component | Status |
|-----------|--------|
| CPU Core (all 48 instructions) | ✅ Complete (simulation) |
| ALU Operations | ✅ Complete (simulation) |
| Memory (ROM + RAM) | ✅ Complete (simulation) |
| I/O System | ✅ Complete (simulation) |
| Interactive Monitor | ✅ Complete (VHPIDIRECT) |
| Test Suite | ✅ Complete (12+ tests pass) |
| Simulation Verification | ✅ Validated |
| FPGA Synthesis | ✅ Verified (ECP5) |
| Hardware Deployment | ⏳ Pending |
| Real Silicon Interface | 📋 Future Work |

---

## Getting Started

```bash
git clone <your-repo>
cd intel-8008-vhdl
make test              # Run comprehensive test suite
cd projects/monitor_8008
make all              # Launch interactive monitor
```

## System Requirements

- **Operating System:** macOS Sequoia 15.6.1 (only tested platform)
- **OSS CAD Suite:** Install per instructions at https://github.com/YosysHQ/oss-cad-suite-build
- **GHDL (Homebrew):** `brew install --cask ghdl` (only needed for interactive monitor)
- **Python 3:** For hex-to-mem conversion utility
- **naken_asm:** Multi-architecture assembler by Michael Kohn
  - Repository: https://github.com/mikeakohn/naken_asm
  - Required for: Assembling custom 8008 programs
  - Supports 8080 syntax (more familiar than original 8008 mnemonics)
