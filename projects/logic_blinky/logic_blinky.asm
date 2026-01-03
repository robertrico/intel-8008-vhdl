; ================================================================================
; LOGIC_BLINKY.ASM - ALU Logical Operations Test for b8008
; ================================================================================
; Tests AND, OR, XOR with visible LED feedback
;
; Memory Map:
;   ROM: 0x0000-0x0FFF (4KB)
;   I/O Port 8 (OUT 8): LED bank (8 bits, active low)
;
; LED Pattern (active low - 0=ON, 1=OFF):
;   Phase 1: XOR result  -> 0xFF XOR 0x0F = 0xF0 -> LEDs: 00001111 (4 LEDs ON)
;   Phase 2: AND result  -> 0xFF AND 0x3C = 0x3C -> LEDs: 11000011 (4 LEDs ON)
;   Phase 3: OR result   -> 0xC0 OR  0x03 = 0xC3 -> LEDs: 00111100 (4 LEDs ON)
;   Phase 4: Complement  -> 0xAA XOR 0xFF = 0x55 -> LEDs: 10101010 (4 LEDs ON)
;
; Each phase shows 4 LEDs ON in different positions.
; If logical ops fail, pattern will be wrong or stuck.
;
; ================================================================================

        cpu 8008new
        org 0000h

; ================================================================================
; RST 0 VECTOR - Interrupt Entry Point
; ================================================================================
rst0_vector:
        jmp main                ; Jump to main program (handles startup interrupt)
        ; Note: JMP is 3 bytes (44 LL HH), fills the RST 0 vector perfectly

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
loop:
        ; --- Phase 1: XOR test ---
        ; 0xFF XOR 0x0F = 0xF0 -> LEDs 0-3 ON (bottom 4)
        mvi a,0FFh
        xri 0Fh
        out 8
        call delay

        ; --- Phase 2: AND test ---
        ; 0xFF AND 0x3C = 0x3C -> LEDs 6,7,0,1 ON (top 2 + bottom 2)
        mvi a,0FFh
        ani 3Ch
        out 8
        call delay

        ; --- Phase 3: OR test ---
        ; 0xC0 OR 0x03 = 0xC3 -> LEDs 2,3,4,5 ON (middle 4)
        mvi a,0C0h
        ori 03h
        out 8
        call delay

        ; --- Phase 4: XOR complement test ---
        ; 0xAA XOR 0xFF = 0x55 -> LEDs 1,3,5,7 ON (alternating)
        mvi a,0AAh
        xri 0FFh
        out 8
        call delay

        jmp loop

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
; 200 * 80 * 14 = 224,000 cycles ~ 0.49 seconds
;
delay:
        mvi b,200               ; Outer loop counter (6 cycles)
delay_outer:
        mvi c,80                ; Inner loop counter (6 cycles)
delay_inner:
        dcr c                   ; Decrement C (5 cycles)
        jnz delay_inner         ; Jump if not zero (9 cycles)

        dcr b                   ; Decrement B (5 cycles)
        jnz delay_outer         ; Jump if not zero (9 cycles)

        ret                     ; Return from subroutine (5 cycles)

        end
