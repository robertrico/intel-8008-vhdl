; Intel 8008 Sign and Parity Conditional Test Program
; For AS Macro Assembler
;
; Purpose: Test sign and parity flag-based conditional instructions
;   - JP  (Jump on Positive - sign flag clear)
;   - JM  (Jump on Minus - sign flag set)
;   - JPE (Jump on Parity Even)
;   - JPO (Jump on Parity Odd)
;   - RP  (Return on Positive)
;   - RM  (Return on Minus)
;   - RPE (Return on Parity Even)
;   - RPO (Return on Parity Odd)
;
; Sign Flag: Set when result bit 7 = 1 (negative in 2's complement)
; Parity Flag: Set when result has even number of 1 bits
;
; Expected Results (in registers at halt):
;   A: 0x00 (success indicator)
;   B: 0x01 (test 1 passed marker)
;   C: 0x02 (test 2 passed marker)
;   D: 0x03 (test 3 passed marker)
;   E: 0x04 (test 4 passed marker)
;   H: 0x10 (RAM pointer high)
;   L: 0x08 (final test marker)
;

        cpu     8008new
        page    0

; Reset vector
        org     0000h
STARTUP:
        MOV     A,A                 ; NOP (PC sync)
        MOV     A,A                 ; NOP
        JMP     MAIN

; Main program
        org     0100h
MAIN:
        ;===========================================
        ; TEST 1: JP - Jump on Positive (sign=0)
        ; Load a positive number, JP should jump
        ;===========================================
        MVI     A,7Fh               ; A = 0x7F (127, positive, bit7=0)
        ORI     00h                 ; OR with 0 to set flags without changing A
        JP      TEST1_PASS          ; Should jump (sign=0, positive)
        JMP     FAIL                ; Should not reach here

TEST1_PASS:
        MVI     B,01h               ; B = 1 (test 1 passed marker)

        ;===========================================
        ; TEST 2: JM - Jump on Minus (sign=1)
        ; Load a negative number, JM should jump
        ;===========================================
        MVI     A,80h               ; A = 0x80 (128, negative, bit7=1)
        ORI     00h                 ; Set flags
        JM      TEST2_PASS          ; Should jump (sign=1, negative)
        JMP     FAIL                ; Should not reach here

TEST2_PASS:
        MVI     C,02h               ; C = 2 (test 2 passed marker)

        ;===========================================
        ; TEST 3: JP should NOT jump when negative
        ;===========================================
        MVI     A,0FFh              ; A = 0xFF (-1, negative)
        ORI     00h                 ; Set flags
        JP      FAIL                ; Should NOT jump (sign=1)
        ; Fall through is correct

        ;===========================================
        ; TEST 4: JM should NOT jump when positive
        ;===========================================
        MVI     A,01h               ; A = 0x01 (positive)
        ORI     00h                 ; Set flags
        JM      FAIL                ; Should NOT jump (sign=0)
        ; Fall through is correct

        ;===========================================
        ; TEST 5: JPE - Jump on Parity Even
        ; 0x0F = 00001111 has 4 ones (even parity)
        ;===========================================
        MVI     A,0Fh               ; A = 0x0F (4 bits set = even parity)
        ORI     00h                 ; Set flags
        JPE     TEST5_PASS          ; Should jump (parity even)
        JMP     FAIL

TEST5_PASS:
        MVI     D,03h               ; D = 3 (test 5 passed marker)

        ;===========================================
        ; TEST 6: JPO - Jump on Parity Odd
        ; 0x07 = 00000111 has 3 ones (odd parity)
        ;===========================================
        MVI     A,07h               ; A = 0x07 (3 bits set = odd parity)
        ORI     00h                 ; Set flags
        JPO     TEST6_PASS          ; Should jump (parity odd)
        JMP     FAIL

TEST6_PASS:
        MVI     E,04h               ; E = 4 (test 6 passed marker)

        ;===========================================
        ; TEST 7: JPE should NOT jump on odd parity
        ;===========================================
        MVI     A,01h               ; A = 0x01 (1 bit set = odd parity)
        ORI     00h                 ; Set flags
        JPE     FAIL                ; Should NOT jump
        ; Fall through is correct

        ;===========================================
        ; TEST 8: JPO should NOT jump on even parity
        ;===========================================
        MVI     A,03h               ; A = 0x03 (2 bits set = even parity)
        ORI     00h                 ; Set flags
        JPO     FAIL                ; Should NOT jump
        ; Fall through is correct

        ;===========================================
        ; TEST 9: RP - Return on Positive
        ; Call subroutine with positive value
        ;===========================================
        MVI     A,40h               ; A = 0x40 (positive)
        ORI     00h                 ; Set flags (positive)
        CALL    SUB_RP              ; Call subroutine
        CPI     0AAh                ; Check A = 0xAA (marker)
        JNZ     FAIL

        ;===========================================
        ; TEST 10: RM - Return on Minus
        ; Call subroutine with negative value
        ;===========================================
        MVI     A,0C0h              ; A = 0xC0 (negative, bit7=1)
        ORI     00h                 ; Set flags (negative)
        CALL    SUB_RM              ; Call subroutine
        CPI     0BBh                ; Check A = 0xBB (marker)
        JNZ     FAIL

        ;===========================================
        ; TEST 11: RPE - Return on Parity Even
        ; Call subroutine with even parity value
        ;===========================================
        MVI     A,33h               ; A = 0x33 = 00110011 (4 bits = even)
        ORI     00h                 ; Set flags
        CALL    SUB_RPE             ; Call subroutine
        CPI     0CCh                ; Check A = 0xCC (marker)
        JNZ     FAIL

        ;===========================================
        ; TEST 12: RPO - Return on Parity Odd
        ; Call subroutine with odd parity value
        ;===========================================
        MVI     A,31h               ; A = 0x31 = 00110001 (3 bits = odd)
        ORI     00h                 ; Set flags
        CALL    SUB_RPO             ; Call subroutine
        CPI     0DDh                ; Check A = 0xDD (marker)
        JNZ     FAIL

        ;===========================================
        ; FINAL: Set success indicators
        ;===========================================
        MVI     H,10h               ; H = 0x10 (RAM pointer marker)
        MVI     L,08h               ; L = 0x08 (final test marker)
        MVI     A,00h               ; A = 0 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh              ; A = 0xFF (failure indicator)

DONE:
        HLT

;-----------------------------------------------------------------------------
; SUB_RP: Subroutine that returns if sign is positive (bit7=0)
; Returns with A = 0xAA as marker
;-----------------------------------------------------------------------------
SUB_RP:
        MVI     A,0AAh              ; Set marker
        RP                          ; Return if positive (sign=0)
        MVI     A,0FFh              ; Should not reach here
        RET

;-----------------------------------------------------------------------------
; SUB_RM: Subroutine that returns if sign is minus (bit7=1)
; Returns with A = 0xBB as marker
;-----------------------------------------------------------------------------
SUB_RM:
        MVI     A,0BBh              ; Set marker
        RM                          ; Return if minus (sign=1)
        MVI     A,0FFh              ; Should not reach here
        RET

;-----------------------------------------------------------------------------
; SUB_RPE: Subroutine that returns if parity is even
; Returns with A = 0xCC as marker
;-----------------------------------------------------------------------------
SUB_RPE:
        MVI     A,0CCh              ; Set marker
        RPE                         ; Return if parity even
        MVI     A,0FFh              ; Should not reach here
        RET

;-----------------------------------------------------------------------------
; SUB_RPO: Subroutine that returns if parity is odd
; Returns with A = 0xDD as marker
;-----------------------------------------------------------------------------
SUB_RPO:
        MVI     A,0DDh              ; Set marker
        RPO                         ; Return if parity odd
        MVI     A,0FFh              ; Should not reach here
        RET

        end
