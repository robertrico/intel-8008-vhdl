# Version History

## Version 2.1 (b8008) - Hardware Validated

**Status:** ✅ Hardware Validated on ECP5 FPGA
**Date:** January 2026

Hardware validation complete. Three working FPGA projects demonstrating LED control, ALU logical operations (AND, OR, XOR), and RAM read/write. Bootstrap interrupt sequence proven working on real hardware.

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

# Build and program FPGA project
cd projects/blinky
make all          # Assemble + synthesize + place & route + bitstream
make prog         # Program via JTAG
```

### Code Location

- Core modules: `src/b8008/` (26 VHDL files)
- Testbenches: `sim/b8008/`
- Test programs: `test_programs/` (24 verified tests)
- FPGA projects: `projects/`
  - `blinky/` - LED blink (first hardware test)
  - `logic_blinky/` - ALU logical operations test
  - `example/` - Template for new projects

### Hardware Validation Results

| Test | Result |
|------|--------|
| LED blink (I/O port 8) | ✅ Pass |
| ALU logical ops (AND, OR, XOR) | ✅ Pass |
| RAM read/write | ✅ Pass |
| Bootstrap interrupt (RST 0) | ✅ Pass |
| CALL/RET with delay loops | ✅ Pass |

### Key Lesson Learned

The Intel 8008 requires a **bootstrap interrupt** to start execution. After reset, the CPU enters STOPPED state and waits for an external interrupt. The FPGA must:
1. Assert interrupt after reset releases
2. Wait for T1I state (CPU acknowledges interrupt)
3. Jam RST 0 instruction (0x05) onto data bus
4. Clear interrupt after T1I detected

Program must have `jmp main` at address 0x0000 to handle the RST 0 vector.

---

## Version 1.x (s8008) - Legacy Monolithic Implementation

**Status:** ⚠️ Deprecated
**Location:** `src/components/s8008.vhdl` (DO NOT USE)

The original single-file implementation. While functional in simulation, it had architectural issues that made maintenance difficult. Replaced by b8008 block-based design.

This code is kept for historical reference only.
