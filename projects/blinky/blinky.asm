; ================================================================================
; BLINKY.ASM - b8008 LED Blink Demo (Project Template)
; ================================================================================
; Copy and modify this file for your own programs.
;
; Memory Map:
;   ROM: 0x0000-0x0FFF (4KB)
;   RAM: 0x1000-0x13FF (1KB)
;   I/O Port 8 (OUT 8): LED bank (8 bits, active low)
;
; This example blinks LED0. Replace with your own code.
; ================================================================================

        cpu 8008new
        org 0000h

; ================================================================================
; RST 0 VECTOR - REQUIRED Entry Point
; ================================================================================
; The 8008 requires a bootstrap interrupt to start. This vectors to address 0.
; You MUST have 'jmp main' here - do not remove or modify this.
;
rst0_vector:
        jmp main                ; Jump to main program

; ================================================================================
; MAIN PROGRAM - Your code goes here
; ================================================================================
main:
        ; --- Initialization ---
        ; Put any one-time setup here

main_loop:
        ; --- Main loop ---
        ; This example blinks LED0. Replace with your code.

        ; Turn LED0 ON (active low: 0 = ON)
        mvi a,0FEh              ; 11111110 = LED0 on, others off
        out 8

        call delay

        ; Turn LED0 OFF (active low: 1 = OFF)
        mvi a,0FFh              ; 11111111 = all LEDs off
        out 8

        call delay

        jmp main_loop           ; Loop forever

; ================================================================================
; DELAY SUBROUTINE
; ================================================================================
; Approximately 0.5 second delay at 455kHz CPU clock.
; Uses registers B and C (clobbers them).
;
delay:
        mvi b,200               ; Outer loop counter
delay_outer:
        mvi c,80                ; Inner loop counter
delay_inner:
        dcr c
        jnz delay_inner

        dcr b
        jnz delay_outer

        ret

        end
