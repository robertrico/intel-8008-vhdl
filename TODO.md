# TODO - b8008 Verification Roadmap

## ✅ ROADMAP COMPLETE (July 2026)

Everything below the line was the working roadmap; it is all done. Where the
project actually landed:

- **PC-in-stack architecture** — the PC is stack slot[SP], per the Intel block
  diagram; post-increment fetch; boundary-only interrupts (silicon-validated)
- **Cycle-exact T-states** — all 27 timing classes match `docs/isa.json` /
  the datasheet (5/8/11 states), verified by `check_cycle_count_test`
- **Interactive monitor** (`projects/b8008_monitor`) — D/W/L/G/H commands,
  Intel HEX loading over serial, 46/46 hardware ISA self-test on silicon
- **Period software** — Mandelbrot, pi, HEXPAWN (1973), SCELBI FP calc (1974),
  STARS (Byte 5/1976) all running on the board (`test_programs/samples/`)
- **SCELBAL** — Jim Loos's SCELBI BASIC, first RAM-resident under the monitor,
  then ROM-resident as **the tiny OS** (`projects/b8008_basic`): boot-to-BASIC,
  `MON` to the monitor, `G 1FB6` warm return (silicon-validated 2026-07-03)
- **Front-panel silicon tests** — runtime interrupts via DIP switch (selectable
  RST vector), READY/WAIT freeze switch, HLT wake, stack-wrap semantics

Remaining ideas (unscheduled): more RAM / bigger memory-map personality,
optional C13 reset button, monitor input-buffer hardening.

---

## ✅ Hardware Validation Complete (January 2026)

The b8008 has been successfully validated on real FPGA hardware:

| Project | What It Tests | Status |
|---------|---------------|--------|
| `blinky` | LED blink, I/O port 8, CALL/RET | ✅ Working |
| `logic_blinky` | ALU logical ops (AND, OR, XOR) | ✅ Working |
| `ram_blinky` | RAM read/write operations | ✅ Working |

**Target**: Lattice ECP5-5G Versa Development Kit (LFE5UM5G-45F)

---

## Simulation Status

- **24/24 verification tests pass**
- **All 48 instruction types implemented** (28 unique operation categories)
- **Block-based architecture complete**
- **Stack depth bug fixed** (RET was reading from wrong level)
- **Interrupt handling tested** (RST 0 bootstrap + RST 7 runtime interrupt)
- **Conditional RET bug fixed** (RZ/RNZ/etc. were ignoring condition flags)
- **Serial I/O tested** (hello_8008.asm outputs "HI\r\n0123456789 B8008-OK\r\n")
- **Estimated opcode coverage: ~95%** (see Confidence Report below)

---

## Confidence Report Summary

| Category | Confidence | Notes |
|----------|------------|-------|
| Instruction Decoder | 95% | All 48 instruction types decoded correctly |
| ALU Operations | 95% | Comprehensive testing of all register and immediate modes |
| Register Operations | 95% | All MOV r,r combinations tested via chains, swaps, NOPs |
| Memory Operations | 95% | MOV r,M and MOV M,r tested for all 14 variants |
| INR/DCR | 100% | All 12 variants tested with boundary conditions |
| Control Flow | 95% | JMP, CALL, RET, conditionals all tested |
| RST Instructions | 100% | All 8 vectors tested |
| I/O Operations | 100% | All 8 INP and all 24 OUT ports tested |
| Interrupts | 100% | Bootstrap (RST 0) and runtime interrupt (RST 7) tested |
| **Overall System** | **95%** | Ready for hardware with high confidence |

---

## High Priority

### [x] UART Hardware Integration (Implementation Complete - January 2026)
UART peripheral integrated with b8008 CPU for real terminal I/O.

**Implementation Status:**
- [x] Added I/O port interface to `b8008_top.vhdl`:
  - `io_port_in` (8-bit) - External input data for INP instructions
  - `io_port_in_select` (3-bit) - Which port uses external input
  - `io_port_in_enable` - Enables external input for selected port
  - `io_port_out` (8-bit) - Data being written by OUT instruction
  - `io_port_num_out` (5-bit) - Full port number (0-31)
  - `io_port_write` - Strobe pulses for one phi2 cycle on OUT T3
- [x] Implemented `hello_uart_top.vhdl`:
  - Instantiates b8008_top with UART hooks
  - Instantiates usart component at 115200 baud
  - OUT 9 triggers UART TX
  - INP 1 returns UART RX data (bit 7=ready, bits 6:0=data)
- [x] Synthesized and built bitstream (8584 FFs, 12504 LUTs)
- [x] All 24 regression tests pass
- [x] **TX verified on hardware** - "Hello, 8008!" outputs correctly

**Reusable UART Wrapper Created:**
- [x] `b8008_usart.vhdl` encapsulates all UART handshaking logic (TX and RX)
- [x] TX: Automatically triggers on OUT to configurable TX_PORT_NUM
- [x] RX: Ready flag latching with auto-clear on falling edge of io_port_read
- [x] New projects just instantiate b8008_usart and wire b8008_top I/O signals

**Hardware Setup:**
- [x] Identify available FPGA pins for TX/RX (3.3V compatible) - B19 (TX), B12 (RX)
- [x] Add UART pin constraints to LPF file - `projects/hello_uart/constraints/hello_uart.lpf`
- [x] Wire FTDI TX → FPGA RX, FTDI RX ← FPGA TX, common GND
- [x] Test TX output at 115200 baud on real hardware
- [x] Test RX echo (read char, write char back) - `io_uart` project

**Project Files:**
- `projects/hello_uart/` - TX-only demo, sends "Hello, 8008!" repeatedly
- `projects/io_uart/` - Full TX+RX echo demo with prompt
- `src/components/b8008_usart.vhdl` - Reusable UART wrapper for 8008
- `src/components/usart.vhdl` - Low-level UART TX/RX

**I/O Port Mapping:**
- Port 1 (IN): Direct UART RX (bit 7=ready, bits 6:0=data)
- Port 9 (OUT): Direct UART TX (sends byte immediately at 115200 baud)
- Port 8 (OUT): LED bank (directly active, accent active low)

### [x] Basic 8008 Monitor - DONE (`projects/b8008_monitor`)
Shipped beyond the spec: `H` help, `D addr[,n]` dump, `W addr,val`
readback-verified write, `L` Intel HEX load with checksums and paced
sender (`send_hex.py`), `G addr` go, RST vector forwarding. 115200 baud.
It became exactly what it promised: the foundation that ported real
8008 software (see `test_programs/samples/`).

### [x] ROM Synthesis Bug - RESOLVED (January 2026)

**Problem:** ROM contents become corrupted on FPGA hardware.

**Initial Symptoms:**
- `cpi 0Ah` (LF) in b8008_monitor caused CPU to crash/freeze at startup
- Same code passes in GHDL simulation
- Adding 32 bytes of padding to end of ROM made it work
- Without padding: 399 bytes → crashes
- With padding: 431 bytes → works

**Investigation Path:**
1. Initially suspected ROM size threshold - padding helped with 4KB ROM
2. Tried 1KB ROM without padding → different failure (CPU runs but no UART I/O)
3. Tried 1KB ROM with padding → still broken
4. Changed ROM default fill from `0xFF` to `0x00` → **WORKS**

**Root Cause:**
- **Yosys incorrectly optimizes ROMs when default fill is `0xFF`**
- The `0xFF` fill (all 1s) triggers aggressive optimization that corrupts ROM init bits
- Using `0x00` fill (all 0s) avoids this optimization bug
- ROM size and padding were red herrings - the real issue is the fill pattern

**Solution Applied:**
- Changed `rom_1kx8.vhdl` and `rom_4kx8.vhdl` default fill: `(others => x"00")`

**Files Modified:**
- `src/components/rom_1kx8.vhdl` - Default fill `x"00"`
- `src/components/rom_4kx8.vhdl` - Default fill `x"00"` (for consistency)
- `src/b8008/b8008_top.vhdl` - Uses `rom_1kx8`, updated memory map
- `projects/project.mk` - References `rom_1kx8.vhdl`

**Memory Map (Updated):**
| Address Range | Size | Device |
|---------------|------|--------|
| 0x0000-0x03FF | 1KB | ROM |
| 0x0400-0x0FFF | 3KB | Unmapped (returns 0x00) |
| 0x1000-0x13FF | 1KB | RAM |
| 0x1400-0x3FFF | 11KB | Unmapped (returns 0x00) |

**Note:** This is a quirk in Yosys/GHDL synthesis, not a CPU bug. Either `0x00` or `0xFF` fill is valid - `0x00` just happens to work correctly with the current toolchain.

---

### [x] Debug Bitbang UART RX Timing - SUPERSEDED
Bitbang I/O was replaced wholesale by the memory-mapped USART
(`IN 1` poll / `OUT 9` send) with atomic snapshot-and-pop RX. The
bitbang path is retired; original notes kept below for history.

### Original notes (January 2026)

**Problem:** Bitbang RX receives corrupted characters in simulation.

**Testbench Created:** `projects/bitbang_uart/sim/bitbang_uart_top_tb.vhdl`
- Exact FPGA replica with RX injection capability
- TX works: "Hello, 8008 1972!" outputs correctly
- RX issue: First char + CR work, subsequent chars corrupted

**Key Finding:**
- CPU runs ~38% slower than expected (576µs vs 416µs per bit)
- Software delay loops calibrated for different clock speed
- NOT a CPU instruction bug - likely adapter/timing calibration issue

**Next Steps:**
- [ ] Test with `calc.asm` to see behavior
- [ ] Consider adapter hardware adjustments (auto bit-time detection?)
- [ ] Or recalibrate software delay constants for b8008's speed

---

## Completed - High Priority

### [x] Add MOV r,M / MOV M,r Explicit Tests
- [x] Create dedicated test for all MOV r,M combinations
- [x] Create dedicated test for all MOV M,r combinations
- [x] Add verification script (`check_mov_mem_test.sh`)

### [x] Add Comprehensive INR/DCR Test
- [x] Test INR B, INR C, INR D, INR E, INR H, INR L (6 variants - no INR A exists)
- [x] Test DCR B, DCR C, DCR D, DCR E, DCR H, DCR L (6 variants - no DCR A exists)
- [x] Test boundary conditions: 0xFF + 1 → 0x00 with Zero flag, 0x00 - 1 → 0xFF
- [x] Add verification script (`check_inr_dcr_test.sh`)
- Note: INR/DCR don't affect the Carry flag per Intel 8008 spec

### [x] Add Systematic MOV r,r Test
- [x] Create test with all MOV r,r combinations (A,B,C,D,E,H,L sources/destinations)
- [x] Verify data propagation through register chain (forward and reverse)
- [x] Test register swaps (B<->C, D<->E, H<->L)
- [x] Test MOV X,X (NOP) preservation
- [x] Add verification script (`check_mov_rr_test.sh`)

---

## Medium Priority

### [x] Add RST 0, 5, 6, 7 Tests
- [x] RST 0 is special (address 0x0000) - tested via bootstrap
- [x] RST 5, 6, 7 tests added in `rst_full_test_as.asm`
- [x] Verification script: `check_rst_full_test.sh`

### [x] Add Flag Verification to Tests
- [x] Added debug flag outputs to b8008 and b8008_top
- [x] Created `flag_test_as.asm` with 8 flag tests
- [x] Verification script: `check_flag_test.sh`
- [x] Tests Carry, Zero, Sign, and Parity flags

### [x] Add Interrupt Test
`interrupt_ready_ff.vhdl` tested via dedicated interrupt testbench.
- [x] Create `interrupt_test_as.asm`
- [x] Test INT input sampling
- [x] Test T1I acknowledge cycle with RST instruction jamming
- [x] Test runtime interrupt (RST 7) waking from HLT
- [x] Create verification script (`check_interrupt_test.sh`)
- [x] Fixed IR reload bug after T1I (instruction was being overwritten from ROM)

### [x] Stack Depth Test
- [x] Test 6 nested CALLs (`stack_depth_test_as.asm`)
- [x] Fixed stack bug: RET was reading before SP decrement
- [x] Verification script: `check_stack_depth_test.sh`
- Note: Stack supports 8 levels (0-7), practical usable depth is 6-7 with bootstrap

### [x] Expand I/O Port Coverage
- [x] Test all 8 INP ports (0-7)
- [x] Test all 24 OUT ports (8-31, port 31 used for checkpoints)
- [x] Created `io_comprehensive_test_as.asm`
- [x] Verification script: `check_io_comprehensive_test.sh`

### [x] Add ALU Register Mode Coverage
- [x] Test ADD/ADC/SUB/SBB with all 7 source registers
- [x] Test ANA/XRA/ORA/CMP with all 7 source registers
- [x] Created `alu_reg_comprehensive_test_as.asm`
- [x] Verification script: `check_alu_reg_comprehensive_test.sh`

---

## Low Priority

### [x] Cross-Validate with Reference Simulator - DONE (different tool)
A faithful Python oracle emulator (PC-in-stack, post-increment model)
runs every port before silicon; calc's FP output artifacts match it
bit-for-bit. Oracle-first debugging became the project methodology.

### [x] Cycle-Accurate Timing Tests - DONE
`check_cycle_count_test.sh` runs one instruction per timing class,
counts actual simulated T-states between fetch markers, and diffs
against `docs/isa.json`. 27/27 cycle-exact, including not-taken
conditionals ending early. Every instruction takes the datasheet's
5/8/11 states.

### [x] FPGA Synthesis and Hardware Validation
- [x] GHDL synthesis: 6665 lines Verilog netlist
- [x] Yosys+nextpnr: ECP5 85k place & route complete
  - Device utilization: 112 LUTs, 63 FFs (includes ROM + RAM + CPU)
  - Max frequency: 218 MHz (100 MHz target) - PASS
- [x] Timing closure verified
- [x] Bitstream generation: 276 KB
- [x] **Hardware validated** (January 2026):
  - `blinky` - LED blink test ✅
  - `logic_blinky` - ALU logical operations (AND, OR, XOR) ✅
  - `ram_blinky` - RAM read/write ✅
- [x] Project template created (`projects/example/`)

### [x] Run Historical 8008 Software - DONE (the whole point, it turned out)
Mandelbrot, pi, HEXPAWN (1973), SCELBI FP calculator (1974), STARS
(Byte 5/1976), and full SCELBAL BASIC (1976) all run on silicon.
Confidence increased dramatically — by finding five real CPU bugs the
42-test self-test missed (carry preservation, rotate flags, WAIT state,
interrupt boundaries, PC-in-stack).

### [x] Create Opcode Sweep Test - DONE (as the hardware self-test)
The monitor's ISA self-test ROM runs 46 directed tests covering every
instruction category ON THE BOARD and reports over serial. 46/46 on
silicon.

---

## Known Limitations

### No INR A or DCR A Instructions
- Opcode 0x00 (which would be INR A with DDD=000) is HLT instead
- Opcode 0x01 (which would be DCR A with DDD=000) is also HLT
- This is correct per Intel 8008 specification - the accumulator cannot be incremented/decremented directly
- To increment A, use `ADI 01h`. To decrement A, use `SUI 01h`

### READY Signal - RESOLVED
A real WAIT state now parks the CPU between T2 and T3 per the
datasheet, exercised by a front-panel DIP switch and covered by
testbench + silicon validation.

---

## Test Coverage Matrix

| Instruction Type | Count | Tested | Coverage |
|-----------------|-------|--------|----------|
| HLT | 3 | 3 | **100%** |
| MOV r,r | 49 | 49 | **100%** |
| MOV r,M | 7 | 7 | **100%** |
| MOV M,r | 7 | 7 | **100%** |
| MVI r | 7 | 7 | **100%** |
| MVI M | 1 | 1 | **100%** |
| INR | 6 | 6 | **100%** |
| DCR | 6 | 6 | **100%** |
| ALU r (56 ops) | 56 | 56 | **100%** |
| ALU M | 8 | 8 | **100%** |
| ALU I | 8 | 8 | **100%** |
| Rotate | 4 | 4 | **100%** |
| JMP | 1 | 1 | **100%** |
| Jcc | 8 | 8 | **100%** |
| CALL | 1 | 1 | **100%** |
| Ccc | 8 | 8 | **100%** |
| RET | 1 | 1 | **100%** |
| Rcc | 8 | 8 | **100%** |
| RST | 8 | 8 | **100%** |
| INP | 8 | 8 | **100%** |
| OUT | 24 | 24 | **100%** |

Note: INR/DCR have 6 variants each (B,C,D,E,H,L) - no INR A or DCR A exists.

---

## Test Program Summary

| Test | What It Verifies | Status |
|------|------------------|--------|
| `alu_test_as.asm` | ADD, SUB, AND, XOR, OR, ADI, SUI, ANI, XRI, ORI, DCR, CMP, ADC, SBB | PASS |
| `alu_reg_comprehensive_test_as.asm` | All ALU register modes: ADD/SUB/ANA/ORA/XRA/CMP r with all registers | PASS |
| `rotate_carry_test_as.asm` | RLC, RRC, RAL, RAR, JC, JNC, RC, RNC, ADD M, SUB M | PASS |
| `conditional_call_test_as.asm` | ACI, SBI, CC, CNC, CNZ, CZ, RZ | PASS |
| `sign_parity_test_as.asm` | JP, JM, JPE, JPO, RP, RM, RPE, RPO | PASS |
| `sign_parity_call_test_as.asm` | CP, CM, CPO, CPE | PASS |
| `rst_test_as.asm` | RST 1, RST 2, RST 3, RST 4 | PASS |
| `rst_full_test_as.asm` | RST 1-7 (all vectors) | PASS |
| `io_test_as.asm` | INP 0-2, OUT 8-9 | PASS |
| `io_comprehensive_test_as.asm` | INP 0-7, OUT 8-30 (all ports) | PASS |
| `ram_intensive_as.asm` | MVI, MOV, memory operations | PASS |
| `memory_alu_test_as.asm` | ADC M, SBB M, ANA M, XRA M, ORA M, CMP M | PASS |
| `mvi_m_test_as.asm` | MVI M | PASS |
| `mov_mem_test_as.asm` | MOV r,M, MOV M,r (all 14 combinations) | PASS |
| `mov_rr_test_as.asm` | MOV r,r (all combinations via chains/swaps) | PASS |
| `inr_dcr_test_as.asm` | INR/DCR all registers, boundary conditions | PASS |
| `flag_test_as.asm` | Carry, Zero, Sign, Parity flags | PASS |
| `stack_depth_test_as.asm` | 6 nested CALLs/RETs | PASS |
| `search_as.asm` | Integrated algorithm test | PASS |
| `alu_full_coverage_test_as.asm` | ADC/SBB/ANA/ORA/XRA/CMP with all registers | PASS |
| `interrupt_test_as.asm` | Bootstrap RST 0, runtime RST 7 interrupt | PASS |
| `hlt_01_as.asm` | HLT opcode 0x01 | PASS |
| `hlt_ff_as.asm` | HLT opcode 0xFF | PASS |
| `hello_8008.asm` | Serial I/O, MOV A,M, PUTS routine, conditional RET | PASS |

---

## Verification Commands

```bash
# Run all tests
./test_programs/verification_scripts/run_all_tests.sh

# Run individual test
./test_programs/verification_scripts/check_alu_test.sh

# Run with specific program
make test-b8008-top PROG=alu_test_as SIM_TIME=30ms
```

---

## Completion Criteria ✅ ALL COMPLETE

All criteria met as of January 2026:

1. [x] All high priority items complete (INR/DCR test, MOV r,r test)
2. [x] All medium priority items complete (I/O, ALU coverage, interrupt test)
3. [x] Opcode coverage reaches 90%+ (currently ~95%)
4. [x] GHDL synthesis completes without errors (6665 lines Verilog)
5. [x] Yosys/nextpnr place & route (ECP5: 112 LUTs, 63 FFs)
6. [x] Timing analysis passes (218 MHz, target 100 MHz)
7. [x] **Three test programs run on hardware** (blinky, logic_blinky, ram_blinky)

