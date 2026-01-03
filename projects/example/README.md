# Example Project - b8008 Template

Copy this folder to create new b8008 FPGA programs.

## Quick Start

```bash
# 1. Copy to new project
cp -r projects/example projects/my_project
cd projects/my_project

# 2. Rename files
mv example.asm my_project.asm
mv src/example_top.vhdl src/my_project_top.vhdl
mv constraints/example.lpf constraints/my_project.lpf

# 3. Edit Makefile - change these lines:
PROJECT := my_project_top
TOP := my_project_top
LPF := constraints/my_project.lpf
ASM := my_project.asm
PROJECT_SRCS := ./src/my_project_top.vhdl

# 4. Edit src/my_project_top.vhdl:
#    - Change entity name: example_top -> my_project_top
#    - Change ROM_FILE: "./example.mem" -> "./my_project.mem"

# 5. Write your program in my_project.asm

# 6. Build and run
make clean && make all && make prog
```

## Project Structure

```
example/
├── Makefile              # Build configuration
├── example.asm           # Your 8008 assembly program
├── constraints/
│   └── example.lpf       # FPGA pin assignments
└── src/
    └── example_top.vhdl  # FPGA top level (uses b8008_top)
```

## Key Points

1. **RST 0 vector required**: Your program MUST start with `jmp main` at address 0x0000

2. **Two files to edit**:
   - `Makefile`: ASM filename
   - `src/example_top.vhdl`: ROM_FILE path and entity name

3. **Active-low LEDs**: Write 0 to turn ON, 1 to turn OFF
   - `mvi a,0FEh` + `out 8` = LED0 on
   - `mvi a,0FFh` + `out 8` = all off

4. **Uses b8008_top**: Single VHDL file with ROM_FILE generic - proven working design

## Make Targets

```bash
make all          # Full build
make prog         # Program FPGA (rebuilds if needed)
make prog-quick   # Program without rebuild check
make clean        # Remove build artifacts
```
