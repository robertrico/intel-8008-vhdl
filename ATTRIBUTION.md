# Attribution and Licensing Information

## Project Overview

This is **b8008** — a block-based, cycle-exact VHDL implementation of the Intel 8008 microprocessor, created by **Robert Rico (2025-2026)**.

The current release is silicon-validated on a Lattice ECP5-5G Versa: the CPU follows the Intel block diagram (PC-in-stack architecture), takes exactly the datasheet's T-states per instruction, and runs period 8008 software — including SCELBAL BASIC, ROM-resident, as a boot-to-BASIC system with an integrated machine monitor.

---

## Copyright

**Copyright (c) 2025-2026 Robert Rico**

All VHDL implementation, system integration, monitor firmware, porting work, and testing infrastructure.

---

## License

This project is licensed under the **MIT License**. See [LICENSE.txt](LICENSE.txt) for full license text.

Third-party software run *on* the CPU (SCELBAL, the period application ports) retains its original authors' rights — see "Period Software" below.

---

## Implementation

### Intel 8008 VHDL Implementation (src/b8008/)

All VHDL code is an **original implementation** by Robert Rico, based on Intel's published specifications and datasheets.

**Reference Materials:**
- Intel 8008 Datasheet (1972, 1978)
- Intel 8008 User's Manual (1973)
- Intel SIM8-01 Reference Design Schematic
- `docs/isa.json` — this project's line-by-line mapping of every opcode to its documented T-state sequence

**Note:** During development, Michael Kohn's i8008 Verilog implementation was reviewed as a reference for understanding another HDL approach; `i8008_alu.vhdl` in the legacy components was derived from his `i8008_alu.v`.

---

## Components by Robert Rico

### Core CPU (src/b8008/)
Block-based modules following the Intel block diagram: state/timing generator, machine-cycle control, instruction register + decoder, 8x14 address stack (the PC is the SP-selected slot), stack pointer, register file, ALU, condition flags, temp registers, memory/I/O control, interrupt/READY flip-flop, and supporting muxes. Each module has its own testbench.

### FPGA Personalities (projects/)
- `b8008_monitor` — boots to an interactive machine monitor: D/W/H commands, `L` Intel HEX loading over serial, `G` go, RST vector forwarding, 46-test hardware ISA self-test ROM
- `b8008_basic` — **the tiny OS**: boots straight into ROM-resident SCELBAL; `MON` drops to the monitor; `G 1FB6` warm-returns to BASIC with the program intact
- `blinky`, `logic_blinky` — first hardware bring-up projects

### Monitor Firmware
- `b8008_monitor.asm` / `basic_monitor.asm` — the interactive monitor (original work)
- `send_hex.py` — paced Intel HEX sender with load verification

### Period Software Ports (test_programs/samples/)
Minimal-change ports of historical 8008 software (see below for original authors). Each port's exact change ledger is documented in the commit history; the porting recipe is in `docs/RAM_PROGRAMS.md`.

### Test Infrastructure
- 28-test regression suite with verification scripts (`test_programs/verification_scripts/`)
- Dedicated interrupt, state-timing, and cycle-count testbenches (`sim/b8008/`)
- Cycle-exactness regression diffing simulated T-states against `docs/isa.json`
- Python oracle emulator methodology (faithful PC-in-stack, post-increment model) for pre-silicon validation of ports

---

## Period Software

The point of this project is running real 1970s software. Credit where it belongs:

### SCELBAL — SCELBI BASIC (1976)
- **Original authors**: Mark Arnold & Nat Wadsworth, SCELBI Computer Consulting
- Released to the public domain by the authors decades later
- **This project runs Jim Loos's build**: [jim11662418/8008-SBC](https://github.com/jim11662418/8008-SBC), portions copyright 2021 by Jim Loos — ported here with a deliberately minimal change ledger (I/O shims, memory-map EQUs, and a `MON` keyword added in unused table space)

### Application Ports (test_programs/samples/)
Sourced from **Mike Willegal's SCELBI archive** ([willegal.net/scelbi/apps8008.html](https://www.willegal.net/scelbi/apps8008.html)):
- **HEXPAWN** (1973) — self-modifying learning game
- **SCELBI floating-point calculator** (1974) — 23-bit FP package
- **STARS** (Byte magazine, May 1976)
- **Mandelbrot renderer** and **pi digit generator** — later community programs for SCELBI-class hardware

Thanks to Mike Willegal for preserving and archiving this software, and to the original authors whose code — unchanged in spirit — validated this CPU better than any directed test.

---

## Third-Party Tools

### Assembly Toolchain

All 8008 code is assembled with the **AS Assembler** (Macro Assembler AS) by Alfred Arnold:

- **Tool**: AS Assembler
- **Author**: Alfred Arnold
- **Website**: http://john.ccac.rwth-aachen.de:8000/as/
- **License**: GPL

This project uses **8080 syntax** (e.g., `MOV`, `MVI`) rather than original 8008 mnemonics (e.g., `Lrr`, `LrI`) as supported by AS Assembler.

### FPGA Toolchain
- **GHDL** (VHDL analysis/simulation/synthesis), **Yosys**, **nextpnr-ecp5**, **prjtrellis** — via the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)

### Historical Attribution

Early iterations of this project used **naken_asm** by Michael Kohn for assembly:
- **Repository**: https://github.com/mikeakohn/naken_asm
- Thanks to Michael Kohn for his multi-architecture assembler and his i8008 Verilog implementation, both of which helped bootstrap early development.

---

## Intel Source Materials

The Intel 8008 architecture is specified in:
- **Intel 8008 Datasheet** (1972, 1978)
- **Intel 8008 User's Manual** (1973)
- **Intel SIM8-01 Reference Design Schematic**

These documents provide the authoritative specifications for:
- Instruction set architecture (48 instructions, 5/8/11 T-states)
- Two-phase clock timing (φ1/φ2)
- State machine behavior (Figure 2: state transitions, interrupt recognition at instruction boundaries)
- The block diagram this implementation follows — including the PC living in the address stack

---

## Project Evolution

### v3.0 — b8008, Block-Based (Current)
- Modular design per the Intel block diagram (`src/b8008/`)
- PC-in-stack, post-increment fetch, boundary-only interrupts, real WAIT state
- Cycle-exact T-states (27/27 timing classes vs `docs/isa.json`)
- Silicon-validated: monitor, period software, ROM-resident SCELBAL (the tiny OS)

### v2.x — v8008 (abandoned) and early b8008
Multi-cycle rework attempt, then the block-based restart that became current.

### v1.0 — s8008, Monolithic Softcore (superseded)
Single-file implementation; worked in simulation and partially on FPGA but with timing issues. Preserved in `src/s8008/` and `docs/LEGACY.md`.

### Future (Stretch Goal)
Interfacing with real 8008 silicon:
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
- **Hardware Deployment**: Silicon-validated on the ECP5-5G Versa (2026) — monitor, period software ports, and ROM-resident SCELBAL all proven on the board

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

- **Jim Loos** for:
  - The 8008-SBC SCELBAL build this project boots into

- **Mark Arnold & Nat Wadsworth (SCELBI Computer Consulting)** for:
  - SCELBAL — BASIC on an 8008, in 1976, in 8KB

- **Mike Willegal** for:
  - The SCELBI software archive that supplied every application port

- **Alfred Arnold** for:
  - AS Assembler (Macro Assembler AS)

- **Michael Kohn** for:
  - naken_asm and the i8008 Verilog reference

- **The VCF community** for:
  - FPGA advice, encouragement, and vintage expertise

- **Vintage computing community** for:
  - Preservation and archiving of historical documentation

- **Open-source FPGA toolchain developers**:
  - GHDL, Yosys, nextpnr, and the OSS CAD Suite team

---

## Contact

For questions, issues, or contributions:
- See repository issues/discussions

For questions about AS Assembler:
- Website: http://john.ccac.rwth-aachen.de:8000/as/
