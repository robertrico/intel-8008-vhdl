# Legacy Implementations (s8008, v8008)

This document describes the previous implementation attempts that led to the current b8008 design.

> **Note:** These implementations are kept for historical reference only. All active development is on b8008.

---

## s8008 - v1.x (Monolithic Implementation)

**Location:** `src/s8008/s8008.vhdl`, `projects/legacy_projects/`

**Status:** Functional in simulation and hardware, but improper timing

### What It Was

A single-file, behavioral VHDL implementation optimized for quick development and FPGA deployment.

### What Worked

- All 48 instructions implemented
- I/O operations functional
- Interrupt support complete
- Successfully deployed to Lattice ECP5-5G FPGA
- Blinky demo ran on real hardware
- Interactive monitor via VHPIDIRECT
- Comprehensive test suite (13+ programs)

### What Didn't Work

- Timing model didn't match real 8008 behavior
- ALU operations had issues on hardware (worked in simulation)
- Single-cycle approach masked timing bugs
- Difficult to understand internal architecture

### Why We Moved On

The goal was to create an implementation that:
1. Matches the Intel 8008 block diagram
2. Has proper multi-cycle timing
3. Is educational and maintainable
4. Can interface with real vintage hardware

s8008 achieved FPGA deployment but failed the architectural goals.

### Hardware Projects (Still Functional)

These projects in `projects/legacy_projects/` work with s8008:

- **blinky/** - LED blink demo
- **cylon/** - Knight Rider LED effect (polling)
- **cylon_single/** - Button-driven LED (polling)
- **cylon_interrupt/** - Interrupt-driven LED
- **monitor_8008/** - Interactive terminal via VHPIDIRECT

---

## v8008 - Attempted Multi-Cycle Rewrite

**Location:** `src/v8008/v8008.vhdl`

**Status:** Abandoned mid-development

### What It Was

An attempt to add proper multi-cycle timing to the monolithic design using a behavioral state machine approach.

### What Went Wrong

1. **Too much conditional logic**: Code became littered with:
   ```vhdl
   if (state = X and flag = Y and not interrupt and cycle = 2) then
   ```

2. **Behavioral instead of structural**: Tried to describe behavior rather than build components

3. **Over-utilization of conditionals**: Every edge case got another `if` statement

4. **Unmaintainable complexity**: Couldn't debug because logic was too tangled

5. **Never reached working state**: Abandoned before completing basic instruction execution

### Lessons Learned

- Don't try to fix architectural problems with more conditional logic
- Behavioral design doesn't scale for complex state machines
- Need clear separation between control and datapath
- Individual modules must be simple and testable

---

## Evolution to b8008

The failures of s8008 and v8008 led to the b8008 design philosophy:

### From s8008 We Learned

- FPGA deployment is achievable
- Test suite infrastructure works
- Assembly toolchain is solid
- Timing bugs hide in behavioral code

### From v8008 We Learned

- Conditional logic doesn't scale
- Need structural, not behavioral design
- Each module must be "dumb"
- Control signals must be explicit

### b8008 Philosophy

1. **Block-diagram architecture**: Follow Intel 8008 internal structure
2. **Dumb modules**: Each component does ONE thing, has no instruction knowledge
3. **Explicit control signals**: No boolean logic soup
4. **Test each module in isolation**: Every module has its own testbench
5. **Control unit is smart, datapath is dumb**: Only one place knows about instructions

---

## File Locations

### DO NOT USE (Legacy)

```
src/s8008/s8008.vhdl          # Monolithic implementation
src/v8008/v8008.vhdl          # Failed multi-cycle attempt
projects/legacy_projects/      # s8008 FPGA projects
```

### USE INSTEAD (Current)

```
src/b8008/                     # Block-based implementation
sim/b8008/                     # b8008 testbenches
test_programs/                 # Test programs (work with b8008)
```

---

## Running Legacy Projects

If you need to run the legacy s8008 projects:

```bash
cd projects/legacy_projects/blinky
make deploy
```

These still work but use the deprecated s8008 core.

---

## Migration Path

When b8008 is ready for hardware:

1. Create new `projects/b8008_blinky/` using b8008 core
2. Verify identical behavior to s8008 version
3. Retire legacy projects to `archive/`
4. Update all documentation

See [TODO.md](../TODO.md) for the verification checklist before hardware deployment.
