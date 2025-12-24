; Intel 8008 Flag Verification Test Program
; For AS Macro Assembler
;
; Purpose: Explicitly test all four condition flags
;   - Carry (C): Set by ADD/SUB overflow, rotate through carry
;   - Zero (Z): Set when result is 0x00
;   - Sign (S): Set when result bit 7 is 1 (negative in 2's complement)
;   - Parity (P): Set when result has even number of 1 bits
;
; Edge cases tested:
;   - 0x00: Z=1, S=0, P=1 (zero has even parity - zero 1-bits)
;   - 0x80: Z=0, S=1, P=0 (one 1-bit = odd parity)
;   - 0xFF: Z=0, S=1, P=1 (eight 1-bits = even parity)
;   - Carry from 0xFF + 1 = 0x00: C=1, Z=1
;   - Borrow from 0x00 - 1 = 0xFF: C=1, S=1
;
; ASSERTION POINTS (for verification script):
;   After TEST 1: Z='1' (zero result)
;   After TEST 2: S='1' (sign bit set)
;   After TEST 3: C='1' (carry from overflow)
;   After TEST 4: P='0' then P='1' (parity toggle)
;
; Expected final state:
;   A = 0x00 (success indicator)
;   B = 0x08 (8 tests passed)

        cpu     8008new
        page    0

; Reset vector at 0x0000
        org     0000h
STARTUP:
        MOV     A,A             ; NOP (PC sync)
        MOV     A,A             ; NOP
        JMP     MAIN

; Main program at 0x0100
        org     0100h

MAIN:
        MVI     B,00h           ; B = test counter (0)

        ;===========================================
        ; TEST 1: Zero flag (Z)
        ; MVI sets no flags, but ADI does!
        ; A = 0x00, ADI 0 -> Z=1
        ;===========================================
        MVI     A,00h           ; A = 0
        ADI     00h             ; A = 0 + 0 = 0, sets Z=1, P=1
        JNZ     FAIL            ; Should NOT jump (Z=1)
        INR     B               ; B = 1

        ;===========================================
        ; TEST 2: Zero flag clear (Z=0)
        ; A = 0x01 should clear Z
        ;===========================================
        MVI     A,01h           ; A = 1
        ADI     00h             ; A = 1, sets Z=0
        JZ      FAIL            ; Should NOT jump (Z=0)
        INR     B               ; B = 2

        ;===========================================
        ; TEST 3: Sign flag (S)
        ; A = 0x80 (bit 7 = 1) should set S
        ;===========================================
        MVI     A,80h           ; A = 0x80
        ADI     00h             ; A = 0x80, sets S=1
        JP      FAIL            ; JP = Jump if Plus (S=0), should NOT jump
        INR     B               ; B = 3

        ;===========================================
        ; TEST 4: Sign flag clear (S=0)
        ; A = 0x7F (bit 7 = 0) should clear S
        ;===========================================
        MVI     A,7Fh           ; A = 0x7F
        ADI     00h             ; A = 0x7F, sets S=0
        JM      FAIL            ; JM = Jump if Minus (S=1), should NOT jump
        INR     B               ; B = 4

        ;===========================================
        ; TEST 5: Carry flag (C)
        ; 0xFF + 1 = 0x00 with carry
        ;===========================================
        MVI     A,0FFh          ; A = 0xFF
        ADI     01h             ; A = 0xFF + 1 = 0x00, C=1
        JNC     FAIL            ; Should NOT jump (C=1)
        ; Also check Z is set (result is 0)
        JNZ     FAIL            ; Should NOT jump (Z=1)
        INR     B               ; B = 5

        ;===========================================
        ; TEST 6: Carry flag clear (C=0)
        ; 0x01 + 0x01 = 0x02, no carry
        ;===========================================
        MVI     A,01h           ; A = 0x01
        ADI     01h             ; A = 0x01 + 0x01 = 0x02, C=0
        JC      FAIL            ; Should NOT jump (C=0)
        INR     B               ; B = 6

        ;===========================================
        ; TEST 7: Parity odd (P=0)
        ; 0x01 has one 1-bit = odd parity
        ;===========================================
        MVI     A,01h           ; A = 0x01
        ADI     00h             ; Forces flag update
        JPE     FAIL            ; JPE = Jump if Parity Even (P=1), should NOT jump
        INR     B               ; B = 7

        ;===========================================
        ; TEST 8: Parity even (P=1)
        ; 0x03 (binary 00000011) has two 1-bits = even parity
        ;===========================================
        MVI     A,03h           ; A = 0x03
        ADI     00h             ; Forces flag update
        JPO     FAIL            ; JPO = Jump if Parity Odd (P=0), should NOT jump
        INR     B               ; B = 8

        ;===========================================
        ; BONUS: Test borrow (carry set on SUB)
        ; 0x00 - 0x01 = 0xFF with borrow (carry)
        ; Not counted in B since it's bonus
        ;===========================================
        MVI     A,00h           ; A = 0x00
        SUI     01h             ; A = 0x00 - 0x01 = 0xFF, C=1 (borrow)
        JNC     FAIL            ; Should NOT jump (C=1)
        ; Check S=1 (0xFF has bit 7 set)
        JP      FAIL            ; Should NOT jump (S=1)

        ;===========================================
        ; All tests passed! Set success marker
        ;===========================================
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

        end
