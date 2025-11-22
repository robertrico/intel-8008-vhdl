; ================================================================================
; CYLON.ASM - Cylon/Knight Rider LED Effect
; ================================================================================
; Creates a bouncing LED pattern (Cylon eye effect) on 8 LEDs
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB)
;   RAM: 0x0800-0x0BFF (1KB) - used for stack
;   I/O Port 8 (OUT 8): LED bank (8 bits, active low)
;
; Expected behavior:
;   Single LED sweeps left to right, then right to left, continuously
;   Pattern: LED0 -> LED1 -> LED2 -> ... -> LED7 -> LED6 -> ... -> LED0
;
; Active-low LED encoding:
;   0xFE = 11111110 = LED0 on
;   0xFD = 11111101 = LED1 on
;   0xFB = 11111011 = LED2 on
;   0xF7 = 11110111 = LED3 on
;   0xEF = 11101111 = LED4 on
;   0xDF = 11011111 = LED5 on
;   0xBF = 10111111 = LED6 on
;   0x7F = 01111111 = LED7 on
;
; ================================================================================

.8008
.org 0x0000

; ================================================================================
; RST 0 VECTOR - Interrupt Entry Point
; ================================================================================
rst0_vector:
    jmp main                    ; Jump to main program (handles startup interrupt)
    ; Note: JMP is 3 bytes (44 LL HH), fills the RST 0 vector perfectly

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
    ; Initialize stack pointer to top of RAM (0x0BFF)
    ; Note: 8008 uses internal stack pointer, no initialization needed

cylon_loop:
    ; ============================================================================
    ; SWEEP LEFT (LED0 -> LED7)
    ; ============================================================================
    ; Start with LED0 on (0xFE)
    mvi a, 0xFE
    out 8
    call delay_short

    ; LED1 on (0xFD)
    mvi a, 0xFD
    out 8
    call delay_short

    ; LED2 on (0xFB)
    mvi a, 0xFB
    out 8
    call delay_short

    ; LED3 on (0xF7)
    mvi a, 0xF7
    out 8
    call delay_short

    ; LED4 on (0xEF)
    mvi a, 0xEF
    out 8
    call delay_short

    ; LED5 on (0xDF)
    mvi a, 0xDF
    out 8
    call delay_short

    ; LED6 on (0xBF)
    mvi a, 0xBF
    out 8
    call delay_short

    ; LED7 on (0x7F)
    mvi a, 0x7F
    out 8
    call delay_short

    ; ============================================================================
    ; SWEEP RIGHT (LED7 -> LED0)
    ; ============================================================================
    ; LED6 on (0xBF) - going back
    mvi a, 0xBF
    out 8
    call delay_short

    ; LED5 on (0xDF)
    mvi a, 0xDF
    out 8
    call delay_short

    ; LED4 on (0xEF)
    mvi a, 0xEF
    out 8
    call delay_short

    ; LED3 on (0xF7)
    mvi a, 0xF7
    out 8
    call delay_short

    ; LED2 on (0xFB)
    mvi a, 0xFB
    out 8
    call delay_short

    ; LED1 on (0xFD)
    mvi a, 0xFD
    out 8
    call delay_short

    ; Back to LED0, loop continues
    jmp cylon_loop

; ================================================================================
; DELAY SUBROUTINE - Shorter delay for smooth animation
; ================================================================================
; Creates approximately 0.15 second delay for smooth Cylon effect
; At 455kHz CPU clock: Need about 68,250 cycles for 0.15s
; Using nested loops: outer * inner * cycles_per_loop
;
; Loop timing:
;   dcr c: 5 cycles
;   jnz: 9 cycles (taken)
;   Total per inner loop: ~14 cycles
;
; Target: 68,250 cycles
; Outer loop = 70, Inner loop = 70
; 70 * 70 * 14 = 68,600 cycles ≈ 0.15 seconds
;
delay_short:
    mvi b, 70                   ; Outer loop counter (6 cycles)
delay_outer:
    mvi c, 70                   ; Inner loop counter (6 cycles)
delay_inner:
    dcr c                       ; Decrement C (5 cycles)
    jnz delay_inner             ; Jump if not zero (9 cycles)

    dcr b                       ; Decrement B (5 cycles)
    jnz delay_outer             ; Jump if not zero (9 cycles)

    ret                         ; Return from subroutine (5 cycles)

.end
