# Version History

## Version 1.3 - Interrupt System Complete

**Release Date:** November 2025

Interrupts are fully operational! After extensive debugging and testing, the interrupt system now correctly handles interrupt acknowledge cycles, vector addressing, and return address preservation.

### Interrupt System - Fully Operational

**Critical Fixes:**
- Fixed interrupt acknowledge cycle bug - RST vectors now route to correct addresses
- Corrected return address preservation - RET now returns to proper program location after interrupt
- Comprehensive interrupt testbench validates timing, vector addressing, and state machine behavior
- Hardware-validated interrupt handling on FPGA with real button inputs

**Technical Details:**
- Proper T1I acknowledge cycle sequencing with PC preservation
- Correct RST instruction vector calculation and execution
- Stack pointer management during interrupt entry/exit
- Interrupt synchronization per Intel 8008 Rev 2 datasheet requirements

### New Core Components

- **Generic I/O Controller** - Configurable input/output ports with interrupt capabilities
- **Memory Controller** - Unified ROM/RAM access with proper address decoding
- **Interrupt Controller** - Hardware debouncing for reliable external interrupt sources
- **Reset/Interrupt Controller** - Proper system initialization and interrupt synchronization
- **Debouncer** - Hardware debouncing component for reliable button inputs

### New Demonstration Projects

- **[Cylon LED Effect](projects/cylon/)** - Simple polling-based LED animation demonstrating basic I/O
- **[Button-Driven Cylon](projects/cylon_single/)** - Button advances LED pattern using polling
- **[Interrupt-Driven Cylon](projects/cylon_interrupt/)** - Hardware interrupts trigger pattern advancement
  - Complete with debug analysis tools for interrupt timing verification
  - State tracing and glitch analysis Python utilities
  - Hardware-validated on ECP5-5G FPGA

### Testing and Validation

- New RST 1 interrupt testbench reproducing and validating the interrupt fixes
- Logic capture documentation of hardware interrupt behavior (DSLogic)
- Comprehensive state tracing and glitch analysis tools
- Edge detection and timing verification utilities

### Commits Since v1.2

- `e9b1617` - Fixes interrupt handling and return address
- `6977e0d` - Back to kind of working
- `f6f16fc` - Adds interrupt-driven Cylon LED effect project
- `ce57358` - Implements interrupt-driven Cylon effect
- `0415e36` - Implements button-driven Cylon LED effect
- `3842624` - Replaces simple I/O with a generic controller
- `5d9a045` - Adds Cylon LED effect program
- `5a2299f` - Adds core system components
- `519062b` - Adds Logic Capture

---

## Version 1.2 - Hardware Deployment

**Release Date:** Prior to interrupt fixes

Working FPGA deployment! The blinky project synthesizes to hardware and actually blinks LEDs on the ECP5-5G board.

### Hardware Deployment - The Big Milestone

- First working FPGA deployment - Real 8008 code running on real hardware!
- Blinky project - Assembly program that synthesizes and blinks LEDs on ECP5-5G board
- Complete build-to-bitstream workflow with `make deploy` in [projects/blinky/](projects/blinky/)
- Hardware-validated I/O operations (OUT instruction driving physical LEDs)
- Demonstrates clock generation, ROM loading, and peripheral interfacing on FPGA

### Critical Bug Fixes

- Fixed INR/DCR race condition - Corrected result byte calculation timing issue
- Fixed I/O cycle detection - Proper identification and handling of INP/OUT operations
- Improved interrupt acknowledge - Correct RST 0 injection during T1I cycle with PC preservation
- Enhanced ROM read cycles - Prevent bus conflicts during write/I/O operations
- Added address validation - ROM/RAM now validate address ranges for better debugging

### Testing & Refinement

- Improved testbench accuracy across all 13+ test programs
- Enhanced I/O console for better cycle detection
- Refined interrupt controller timing and synchronization
- Better build organization (assembly outputs in dedicated build directories)

---

## Version 1.1 - Interrupt System Corrections

**Release Date:** Initial interrupt implementation

Corrected interrupt implementation with proper T3 sampling, interrupt synchronizer, and PC preservation per Intel 8008 Rev 2 datasheet specifications.

### Interrupt System Corrections

- Moved INT sampling from T1 to end of T3 during FETCH (per datasheet specification)
- Implemented interrupt synchronizer per Rev 2 datasheet requirements (±200ns stability)
- Fixed T1/T1I mutual exclusivity - proper state transition without spurious T1
- Added PC preservation during interrupt acknowledge sequence
- Created comprehensive interrupt testbench framework

For detailed analysis of the v1.0 bugs and fixes, see [docs/interrupt_analysis_and_testing.txt](docs/interrupt_analysis_and_testing.txt).

---

## Version 1.0 - Initial Release

**Release Date:** Initial public release

Complete 8008 CPU implementation with all 48 instructions, comprehensive test suite, and simulation validation.

### CPU Core

- All 48 instructions implemented and tested
- Cycle-accurate timing matching real 8008 behavior
- Complete register set: A, B, C, D, E, H, L
- 8-level stack for CALL/RET instructions
- 14-bit addressing (16KB address space)
- Two-phase clock (φ1/φ2) generation

### Memory & I/O

- 2KB ROM with program loading from assembled code
- 1KB RAM with full read/write support
- I/O console for simulation testing
- Interactive terminal via VHPIDIRECT (monitor project)

### Test Programs

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

All tests pass with full assertion checking.
