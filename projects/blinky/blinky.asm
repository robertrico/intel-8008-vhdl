; ================================================================================
; BLINKY.ASM - Intel 8008 Hardware Validation Program
; ================================================================================
; First hardware test for Intel 8008 VHDL implementation on FPGA
;
; Functionality:
;   - LED blinks at rate determined by RAM variable
;   - Button press triggers interrupt, changes blink rate
;   - Tests: ROM, RAM, I/O, interrupts, all basic instructions
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB)
;   RAM: 0x0800-0x0BFF (1KB)
;   I/O Ports:
;     Port 0x00 (OUT): LED bank (8 bits, active low)
;     Port 0x01 (INP): Button input (bit 0 = interrupt button)
;
; Copyright (c) 2025 Robert Rico
; ================================================================================

.8008
.org 0x0000

; ================================================================================
; INTERRUPT VECTOR TABLE
; ================================================================================
; RST 0 at 0x0000 - Hardware interrupt vector
; When INT pin is asserted, CPU jumps here
interrupt_vector:
    jmp interrupt_handler       ; Jump to interrupt handler (3 bytes: 0x44, low, high)

; ================================================================================
; MAIN PROGRAM
; ================================================================================
; Starts at 0x0003 (after interrupt vector)
main:
    ; Initialize blink rate variable in RAM
    mvi a, 0x01                 ; Default blink rate (fast: 1 * 10ms = 10ms)
    mvi h, 0x08                 ; RAM base address high byte (0x0800)
    mvi l, 0x00                 ; RAM base address low byte
    mov m, a                    ; Store rate to RAM[0x0800]

    ; Note: 8008 has no explicit interrupt enable/disable
    ; Interrupts are always enabled and sampled during T1 states

; ================================================================================
; MAIN LOOP - Blink LED at current rate
; ================================================================================
main_loop:
    ; Read current blink rate from RAM
    mvi h, 0x08                 ; RAM address high
    mvi l, 0x00                 ; RAM address low
    mov a, m                    ; A = blink_rate from RAM[0x0800]

    ; Turn LED0 ON (active low, so write 0xFE)
    mvi b, 0xFE                 ; LED0 = 0 (on), all others = 1 (off)
    mov a, b                    ; Move to accumulator for output
    out 8                       ; Write to LED port (OUT uses ports 8-23)

    ; Delay for (rate * 1ms) with LED on
    mvi h, 0x08
    mvi l, 0x00
    mov a, m                    ; Reload rate
    mov b, a                    ; B = delay count
delay_on:
    call delay_1ms              ; Call 1ms delay subroutine
    dcr b                       ; Decrement counter
    jnz delay_on                ; Loop until B = 0

    ; Turn LED0 OFF (active low, so write 0xFF)
    mvi a, 0xFF                 ; All LEDs off
    out 8                       ; Write to LED port (OUT uses ports 8-23)

    ; Delay for (rate * 1ms) with LED off
    mvi h, 0x08
    mvi l, 0x00
    mov a, m                    ; Reload rate from RAM
    mov b, a                    ; B = delay count
delay_off:
    call delay_1ms              ; Call 1ms delay subroutine
    dcr b                       ; Decrement counter
    jnz delay_off               ; Loop until B = 0

    jmp main_loop               ; Repeat forever

; ================================================================================
; INTERRUPT HANDLER
; ================================================================================
; Called when button edge is detected (both rising and falling)
; Changes the blink rate based on button state
interrupt_handler:
    ; Save accumulator to RAM (8008 has no PUSH instruction)
    mvi h, 0x08                 ; High byte of save location
    mvi l, 0xFF                 ; Low byte (0x08FF)
    mov m, a                    ; Save A to RAM[0x08FF]

    ; Read button state from I/O port
    in 1                        ; Read button input port into A (INP uses ports 0-7)
    ani 0x01                    ; Mask bit 0 (isolate button state)

    ; Check button state and update rate accordingly
    jz button_released          ; If bit 0 = 0, button released

button_pressed:
    ; Button pressed: Set slow blink rate
    mvi a, 0x0A                 ; Slow rate (10 * 10ms = 100ms period, 5 Hz)
    jmp store_rate

button_released:
    ; Button released: Set fast blink rate
    mvi a, 0x01                 ; Fast rate (1 * 10ms = 10ms period, 50 Hz)

store_rate:
    ; Store new rate to RAM
    mvi h, 0x08                 ; RAM address high
    mvi l, 0x00                 ; RAM address low
    mov m, a                    ; Update RAM[0x0800] with new rate

    ; Restore accumulator from RAM
    mvi h, 0x08                 ; High byte of save location
    mvi l, 0xFF                 ; Low byte (0x08FF)
    mov a, m                    ; Restore A from RAM[0x08FF]

    ret                         ; Return from interrupt (RET = 0x07)

; ================================================================================
; DELAY SUBROUTINE
; ================================================================================
; Approximately 100ms delay at 455 kHz CPU clock (2.2µs per cycle)
; CPU cycle time: 2.2µs (100MHz / 220 clocks per 8008 cycle)
; Target: 100ms = 100,000µs
; Cycles needed: 100,000µs / 2.2µs ≈ 45,454 cycles
;
; Strategy: Use D and E registers for nested loop (preserve A, B, C)
;   Outer loop (D): 177 iterations (0xB1)
;   Inner loop (E): 255 iterations (0xFF)
;   Total: 177 * 255 ≈ 45,000 cycles ≈ 100ms
;
delay_1ms:
    mvi d, 0xB1                 ; Outer loop: 177 iterations

delay_outer:
    mvi e, 0xFF                 ; Inner loop: 255 iterations

delay_loop:
    dcr e                       ; Decrement E (5 cycles)
    jnz delay_loop              ; Jump if not zero (9 cycles taken, 7 not taken)

    dcr d                       ; Decrement outer counter
    jnz delay_outer             ; Jump if not zero

    ret                         ; Return to caller (5 cycles)

.end
