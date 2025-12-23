# Attribution and Licensing Information

## Project Overview

This is a **cycle-accurate VHDL implementation** of the Intel 8008 microprocessor, created by **Robert Rico in 2025**.

This v1.0 release provides a complete, validated 8008 implementation for FPGA deployment, with comprehensive test coverage and an interactive monitor for real-time program execution.

---

## Copyright

**Copyright (c) 2025 Robert Rico**

All VHDL implementation, system integration, and testing infrastructure.

---

## License

This project is licensed under the **MIT License**. See [LICENSE.txt](LICENSE.txt) for full license text.

---

## Implementation

### Intel 8008 VHDL Implementation

All VHDL code is an **original implementation** by Robert Rico (2025), based on Intel's published specifications and datasheets.

**Reference Materials:**
- Intel 8008 Datasheet (1972, 1978)
- Intel 8008 User's Manual (1973)
- Intel SIM8-01 Reference Design Schematic

**Note:** During development, Michael Kohn's i8008 Verilog implementation was reviewed as a reference for understanding another HDL approach to the 8008 architecture.

---

## Components by Robert Rico

### v1.0 Core Implementation (src/components/)
- `s8008.vhdl` - Complete Intel 8008 CPU (1795 lines, cycle-accurate)
- `i8008_alu.vhdl` - Arithmetic Logic Unit ( Derived from Michael Kohn's i8008_alu.v)
- `phase_clocks.vhdl` - Two-phase non-overlapping clock generator (φ1/φ2)
- `rom_2kx8.vhdl` - 2KB ROM with program loading from .mem files
- `ram_1kx8.vhdl` - 1KB RAM with full read/write support
- `io_console.vhdl` - I/O console for simulation testing

### Interactive Monitor Project (projects/monitor_8008/)
- `monitor.asm` - Interactive monitor program with command processing
- `console_vhpi.c` - C code for real-time terminal I/O via VHPIDIRECT
- `io_console_interactive.vhdl` - VHDL I/O peripheral with C function integration
- `s8008_monitor_tb.vhdl` - Testbench for interactive simulation

### Test Infrastructure (sim/)
- `s8008_tb.vhdl` - Comprehensive test suite (all 48 instructions)
- `s8008_*_tb.vhdl` - Individual test program runners (search, RAM tests, etc.)
- `sim/units/*_tb.vhdl` - Unit tests for instruction categories
  - ALU operations
  - I/O operations
  - Rotate instructions
  - Stack operations (CALL/RET/RST)
  - Conditional jumps/calls/returns
  - Increment/decrement

### Test Programs (test_programs/)
- `simple_add.asm` - Basic arithmetic validation
- `search.asm` - Character search algorithm from Intel User Manual
- `ram_test.asm` - RAM read/write validation
- `ram_intensive.asm` - Stress test with complex patterns

### Build System
- `Makefile` - Main build configuration with test targets
- `common.mk` - Unified build rules for simulation and FPGA synthesis
- `hex_to_mem.py` - Utility to convert Intel HEX to memory initialization format

---

## Third-Party Tools

### Assembly Toolchain

All test programs are assembled using the **AS Assembler** (Macro Assembler AS) by Alfred Arnold:

- **Tool**: AS Assembler
- **Author**: Alfred Arnold
- **Website**: http://john.ccac.rwth-aachen.de:8000/as/
- **License**: GPL

This project uses **8080 syntax** (e.g., `MOV`, `MVI`) rather than original 8008 mnemonics (e.g., `Lrr`, `LrI`) because AS Assembler provides native support for this more familiar instruction set.

### Historical Attribution

Early iterations of this project used **naken_asm** by Michael Kohn for assembly:
- **Repository**: https://github.com/mikeakohn/naken_asm
- **Website**: https://www.mikekohn.net/
- Thanks to Michael Kohn for his multi-architecture assembler which helped bootstrap early development.

---

## Intel Source Materials

The Intel 8008 architecture is specified in:
- **Intel 8008 Datasheet** (1972, 1978)
- **Intel 8008 User's Manual** (1973)
- **Intel SIM8-01 Reference Design Schematic**

These documents provide the authoritative specifications for:
- Instruction set architecture (48 instructions)
- Two-phase clock timing (φ1/φ2)
- State machine behavior (T1-T5 cycles)
- Pin-out and electrical characteristics

---

## Project Evolution

### v1.0 - Monolithic Softcore (Current)
The active implementation uses a unified CPU design:
- Complete 8008 in `s8008.vhdl` (1795 lines)
- Cycle-accurate behavior matching Intel specifications
- Optimized for FPGA synthesis
- All glue logic integrated into CPU
- Fully validated in simulation

### Earlier Iterations
Previous experimental approaches explored:
- Modular glue-logic components (8212 latches, timing controllers)
- Designed for interfacing with real 8008 silicon
- Preserved in git history for reference

### Future (Stretch Goal)
Potential return to modular approach for real silicon interfacing:
- PMOS voltage level conversion (-9V/0V ↔ 3.3V FPGA)
- External address latching and timing
- Level shifter PCB design

---

## Trademarks

- Intel, 8008, and SIM8-01 are trademarks of Intel Corporation
- Other trademarks belong to their respective owners

This is an independent educational project, not an official product.

---

## Disclaimer

This hardware design is provided "as-is" for educational and historical preservation purposes.

### Simulation vs. Hardware Status
- **Simulation**: Fully validated on macOS Sequoia 15.6.1
- **FPGA Synthesis**: Verified for Lattice ECP5-5G
- **Hardware Deployment**: Not yet tested on physical FPGA

### Vintage Hardware Interfacing (Future)
When interfacing with vintage Intel 8008 silicon:
- Verify voltage levels carefully (PMOS: -9V/0V vs. FPGA: 3.3V)
- Test with non-critical hardware first
- Use appropriate level shifters and protection circuitry
- Proceed at your own risk

---

## Acknowledgments

- **Intel Corporation** for:
  - Original 8008 microprocessor design and documentation
  - SIM8-01 reference design

- **Michael Kohn** for:
  - naken_asm assembler used for all test programs

- **Vintage computing community** for:
  - Preservation and archiving of historical documentation
  - Sharing knowledge and expertise

- **Open-source FPGA toolchain developers**:
  - GHDL, Yosys, nextpnr, and the OSS CAD Suite team

---

## Contact

For questions, issues, or contributions:
- See repository issues/discussions

For questions about AS Assembler:
- Website: http://john.ccac.rwth-aachen.de:8000/as/
