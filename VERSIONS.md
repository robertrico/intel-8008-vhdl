# Version History

## Version 2.0 (b8008) - Block-Based Implementation

**Status:** ✅ Complete - Ready for Hardware Testing
**Date:** December 2025

Complete architectural redesign following Intel 8008 block diagram with modular "dumb module" philosophy. All 48 instruction types implemented and verified in simulation. FPGA bitstream ready for hardware deployment.

### Architectural Approach

**Design Philosophy:**
- **Block-based modular design** - Each component (PC, ALU, registers, etc.) is a separate, simple module (~50-100 lines each)
- **"Dumb modules"** - Components have NO instruction awareness, only respond to explicit control signals
- **Clean interfaces** - Well-defined signals between modules
- **Testability** - Each module has individual testbench for isolation testing

### Verification Status

- **24/24 verification tests pass**
- **All 48 instruction types implemented** (28 unique operation categories)
- **100% opcode coverage** for all testable instruction variants
- **Stack depth verified** (6 nested CALLs)
- **Interrupt handling verified** (RST 0 bootstrap + RST 7 runtime)
- **Serial I/O verified** (bitbanged UART in simulation)

### FPGA Synthesis

| Metric | Value |
|--------|-------|
| GHDL Synthesis | 6665 lines Verilog |
| Device | ECP5 85k |
| LUT4s | 112 (blinky project) |
| Flip-flops | 63 |
| Max Frequency | 218 MHz (100 MHz target) |
| Timing | PASS |
| Bitstream | 276 KB |

### Build Commands

```bash
# Run all verification tests
./test_programs/verification_scripts/run_all_tests.sh

# Build FPGA project
make project P=blinky

# Program FPGA
make project P=blinky T=prog
```

### Code Location

- Core modules: `src/b8008/` (26 VHDL files)
- Testbenches: `sim/b8008/`
- Test programs: `test_programs/` (24 verified tests)
- FPGA projects: `projects/blinky/`

### Next Step

Flash to hardware and validate real-world operation.

---

## Version 1.x (s8008) - Legacy Monolithic Implementation

**Status:** ⚠️ Deprecated
**Location:** `src/components/s8008.vhdl` (DO NOT USE)

The original single-file implementation. While functional in simulation, it had architectural issues that made maintenance difficult. Replaced by b8008 block-based design.

This code is kept for historical reference only.
