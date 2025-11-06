; ================================================================================
; BLINKY_SIMPLE.ASM - Minimal Intel 8008 Hardware Test
; ================================================================================
; Absolute minimal program to verify CPU is executing
;
; This program does NOTHING except continuously output patterns to the LED port.
; No RAM, no delays, no subroutines, no interrupts - just pure execution proof.
;
; If LEDs are changing AT ALL, the CPU is alive and executing instructions.
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB)
;   I/O Port 0x00 (OUT 8): LED bank (8 bits, active low)
;
; Expected behavior:
;   LEDs should rapidly cycle through patterns (far too fast to see individual
;   changes, but overall brightness should be different from all-off or all-on)
;
; ================================================================================

.8008
.org 0x0000

; ================================================================================
; RST 0 VECTOR - Interrupt Entry Point
; ================================================================================
; Even though we won't use interrupts, this must exist
; If an interrupt fires, just ignore it and continue
rst0_vector:
    ret                         ; 0x07 - Return immediately (5 cycles)
    hlt                         ; 0xFF - HLT as padding (never executed)
    hlt                         ; 0xFF - HLT as padding (never executed)

; ================================================================================
; MAIN PROGRAM - Starts at 0x0003
; ================================================================================
; Strategy: Rapidly write different patterns to LED port
; The LED port uses OUT instruction, which on 8008 uses ports 8-23
; So "OUT 8" writes to physical I/O port 0

main:
    ; Pattern 1: 0b11111110 (LED0 on, all others off)
    mvi a, 0xFE                 ; A = 0xFE (6 cycles)
    out 8                       ; Output to LED port (6 cycles)

    ; Pattern 2: 0b11111101 (LED1 on, all others off)
    mvi a, 0xFD                 ; A = 0xFD
    out 8                       ; Output to LED port

    ; Pattern 3: 0b11111011 (LED2 on, all others off)
    mvi a, 0xFB                 ; A = 0xFB
    out 8                       ; Output to LED port

    ; Pattern 4: 0b11110111 (LED3 on, all others off)
    mvi a, 0xF7                 ; A = 0xF7
    out 8                       ; Output to LED port

    ; Pattern 5: 0b11101111 (LED4 on, all others off)
    mvi a, 0xEF                 ; A = 0xEF
    out 8                       ; Output to LED port

    ; Pattern 6: 0b11011111 (LED5 on, all others off)
    mvi a, 0xDF                 ; A = 0xDF
    out 8                       ; Output to LED port

    ; Pattern 7: 0b10111111 (LED6 on, all others off)
    mvi a, 0xBF                 ; A = 0xBF
    out 8                       ; Output to LED port

    ; Pattern 8: 0b01111111 (LED7 on, all others off)
    mvi a, 0x7F                 ; A = 0x7F
    out 8                       ; Output to LED port

    ; Pattern 9: All LEDs on
    mvi a, 0x00                 ; A = 0x00 (all LEDs on - active low)
    out 8                       ; Output to LED port

    ; Pattern 10: All LEDs off
    mvi a, 0xFF                 ; A = 0xFF (all LEDs off - active low)
    out 8                       ; Output to LED port

    ; Repeat forever
    jmp main                    ; Jump back to start (9 cycles)

    ; Total loop: ~10 instructions * ~12 cycles = ~120 cycles
    ; At 455kHz CPU clock (2.2µs/cycle): 120 * 2.2µs = 264µs per loop
    ; Loop frequency: ~3.8 kHz - Too fast to see, but LEDs will be dimmer than constant-on

.end
