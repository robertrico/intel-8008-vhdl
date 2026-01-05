# Bug Report: Yosys/GHDL ROM Initialization Corruption with 0xFF Fill

**Date:** January 2026
**Project:** b8008 (Intel 8008 VHDL Implementation)
**Target:** Lattice ECP5-5G Versa Development Kit (LFE5UM5G-45F)
**Toolchain:** GHDL + Yosys + nextpnr-ecp5 (OSS CAD Suite)

---

## Summary

ROM contents become corrupted on FPGA hardware when the ROM's default fill pattern is `0xFF`. Changing the fill to `0x00` resolves the issue. This appears to be a bug in Yosys optimization passes when processing GHDL-generated Verilog with mostly-1s ROM initialization.

---

## Symptoms

### What We Observed

1. **CPU crashes/freezes at startup** on real FPGA hardware
2. **GHDL simulation passes perfectly** - identical code works in simulation
3. Adding a `cpi 0Ah` instruction (compare immediate with LF character) triggered the crash
4. The specific byte value `0x0A` was initially suspected but ruled out

### The Red Herrings

During investigation, we went down several false paths:

1. **ROM size hypothesis**: Adding 32 bytes of padding "fixed" the issue with 4KB ROM
   - 399 bytes → crashes
   - 431 bytes (with padding) → works
   - This made us think it was a size threshold issue

2. **1KB ROM test**: Switching to smaller ROM produced *different* failure
   - CPU ran but no UART I/O at all
   - With padding → still broken
   - This ruled out size as the root cause

3. **The real fix**: Changing default fill from `0xFF` to `0x00` → **works perfectly**

---

## Root Cause Analysis

### The VHDL ROM Pattern

```vhdl
-- Original (BROKEN on hardware)
variable rom_data : rom_array := (others => x"FF");

-- Fixed (WORKS on hardware)
variable rom_data : rom_array := (others => x"00");
```

### Why Padding Appeared to Help

When most ROM content is `0xFF` (unused locations), the ROM is "sparse" - only ~400 bytes of actual code in a 4096-byte array. Adding padding changed the ratio of actual-data to fill-data, which apparently affected how Yosys optimized the ROM.

### Hypothesis

Yosys performs aggressive optimization when it detects that most of a memory's initial values are the same (especially all-1s). During the `proc` pass or subsequent optimization, initialization bits may be incorrectly stripped or simplified, corrupting the actual ROM data that differs from the fill pattern.

The `0x00` fill doesn't trigger this optimization path, possibly because:
- All-zeros is treated as "uninitialized" (safe default)
- All-ones triggers "constant propagation" optimizations
- Different code paths in Yosys handle these cases

---

## Steps to Reproduce

### Minimal Test Case (TODO: Create)

A minimal reproducing case would be:

```vhdl
-- minimal_rom_test.vhdl
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity minimal_rom is
    port (
        addr : in  std_logic_vector(9 downto 0);
        data : out std_logic_vector(7 downto 0)
    );
end minimal_rom;

architecture rtl of minimal_rom is
    type rom_array is array(0 to 1023) of std_logic_vector(7 downto 0);

    function init_rom return rom_array is
        variable r : rom_array := (others => x"FF");  -- THE BUG TRIGGER
    begin
        -- Small amount of actual data
        r(0) := x"06";  -- Some instruction
        r(1) := x"05";
        r(2) := x"0E";
        r(3) := x"03";
        -- ... rest is 0xFF
        return r;
    end function;

    constant rom : rom_array := init_rom;
begin
    data <= rom(to_integer(unsigned(addr)));
end rtl;
```

### Full Reproduction Steps

1. **Build with 0xFF fill:**
   ```bash
   cd projects/b8008_monitor
   # Ensure rom_1kx8.vhdl has: (others => x"FF")
   make clean-all assemble bit prog
   ```
   **Expected:** CPU crashes, no UART output, LEDs may not respond

2. **Build with 0x00 fill:**
   ```bash
   # Change rom_1kx8.vhdl to: (others => x"00")
   make clean-all assemble bit prog
   ```
   **Expected:** CPU runs, UART outputs banner, LEDs respond

### Verification in Simulation

Both versions pass GHDL simulation:
```bash
make test-b8008-top PROG=b8008_monitor SIM_TIME=50ms
# PASSES with either fill pattern
```

This confirms the bug is in synthesis/PnR, not in the VHDL logic.

---

## Environment

```
Platform: macOS (Darwin 24.6.0)
Toolchain: OSS CAD Suite (oss-cad-suite)
  - GHDL: ghdl --version (check actual version)
  - Yosys: yosys --version (check actual version)
  - nextpnr-ecp5: nextpnr-ecp5 --version (check actual version)

Target FPGA: Lattice ECP5-5G (LFE5UM5G-45F)
Board: ECP5-5G Versa Development Kit
```

### Synthesis Command

```bash
# GHDL synthesis to Verilog
ghdl -a --std=08 --work=work [source files]
ghdl --synth --std=08 --work=work --out=verilog top_entity > design.v

# Yosys synthesis for ECP5
yosys -p "read_verilog ghdl_gates.v design.v; \
          hierarchy -check -top top_entity; \
          tribuf -logic; \
          proc; \
          opt -nodffe; \
          synth_ecp5 -top top_entity -json design.json"
```

---

## Workaround

Change ROM default fill from `0xFF` to `0x00`:

```vhdl
-- In rom_1kx8.vhdl and rom_4kx8.vhdl
variable rom_data : rom_array := (others => x"00");  -- NOT x"FF"
```

This is functionally equivalent for our use case since:
- Unused ROM addresses return `0x00` (NOP-like or benign)
- The 8008 treats `0x00` as HLT, which is safe for runaway code
- `0xFF` is also HLT, so semantically identical

---

## Files Involved

| File | Change |
|------|--------|
| `src/components/rom_1kx8.vhdl` | Default fill `x"00"` |
| `src/components/rom_4kx8.vhdl` | Default fill `x"00"` |
| `src/b8008/b8008_top.vhdl` | Now uses `rom_1kx8` |
| `projects/project.mk` | References `rom_1kx8.vhdl` |

---

## Investigation TODO

- [ ] Create minimal VHDL test case (just ROM, nothing else)
- [ ] Test minimal case on ECP5 with both fill patterns
- [ ] Capture GHDL-generated Verilog for both cases and diff
- [ ] Capture Yosys JSON netlist for both cases and diff
- [ ] Identify which Yosys pass corrupts the initialization
- [ ] Test with `-nodffe` removed or other opt flags
- [ ] Check if issue exists with Verilog-native ROM (bypass GHDL)
- [ ] Search GHDL and Yosys issue trackers more thoroughly
- [ ] File bug report with minimal reproducer

---

## Related Issues (Not Exact Matches)

- [Yosys #867: ROM memory inference and initialization](https://github.com/YosysHQ/yosys/issues/867)
  - Similar area (ROM init) but different symptom (BRAM vs LUT inference)

- [ghdl-yosys-plugin: RAM inference issues](https://github.com/ghdl/ghdl-yosys-plugin)
  - Known limitation: "RAM inference is currently problematic"

- [Yosys #3415: Block RAM Synthesis in ECP5](https://github.com/YosysHQ/yosys/issues/3415)
  - ECP5 BRAM issues but different root cause

---

## Timeline of Discovery

1. **Initial symptom**: Adding `cpi 0Ah` to monitor program caused FPGA crash
2. **First hypothesis**: The byte `0x0A` is somehow special → ruled out (ROM already had 6 instances of `0x0A`)
3. **Second hypothesis**: ROM size threshold → padding helped with 4KB ROM
4. **Third test**: 1KB ROM without padding → different failure mode
5. **Fourth test**: 1KB ROM with padding → still broken
6. **Fifth test**: 1KB ROM with `0x00` fill → **SUCCESS**
7. **Sixth test**: 4KB ROM with `0x00` fill → **SUCCESS**
8. **Conclusion**: The `0xFF` fill pattern is the trigger, not size or content

---

## Notes

This bug is subtle and dangerous because:
1. **Simulation passes** - you won't catch it in testbenches
2. **Hardware fails silently** - CPU just doesn't work, no error messages
3. **Red herrings abound** - size, padding, specific bytes all seemed relevant
4. **Common pattern** - `0xFF` is the natural "erased EEPROM" default many designers use

If you're using GHDL + Yosys for ECP5 and have ROM initialization issues, try `0x00` fill as a first debugging step.
