; ================================================================================
; BLINKY.ASM - Single LED Blink Test
; ================================================================================
; Simple visible LED blink on LED0 (pin E16 via debug_led on board)
;
; Memory Map:
;   ROM: 0x0000-0x07FF (2KB)
;   I/O Port 8 (OUT 8): LED bank (8 bits, active low)
;
; Expected behavior:
;   LED0 blinks continuously (on for 0.5s, off for 0.5s), forever
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
blink_loop:
    ; Turn LED0 ON (active low, so output 0xFE = 11111110)
    mvi a, 0xFE
    out 8

    ; Delay ~0.5 seconds
    call delay

    ; Turn LED0 OFF (active low, so output 0xFF = 11111111)
    mvi a, 0xFF
    out 8

    ; Delay ~0.5 seconds
    call delay

    ; Loop forever
    jmp blink_loop

; ================================================================================
; DELAY SUBROUTINE
; ================================================================================
; Creates approximately 0.5 second delay
; At 455kHz CPU clock: Need about 227,500 cycles for 0.5s
; Using nested loops: outer * inner * cycles_per_loop
;
; Loop timing:
;   dcr b: 5 cycles
;   jnz: 9 cycles (taken) or 9 cycles (not taken)
;   Total per inner loop: ~14 cycles
;
; Target: 227,500 cycles
; Outer loop = 200, Inner loop = 80
; 200 * 80 * 14 = 224,000 cycles ≈ 0.49 seconds
;
delay:
    mvi b, 200                  ; Outer loop counter (6 cycles)
delay_outer:
    mvi c, 80                   ; Inner loop counter (6 cycles)
delay_inner:
    dcr c                       ; Decrement C (5 cycles)
    jnz delay_inner            ; Jump if not zero (9 cycles)

    dcr b                       ; Decrement B (5 cycles)
    jnz delay_outer            ; Jump if not zero (9 cycles)

    ret                         ; Return from subroutine (5 cycles)

.end
