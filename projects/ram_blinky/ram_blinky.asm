; ================================================================================
; RAM_BLINKY.ASM - RAM Read/Write Test with LED Feedback
; ================================================================================
; Tests RAM write and read operations with visible LED results
; HEARTBEAT DEPENDS ON RAM: If RAM fails, blinking stops!
;
; Memory Map:
;   ROM: 0x0000-0x0FFF (4KB)
;   RAM: 0x1000-0x13FF (1KB)
;   I/O Port 8 (OUT 8): LED bank (8 bits, active low)
;
; LED Assignment (active low: 0=ON, 1=OFF):
;   LED0-5: Individual test results (see below)
;   LED6: All tests passed indicator
;   LED7: RAM-dependent heartbeat (ONLY blinks if RAM works!)
;
; Test Sequence (write-all then read-all for persistence check):
;   1. Write 0x55 to RAM[0x1000]
;   2. Write 0xAA to RAM[0x1001]
;   3. Write 0x42 to RAM[0x1002]
;   4. Read RAM[0x1000], verify 0x55 -> LED0, LED1
;   5. Read RAM[0x1001], verify 0xAA -> LED2, LED3
;   6. Read RAM[0x1002], verify 0x42 -> LED4, LED5
;   7. If all pass -> LED6, toggle heartbeat using RAM
;
; HEARTBEAT MECHANISM:
;   The heartbeat state is stored IN RAM at 0x1003.
;   If RAM read/write fails, heartbeat cannot toggle -> LED7 freezes.
;   A blinking LED7 PROVES RAM is working!
;
; ================================================================================

        cpu 8008new
        org 0000h

; RAM addresses (must be in range 0x1000-0x13FF)
RAM_TEST_0      equ 1000h       ; Test location 0
RAM_TEST_1      equ 1001h       ; Test location 1
RAM_TEST_2      equ 1002h       ; Test location 2
RAM_HEARTBEAT   equ 1003h       ; Heartbeat state stored in RAM!

; Test patterns
PATTERN_1       equ 55h         ; 01010101
PATTERN_2       equ 0AAh        ; 10101010
PATTERN_3       equ 42h         ; 01000010

; ================================================================================
; RST 0 VECTOR
; ================================================================================
rst0_vector:
        jmp main

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
        ; Initialize heartbeat in RAM to 0x00
        mvi h,10h
        mvi l,03h               ; Address 0x1003 (RAM_HEARTBEAT)
        mvi a,00h
        mov m,a                 ; RAM[0x1003] = 0x00

test_loop:
        mvi e,00h               ; E = test result accumulator

        ; =====================
        ; PHASE 1: WRITE ALL TEST PATTERNS
        ; =====================

        ; Write 0x55 to RAM[0x1000]
        mvi h,10h
        mvi l,00h
        mvi a,PATTERN_1
        mov m,a

        ; Write 0xAA to RAM[0x1001]
        mvi l,01h
        mvi a,PATTERN_2
        mov m,a

        ; Write 0x42 to RAM[0x1002]
        mvi l,02h
        mvi a,PATTERN_3
        mov m,a

        ; =====================
        ; PHASE 2: READ ALL AND VERIFY (tests persistence)
        ; =====================

        ; Read RAM[0x1000], verify 0x55
        mvi l,00h
        mov a,m
        cpi PATTERN_1
        jnz read_test_1

        ; Test 0 passed - LED0 and LED1 ON
        mov a,e
        ori 03h                 ; Set bits 0,1
        mov e,a

read_test_1:
        ; Read RAM[0x1001], verify 0xAA
        mvi l,01h
        mov a,m
        cpi PATTERN_2
        jnz read_test_2

        ; Test 1 passed - LED2 and LED3 ON
        mov a,e
        ori 0Ch                 ; Set bits 2,3
        mov e,a

read_test_2:
        ; Read RAM[0x1002], verify 0x42
        mvi l,02h
        mov a,m
        cpi PATTERN_3
        jnz check_all

        ; Test 2 passed - LED4 and LED5 ON
        mov a,e
        ori 30h                 ; Set bits 4,5
        mov e,a

        ; =====================
        ; CHECK: All tests passed?
        ; =====================
check_all:
        mov a,e
        cpi 3Fh                 ; All 6 bits set?
        jnz output_leds

        ; All tests passed! Set LED6
        mov a,e
        ori 40h
        mov e,a

        ; =====================
        ; HEARTBEAT: Toggle using RAM (proves RAM works!)
        ; =====================
        ; Read current heartbeat state from RAM
        mvi l,03h               ; Address 0x1003
        mov a,m                 ; A = RAM[0x1003]
        xri 80h                 ; Toggle bit 7
        mov m,a                 ; Write back to RAM
        mov d,a                 ; D = heartbeat state
        jmp combine_output

output_leds:
        ; Tests failed - heartbeat frozen (D unchanged)
        mvi d,00h               ; No heartbeat if tests fail

combine_output:
        ; Combine test results (E) with heartbeat (D)
        mov a,e
        ora d                   ; OR in heartbeat bit

        ; Invert for active-low LEDs
        xri 0FFh

        ; Output to LEDs
        out 8

        ; Delay
        call delay

        ; Loop forever
        jmp test_loop

; ================================================================================
; DELAY SUBROUTINE
; ================================================================================
delay:
        mvi b,200
delay_outer:
        mvi c,80
delay_inner:
        dcr c
        jnz delay_inner
        dcr b
        jnz delay_outer
        ret

        end
