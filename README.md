# Intel 8008 VHDL Implementation - v1.2

A complete, cycle-accurate VHDL implementation of the Intel 8008 microprocessor with interrupt support, interactive monitor, comprehensive test suite, and **working FPGA deployment** with real hardware validation.

[![Status](https://img.shields.io/badge/status-v1.2%20hardware%20validated-brightgreen)]()
[![FPGA](https://img.shields.io/badge/FPGA-Deployed%20%26%20Working-success)]()
[![License](https://img.shields.io/badge/license-MIT-blue)](LICENSE.txt)

> **New in v1.2:** Working FPGA deployment! The [blinky project](projects/blinky/) synthesizes to hardware and actually blinks LEDs on the ECP5-5G board - written entirely in 8008 assembly. Major core improvements: fixed INR/DCR race condition, corrected I/O cycle detection, improved interrupt acknowledge handling, enhanced ROM/RAM address validation, and refined testbench accuracy.

> **New in v1.1:** Corrected interrupt implementation with proper T3 sampling, interrupt synchronizer, and PC preservation per Intel 8008 Rev 2 datasheet specifications.

> **Platform Note:** This project has been developed and tested exclusively on **macOS Sequoia 15.6.1**. Compatibility with other operating systems has not been verified.

## Overview

This project implements the Intel 8008 microprocessor (introduced April 1972) in VHDL, providing:

- **Complete 8008 CPU core** - All 48 instructions with cycle-accurate behavior
- **Interrupt support** - Hardware-accurate interrupt handling with T1I acknowledge cycle and synchronizer
- **Interactive monitor** - Real-time assembly program execution via VHPIDIRECT
- **Memory subsystem** - 2KB ROM + 1KB RAM
- **Comprehensive test suite** - 13+ validated programs with assertion-based verification
- **FPGA deployment** - Running on real hardware! Blinky project deploys to Lattice ECP5-5G and blinks LEDs

The blinky project demonstrates real hardware execution, while the interactive monitor provides a command-line interface for experimenting with 8008 assembly programs in simulation.

### What's New in v1.2

**Hardware Deployment - The Big Milestone:**
- First working FPGA deployment - Real 8008 code running on real hardware!
- Blinky project - Assembly program that synthesizes and blinks LEDs on ECP5-5G board
- Complete build-to-bitstream workflow with `make deploy` in [projects/blinky/](projects/blinky/)
- Hardware-validated I/O operations (OUT instruction driving physical LEDs)
- Demonstrates clock generation, ROM loading, and peripheral interfacing on FPGA

**Critical Bug Fixes:**
- Fixed INR/DCR race condition - Corrected result byte calculation timing issue
- Fixed I/O cycle detection - Proper identification and handling of INP/OUT operations
- Improved interrupt acknowledge - Correct RST 0 injection during T1I cycle with PC preservation
- Enhanced ROM read cycles - Prevent bus conflicts during write/I/O operations
- Added address validation - ROM/RAM now validate address ranges for better debugging

**Testing & Refinement:**
- Improved testbench accuracy across all 13+ test programs
- Enhanced I/O console for better cycle detection
- Refined interrupt controller timing and synchronization
- Better build organization (assembly outputs in dedicated build directories)

### What's New in v1.1

**Interrupt System Corrections:**
- Moved INT sampling from T1 to end of T3 during FETCH (per datasheet specification)
- Implemented interrupt synchronizer per Rev 2 datasheet requirements (±200ns stability)
- Fixed T1/T1I mutual exclusivity - proper state transition without spurious T1
- Added PC preservation during interrupt acknowledge sequence
- Created comprehensive interrupt testbench framework

For detailed analysis of the v1.0 bugs and fixes, see [docs/interrupt_analysis_and_testing.txt](docs/interrupt_analysis_and_testing.txt).

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

### Hardware Blinky Project (NEW in v1.2!)

**Deploy real 8008 assembly to FPGA hardware:**

```bash
cd projects/blinky
make deploy
```

This will:
1. Assemble [blinky.asm](projects/blinky/blinky.asm) (LED blink program in 8008 assembly)
2. Convert to memory initialization format
3. Synthesize the complete 8008 system for ECP5-5G FPGA
4. Generate bitstream
5. Program the FPGA

Watch LED0 blink! The program uses a delay loop written in pure 8008 assembly to create ~0.5 second on/off intervals. This is a complete 8008 system running real assembly code on real hardware.

See [projects/blinky/Makefile](projects/blinky/Makefile) for individual build steps and [projects/blinky/blinky.asm](projects/blinky/blinky.asm) for the assembly source with detailed comments.

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

### v1.2 Features (Hardware Validated!)

#### FPGA Deployment - WORKING!
- **Blinky project** synthesizes and runs on Lattice ECP5-5G hardware
- **Real 8008 assembly** driving physical LEDs via OUT instruction
- **Complete system-on-chip** with CPU, ROM, RAM, I/O controller, and clock generation
- **One-command deployment** - `make deploy` builds and programs FPGA
- **Hardware-validated** interrupt handling, I/O operations, and timing

### v1.0 Features (All Working)

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

#### FPGA Synthesis & Deployment
- **Successfully deployed** to Lattice ECP5-5G (45k LUTs)
- **Working on real hardware** - Blinky project validated
- **Complete synthesis flow** - GHDL → Yosys → nextpnr → bitstream
- **Place & Route** with timing and resource reports
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
│   ├── blinky/             # Hardware validation project (NEW in v1.2)
│   │   ├── blinky.asm      # LED blink program in 8008 assembly
│   │   ├── src/            # FPGA top-level and peripherals
│   │   ├── constraints/    # ECP5-5G pin constraints
│   │   └── Makefile        # Complete FPGA deployment workflow
│   ├── monitor_8008/       # Interactive monitor project
│   │   ├── monitor.asm     # Monitor program source
│   │   ├── console_vhpi.c  # C code for real terminal I/O
│   │   └── Makefile        # Build system with VHPIDIRECT
│   └── hello_io/           # Simple I/O test program
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

---

## Interrupt System: Implementation and Historical Context

The Intel 8008 interrupt mechanism represents an early and minimalist approach to interrupt handling that differs significantly from later microprocessors. Understanding its operation requires careful analysis of the datasheet evolution and timing requirements.

### Interrupt Architecture Overview

The 8008 implements a **single-level, non-vectorized interrupt** with instruction injection capability. Unlike modern processors with interrupt vector tables or the 8080's hardware-vectored interrupts, the 8008's approach places significant responsibility on external hardware.

#### Key Characteristics:
- **Single INT input line** - No priority levels in hardware
- **Instruction injection mechanism** - External device supplies the first instruction byte
- **No automatic state save** - Software/external hardware must preserve context
- **Program Counter preservation** - PC is not incremented during interrupt acknowledge

### The Interrupt Sequence

#### 1. Interrupt Recognition (End of PCI Cycle)

The CPU samples the INT line **at the end of each Program Counter Increment (PCI) cycle** during the T3 state. This is critical:

- **PCI cycle**: A complete instruction fetch (T1-T2-T3 or T1-T2-T3-T4-T5)
- **Sampling point**: At T3 completion, when `microcode_state = FETCH`
- **Decision**: Transition to T1I (interrupt acknowledge) instead of T1 (next instruction)

**Important**: T1 and T1I are **mutually exclusive states**. The CPU never enters T1 before T1I. This distinction is crucial for correct hardware interfacing.

#### 2. Interrupt Acknowledge Cycle (T1I-T2-T3)

When INT is recognized, the CPU performs a special acknowledge cycle:

**T1I State** (State outputs S2 S1 S0 = 110):
- Lower 8 bits of Program Counter output on data bus
- **PC is NOT incremented** - preserved for return address

**T2 State**:
- Upper 6 bits of PC and cycle type code output
- External interrupt controller recognizes acknowledge

**T3 State**:
- External controller may optionally drive data bus
- Typical implementations don't use this cycle for instruction injection

#### 3. Instruction Injection (Subsequent PCI Cycle)

Following the T1I acknowledge cycle, a **normal PCI cycle** occurs:

**T1 State**: CPU outputs the same PC (still not incremented)

**T2 State**: Cycle type = "00" (PCI - instruction fetch)

**T3 State**: **External interrupt controller jams instruction byte onto data bus**
- Typical instruction: RST n (Restart to vector n)
- Alternative: CALL, JMP, or any valid instruction
- CPU latches this as if it were fetched from memory

**Critical Detail**: Only the first byte is supplied by external hardware. If a multi-byte instruction is injected (e.g., CALL), subsequent bytes are fetched from normal memory using the current PC value.

#### 4. Instruction Execution

The injected instruction executes normally through the CPU's standard decode and execution logic.

**For RST n instruction**:
1. Current PC is pushed onto the 8-level stack
2. PC is set to (n × 8) - vector address in page zero
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

Each vector has 8 bytes - typically contains a JMP to the actual handler or minimal inline code.

#### 5. Return from Interrupt

The interrupt handler executes and terminates with a RET instruction:
- RET pops the saved PC from the stack
- Execution resumes at the interrupted instruction
- No special "return from interrupt" instruction needed

### Implementation Challenges: v1.0 Design Flaw

The initial v1.0 implementation contained a critical interrupt handling error that would manifest as correct behavior in simulation but system freeze on physical hardware.

#### The Flawed Logic (v1.0):

```vhdl
-- INCORRECT: Checking interrupt during T1 state
when T1 =>
    if INT = '1' then
        timing_state <= T1I;  -- Wrong: Already in T1!
    else
        timing_state <= T2;
    end if;
```

#### Problems with This Approach:

1. **T1/T1I exclusivity violation**: CPU enters T1, outputs state code 000, then attempts to transition to T1I
2. **Spurious state output**: External hardware sees one clock of T1 before T1I acknowledge
3. **Possible mid-instruction interrupt**: Could sample INT during non-PCI cycles (immediate fetch, memory operations, etc.)
4. **PC increment ambiguity**: PC increment logic may execute before interrupt is recognized

#### Why It Appeared to Work in Simulation:

- Testbench timing may not assert INT during critical states
- Simplified interrupt controller models may ignore state code glitches
- Simulation may not exercise all instruction timing combinations
- Single-step execution masks timing-dependent behavior

#### Why It Fails on Hardware:

- Real interrupt controllers strictly decode state sequences
- Asynchronous interrupt timing exposes all edge cases
- PC corruption from improper increment timing
- Multi-byte instructions interrupted mid-fetch cause decode errors
- System deadlock from inconsistent state machine progression

### The Correct Implementation

#### Interrupt Detection at T3:

```vhdl
when T3 =>
    if microcode_state = FETCH then
        -- Just completed instruction fetch (PCI cycle)
        if is_halt_op = '1' then
            timing_state <= STOPPED;
        elsif INT = '1' then
            timing_state <= T1I;  -- Correct: T1I instead of T1
            -- PC must not increment
        elsif instruction_needs_execute = '1' then
            timing_state <= T4;
        else
            timing_state <= T1;
        end if;
    -- ... other T3 cases
```

#### Key Corrections:

1. **Sample INT at end of T3** during FETCH microcode state only
2. **Directly transition to T1I** - never enter T1 first
3. **Prevent PC increment** during T1I cycle
4. **Allow normal PCI cycle after T1I** for instruction injection
5. **Resume PC increment** after instruction injection completes

### Datasheet Evolution: Rev 1 (1972) vs. Rev 2 (1973)

An important historical note exists in the Intel datasheets that reveals a discovered timing bug in the original 8008 design.

#### Intel 8008 Datasheet Revision 2 (1973) - Critical Addition:

> **When the processor is interrupted, the system INTERRUPT signal must be synchronized with the leading edge of the φ1 or φ2 clock. To assure proper operation of the system, the interrupt line to the CPU must not be allowed to change within 200ns of the falling edge of φ1.** An example of a synchronizing circuit is shown on the schematic for the SIM8-01 (Section VII). This is a new circuit recently added to the SIM8-01 board.

(Emphasis added to highlight the explicit acknowledgment of this being a new requirement)

#### What Changed Between Revisions:

**Revision 1 (1972)**: No mention of interrupt signal synchronization requirements

**Revision 2 (1973)**: Added explicit timing constraints and synchronization circuit requirement

#### Analysis of the Timing Requirement:

**Setup/Hold Time Constraint**: ±200ns around φ1 falling edge
- Prevents metastability in interrupt detection logic
- Ensures clean sampling by internal flip-flops
- Requires external synchronization circuit

**Why This Matters**:
- The 8008 was pushing the limits of 1972 PMOS technology
- Internal synchronizers may have been minimal or absent
- Asynchronous INT input could cause race conditions
- Real systems exhibited interrupt-related failures

#### The SIM8-01 Reference Design Solution:

Intel's solution (added to SIM8-01 board) implemented an **external interrupt synchronizer**:
- Latches incoming interrupt requests
- Synchronizes to φ1/φ2 clock edges
- Ensures INT signal stability during sampling window
- Provides "acknowledged" flag to clear interrupt source

### Recommended VHDL Implementation Strategy

To properly implement 8008-compatible interrupt handling in VHDL:

#### 1. Interrupt Synchronizer Process

```vhdl
-- Separate process: clock-synchronized interrupt latch
signal int_latched : std_logic := '0';

process(phi1, phi2, reset_n)
begin
    if reset_n = '0' then
        int_latched <= '0';
    elsif rising_edge(phi1) then  -- Synchronized to clock
        -- Latch interrupt request
        if INT = '1' and int_latched = '0' then
            int_latched <= '1';
        end if

        -- Clear on acknowledge (entering T1I)
        if timing_state = T1I then
            int_latched <= '0';
        end if;
    end if;
end process;
```

#### 2. Use Latched Signal in State Machine

```vhdl
-- Use int_latched instead of raw INT signal
when T3 =>
    if microcode_state = FETCH then
        if int_latched = '1' then
            timing_state <= T1I;
```

#### Benefits:

- **Clock synchronization**: Meets Rev 2 timing requirements
- **Edge detection**: Triggers once per interrupt event
- **No retriggering**: Cleared on acknowledge, prevents loops
- **Metastability prevention**: Registered input avoids race conditions

### Connection to Modern Interrupt Systems

Understanding the 8008's interrupt mechanism illuminates the evolution of interrupt architecture:

#### 8008 Limitations:
- Single interrupt level (no priorities)
- No automatic state preservation
- External hardware complexity (instruction injection)
- Manual context save via software

#### Evolution to 8080/8085:
- Hardware-vectored interrupts (RST 0-7 directly)
- Multiple priority levels (8085: TRAP, RST 7.5, 6.5, 5.5)
- Simplified external hardware interface

#### Modern Microcontrollers:
- Nested interrupt controllers (NVIC, etc.)
- Automatic register save/restore
- Priority levels and preemption
- Vector tables in memory

**The 8008's approach** of having external hardware inject an instruction directly influenced the interrupt acknowledge bus cycle design that persisted through x86 architecture to the present day.

### Debugging Interrupt Issues

Common symptoms of incorrect interrupt implementation:

**Simulation appears correct, hardware freezes**:
- Likely cause: Improper INT sampling point (checking at T1 instead of T3)
- Likely cause: Missing interrupt synchronization
- Likely cause: PC being incremented during T1I

**Continuous interrupt loop**:
- Likely cause: Interrupt latch not cleared on acknowledge
- Likely cause: External hardware not seeing T1I state properly

**Random instruction execution**:
- Likely cause: Interrupt occurring during non-PCI cycle (immediate byte fetch, etc.)
- Likely cause: External hardware not properly jamming instruction byte

**State machine lockup**:
- Likely cause: T1/T1I exclusivity violated
- Likely cause: Microcode state corruption from mid-instruction interrupt

### Testing Interrupt Functionality

To validate interrupt implementation:

1. **Unit test**: Assert INT at various microcode states, verify only PCI interruption
2. **Timing test**: Verify T1I appears immediately after T3 (no intermediate T1)
3. **PC preservation test**: Confirm PC doesn't increment during T1I cycle
4. **Injection test**: Simulate external controller jamming RST instruction
5. **Return test**: Verify RET returns to correct PC after handler
6. **Synchronization test**: Apply asynchronous INT, verify no metastability

### References

- Intel 8008 Datasheet, Revision 1 (April 1972)
- Intel 8008 Datasheet, Revision 2 (November 1972) - Added interrupt synchronization requirements
- Intel SIM8-01 Reference Design Schematic (Section VII: Interrupt Synchronizer)
- "The Intel 8008 Microprocessor: 25 Years Later" - IEEE Micro retrospective

---

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

## FPGA Deployment - COMPLETE!

**v1.2 Achievement:** The 8008 implementation is now running on real hardware! The blinky project successfully deploys to the ECP5-5G board and blinks LEDs using an 8008 assembly program.

### What's Working on Hardware

**Blinky Project** - [projects/blinky/](projects/blinky/)
- 76-line assembly program creates ~0.5s LED blink intervals
- Uses OUT instruction to drive LED bank (active-low, port 8)
- Delay subroutine with nested loops (~227,000 cycles per blink)
- Runs indefinitely, demonstrating stable FPGA operation

**Complete System-on-Chip**
- Intel 8008 CPU core running at ~455 kHz
- 2KB ROM initialized with assembled program
- 1KB RAM for stack and data
- Simple I/O controller for LED output
- Two-phase clock generator (φ1/φ2) from FPGA oscillator
- Interrupt controller (synchronized per Rev 2 datasheet)

**One-Command Deployment**
```bash
cd projects/blinky
make deploy
```

### Deployment Guide

#### Target Hardware

**Development Board:** Lattice ECP5-5G Versa Kit
- **Device:** LFE5UM5G-45F-8BG381C
- **Package:** 381-ball CABGA
- **Resources:** 45k LUTs, SERDES capable
- **Price:** ~$200 USD

The design is portable to other FPGAs (adjust constraints and Makefile settings).

#### Hardware Setup

**Board Configuration:**
1. Connect 12V power adapter
2. Connect USB cable (for programming)
3. Set DIP switches (SW4) to Master SPI mode: `010`
   - SW4.3: Down (CFG2 = 0)
   - SW4.2: Up (CFG1 = 1)
   - SW4.1: Down (CFG0 = 0)

**LED Observation:**
- LED0 (pin E16 via debug_led) - Main blink indicator
- Watch for steady 0.5s on / 0.5s off pattern

#### Build and Deploy

**Complete workflow (recommended):**
```bash
cd projects/blinky
make deploy
```

This runs: clean → assemble → convert → synthesize → program

**Individual steps:**
```bash
make asm           # Assemble blinky.asm → blinky.hex
make hex2mem       # Convert to memory format
make bitstream     # Synthesize FPGA bitstream
make program       # Flash to SRAM (volatile - for testing)
make flash         # Flash to persistent memory (survives power cycle)
```

**View synthesis reports:**
```bash
make reports       # Resource utilization and timing analysis
```

The synthesis flow:
1. **GHDL synthesis** - VHDL → Verilog
2. **Yosys synthesis** - Verilog → JSON netlist
3. **nextpnr place & route** - Logic placement and routing
4. **ecppack** - Generate bitstream
5. **openFPGALoader** - Program FPGA

### Pin Constraints

The blinky project uses its own constraint file at [projects/blinky/constraints/blinky.lpf](projects/blinky/constraints/blinky.lpf) which maps:
- Clock input to board's oscillator
- LED0 output (pin E16) for blink indicator
- Debug signals for optional logic analyzer connection

Modify this file to add:
- UART pins for terminal I/O (future work)
- Additional LEDs or switches for expanded functionality

### Next Steps for Hardware Development

**Current focus (v1.3):** Validate implementation accuracy by running vintage 8008 programs from [jim11662418's 8008 SBC collection](https://github.com/jim11662418/Intel_8008_Single_Board_Computer) with minimal assembly modifications.

Future enhancements:

1. **UART Interface** - Implement serial communication peripheral for terminal I/O
2. **Monitor on Hardware** - Adapt interactive monitor program to run on FPGA with UART
3. **Performance Optimization** - Increase clock frequency beyond current ~455 kHz
4. **Resource Optimization** - Reduce LUT usage for smaller FPGA targets
5. **Additional Peripherals** - Add timers, GPIO, or other 8008-compatible peripherals
6. **Multi-Project Support** - Additional hardware validation programs beyond blinky

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
- Design to begin now that FPGA validation is complete

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
| CPU Core (all 48 instructions) | Complete (simulation & hardware) |
| ALU Operations | Complete (simulation & hardware) |
| Memory (ROM + RAM) | Complete (simulation & hardware) |
| I/O System | Complete (simulation & hardware) |
| Interactive Monitor | Complete (VHPIDIRECT simulation) |
| Test Suite | Complete (13+ tests pass) |
| Simulation Verification | Validated |
| FPGA Synthesis | Verified (ECP5) |
| Hardware Deployment | Complete (Blinky project working!) |
| Real Silicon Interface | Future Work |

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
