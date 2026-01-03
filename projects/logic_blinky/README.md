# Logic Blinky - ALU Logical Operations Test

Tests AND, OR, XOR instructions with visible LED feedback.

## Creating New Projects

To create a new b8008 project:

1. Copy the `blinky` directory (known working baseline)
2. Rename your `.asm` file
3. Update `Makefile`: change `ASM := your_program.asm`
4. Update `src/blinky_top.vhdl`: change `ROM_FILE => "./your_program.mem"`
5. `make clean && make all && make prog-quick`

## Key Requirements

- **Bootstrap interrupt**: The 8008 requires an RST 0 interrupt to start. The `blinky_top.vhdl` handles this automatically.
- **RST 0 vector at 0x0000**: Must have `jmp main` as the first instruction
- **Don't put code at RST addresses**: 0x08, 0x10, 0x18, 0x20, 0x28, 0x30, 0x38 are RST vectors

## LED Pattern

Cycles through 4 phases showing logical operation results:

| Phase | Operation | Result | LEDs ON |
|-------|-----------|--------|---------|
| 1 | 0xFF XOR 0x0F | 0xF0 | 0,1,2,3 (bottom 4) |
| 2 | 0xFF AND 0x3C | 0x3C | 0,1,6,7 (corners) |
| 3 | 0xC0 OR 0x03 | 0xC3 | 2,3,4,5 (middle 4) |
| 4 | 0xAA XOR 0xFF | 0x55 | 1,3,5,7 (alternating) |
