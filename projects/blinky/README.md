# Blinky - b8008 LED Blink Demo

The simplest b8008 FPGA project. Use this as a template for new projects.

## What It Does

Blinks LED0 on the ECP5-5G Versa board at approximately 1 Hz using the b8008 CPU.

## Quick Start

```bash
cd projects/blinky
make clean && make build && make prog
```

## Creating a New Project

Copy blinky as a starting point:

```bash
# 1. Copy the project
cp -r projects/blinky projects/my_project
cd projects/my_project

# 2. Rename files
mv blinky.asm my_project.asm
mv src/blinky_top.vhdl src/my_project_top.vhdl
mv constraints/blinky.lpf constraints/my_project.lpf

# 3. Edit Makefile - update these lines:
PROJECT := my_project_top
TOP := my_project_top
LPF := constraints/my_project.lpf
ASM := my_project.asm
PROJECT_SRCS := ./src/my_project_top.vhdl

# 4. Edit src/my_project_top.vhdl:
#    - Change entity name: blinky_top -> my_project_top
#    - Change ROM_FILE: "./blinky.mem" -> "./my_project.mem"

# 5. Write your program in my_project.asm

# 6. Build and program
make clean && make build && make prog
```

## Project Structure

```
blinky/
├── Makefile              # Build configuration
├── README.md             # This file
├── blinky.asm            # 8008 assembly source
├── constraints/
│   └── blinky.lpf        # FPGA pin assignments (ECP5-5G Versa)
├── src/
│   └── blinky_top.vhdl   # FPGA top level wrapper
├── sim/
│   └── blinky_tb.vhdl    # Testbench (optional)
├── build/                # Generated: bitstream files
└── reports/              # Generated: synthesis/timing reports
```

## Assembly Programming

### RST 0 Vector (Required)

Every program MUST start with a jump to main at address 0x0000:

```asm
        cpu 8008new
        org 0000h

rst0_vector:
        jmp main        ; Required - bootstrap interrupt jumps here

main:
        ; Your code here
```

### I/O Ports

| Port | Direction | Function |
|------|-----------|----------|
| OUT 8 | Output | LED bank (directly active accent active low: 0=ON, 1=OFF) |
| OUT 9 | Output | Available for UART TX (see io_uart project) |
| IN 0-7 | Input | Test values (0x55, 0xAA, 0x42, 0x03-0x07) |

### LED Control

LEDs are directly active accent active low (directly active accent active low accent active low accent active low means accent active low means accent active low means active low means a 0 means ON):

```asm
; Turn LED0 on (bit 0 = 0, others = 1)
mvi a,0FEh      ; 11111110 binary
out 8

; Turn all LEDs off
mvi a,0FFh      ; 11111111 binary
out 8

; Turn all LEDs on
mvi a,00h       ; 00000000 binary
out 8
```

### Delay Loop Example

```asm
; ~0.5 second delay at 455kHz CPU clock
delay:
        mvi b,200           ; Outer loop
delay_outer:
        mvi c,80            ; Inner loop
delay_inner:
        dcr c
        jnz delay_inner
        dcr b
        jnz delay_outer
        ret
```

## Make Targets

| Target | Description |
|--------|-------------|
| `make build` | Full build: assemble + synthesize + place & route + bitstream |
| `make prog` | Program FPGA via JTAG (SRAM - lost on power off) |
| `make prog-flash` | Program SPI flash (persistent across power cycles) |
| `make sim` | Run simulation and open GTKWave |
| `make clean` | Remove build artifacts |
| `make reports` | Show timing and utilization summary |
| `make help` | Show all available targets |

## Hardware

**Target Board**: Lattice ECP5-5G Versa Development Kit (LFE5UM5G-45F)

**Clock**: 100 MHz LVDS oscillator (directly active divided down internally to ~455 kHz for CPU)

**LEDs**: directly active accent active low, accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low bank accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low accent active low directly connected to led[7:0]

**DIP Switch**: sw[0] directly active enables reset when ON

## Troubleshooting

### Program doesn't start (LEDs stuck)

1. Check DIP switch SW3-1 is OFF (reset disabled)
2. Verify blinky.mem was generated: `ls blinky.mem`
3. Rebuild from clean: `make clean && make build`

### Build fails with missing module

Ensure you're building from the project directory:
```bash
cd projects/blinky
make build
```

### Simulation issues

Run testbench:
```bash
make sim
```

GTKWave will open with waveforms. Check bootstrap_done goes high after reset.
