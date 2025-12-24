; Intel 8008 Sign/Parity Conditional Call Test Program
; For AS Macro Assembler
;
; Purpose: Test sign and parity flag-based conditional call instructions
;   - CP  (Call on Positive / Sign=0)
;   - CM  (Call on Minus / Sign=1)
;   - CPO (Call on Parity Odd)
;   - CPE (Call on Parity Even)
;
; Sign Flag: Set when result bit 7 = 1 (negative in 2's complement)
; Parity Flag: Set when result has even number of 1 bits
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After CP    - C=0xAA (called on positive)
;   CP2:  After CM    - D=0xBB (called on minus)
;   CP3:  After CPO   - E=0xCC (called on odd parity)
;   CP4:  After CPE   - H=0xDD (called on even parity)
;   CP5:  After CP!   - L=0x00 (did not call on negative)
;   CP6:  After CM!   - L=0x00 (did not call on positive)
;   CP7:  After CPE!  - L=0x00 (did not call on odd parity)
;   CP8:  After CPO!  - L=0x00 (did not call on even parity)
;   CP9:  Final       - A=0x00 (success)
;
; Expected Results (in registers at halt):
;   A: 0x00 (success indicator)
;   B: 0x04 (4 tests completed)

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

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
        MVI     C,00h           ; C = CP marker (will be 0xAA)
        MVI     D,00h           ; D = CM marker (will be 0xBB)
        MVI     E,00h           ; E = CPO marker (will be 0xCC)

        ;===========================================
        ; TEST 1: CP - Call on Positive (sign=0)
        ; Load a positive number, CP should call
        ;===========================================
        MVI     A,7Fh           ; A = 0x7F (127, positive, bit7=0)
        ORI     00h             ; OR with 0 to set flags without changing A
        CP      SUB_CP          ; Should call (sign=0, positive)
        ; CHECKPOINT 1: Verify CP called
        MVI     A,01h
        OUT     CHKPT           ; CP1: C=0xAA

        ; Check that C was set by subroutine
        MOV     A,C
        CPI     0AAh            ; Check C = 0xAA
        JNZ     FAIL            ; Fail if C != 0xAA
        INR     B               ; Test 1 passed, B = 1

        ;===========================================
        ; TEST 2: CM - Call on Minus (sign=1)
        ; Load a negative number, CM should call
        ;===========================================
        MVI     A,80h           ; A = 0x80 (128, negative, bit7=1)
        ORI     00h             ; Set flags
        CM      SUB_CM          ; Should call (sign=1, negative)
        ; CHECKPOINT 2: Verify CM called
        MVI     A,02h
        OUT     CHKPT           ; CP2: D=0xBB

        ; Check that D was set by subroutine
        MOV     A,D
        CPI     0BBh            ; Check D = 0xBB
        JNZ     FAIL            ; Fail if D != 0xBB
        INR     B               ; Test 2 passed, B = 2

        ;===========================================
        ; TEST 3: CPO - Call on Parity Odd
        ; 0x07 = 00000111 has 3 ones (odd parity)
        ;===========================================
        MVI     A,07h           ; A = 0x07 (3 bits set = odd parity)
        ORI     00h             ; Set flags
        CPO     SUB_CPO         ; Should call (parity odd)
        ; CHECKPOINT 3: Verify CPO called
        MVI     A,03h
        OUT     CHKPT           ; CP3: E=0xCC

        ; Check that E was set by subroutine
        MOV     A,E
        CPI     0CCh            ; Check E = 0xCC
        JNZ     FAIL            ; Fail if E != 0xCC
        INR     B               ; Test 3 passed, B = 3

        ;===========================================
        ; TEST 4: CPE - Call on Parity Even
        ; 0x0F = 00001111 has 4 ones (even parity)
        ;===========================================
        MVI     A,0Fh           ; A = 0x0F (4 bits set = even parity)
        ORI     00h             ; Set flags
        CPE     SUB_CPE         ; Should call (parity even)
        ; CHECKPOINT 4: Verify CPE called
        MVI     A,04h
        OUT     CHKPT           ; CP4: H=0xDD

        ; Check that H was set by subroutine
        MOV     A,H
        CPI     0DDh            ; Check H = 0xDD
        JNZ     FAIL            ; Fail if H != 0xDD
        INR     B               ; Test 4 passed, B = 4

        ;===========================================
        ; TEST 5: CP should NOT call when negative
        ;===========================================
        MVI     L,00h           ; L = 0 (will be set to 0xEE if CP incorrectly calls)
        MVI     A,0FFh          ; A = 0xFF (-1, negative)
        ORI     00h             ; Set flags
        CP      SUB_BAD_CP      ; Should NOT call (sign=1)
        ; CHECKPOINT 5: Verify CP did not call
        MVI     A,05h
        OUT     CHKPT           ; CP5: L=0x00

        ; Check L was NOT modified
        MOV     A,L
        CPI     00h             ; L should still be 0
        JNZ     FAIL            ; Fail if L was modified

        ;===========================================
        ; TEST 6: CM should NOT call when positive
        ;===========================================
        MVI     L,00h           ; Reset L
        MVI     A,01h           ; A = 0x01 (positive)
        ORI     00h             ; Set flags
        CM      SUB_BAD_CM      ; Should NOT call (sign=0)
        ; CHECKPOINT 6: Verify CM did not call
        MVI     A,06h
        OUT     CHKPT           ; CP6: L=0x00

        ; Check L was NOT modified
        MOV     A,L
        CPI     00h             ; L should still be 0
        JNZ     FAIL            ; Fail if L was modified

        ;===========================================
        ; TEST 7: CPE should NOT call on odd parity
        ;===========================================
        MVI     L,00h           ; Reset L
        MVI     A,01h           ; A = 0x01 (1 bit set = odd parity)
        ORI     00h             ; Set flags
        CPE     SUB_BAD_CPE     ; Should NOT call (parity odd)
        ; CHECKPOINT 7: Verify CPE did not call
        MVI     A,07h
        OUT     CHKPT           ; CP7: L=0x00

        ; Check L was NOT modified
        MOV     A,L
        CPI     00h             ; L should still be 0
        JNZ     FAIL            ; Fail if L was modified

        ;===========================================
        ; TEST 8: CPO should NOT call on even parity
        ;===========================================
        MVI     L,00h           ; Reset L
        MVI     A,03h           ; A = 0x03 (2 bits set = even parity)
        ORI     00h             ; Set flags
        CPO     SUB_BAD_CPO     ; Should NOT call (parity even)
        ; CHECKPOINT 8: Verify CPO did not call
        MVI     A,08h
        OUT     CHKPT           ; CP8: L=0x00

        ; Check L was NOT modified
        MOV     A,L
        CPI     00h             ; L should still be 0
        JNZ     FAIL            ; Fail if L was modified

        ;===========================================
        ; All tests passed! Set success marker
        ;===========================================
        ; CHECKPOINT 9: Final success
        MVI     A,09h
        OUT     CHKPT           ; CP9: success
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

;-----------------------------------------------------------------------------
; SUB_CP: Subroutine called by CP (Call on Positive)
; Sets C = 0xAA as marker
;-----------------------------------------------------------------------------
SUB_CP:
        MVI     C,0AAh          ; Set marker
        RET

;-----------------------------------------------------------------------------
; SUB_CM: Subroutine called by CM (Call on Minus)
; Sets D = 0xBB as marker
;-----------------------------------------------------------------------------
SUB_CM:
        MVI     D,0BBh          ; Set marker
        RET

;-----------------------------------------------------------------------------
; SUB_CPO: Subroutine called by CPO (Call on Parity Odd)
; Sets E = 0xCC as marker
;-----------------------------------------------------------------------------
SUB_CPO:
        MVI     E,0CCh          ; Set marker
        RET

;-----------------------------------------------------------------------------
; SUB_CPE: Subroutine called by CPE (Call on Parity Even)
; Sets H = 0xDD as marker
;-----------------------------------------------------------------------------
SUB_CPE:
        MVI     H,0DDh          ; Set marker
        RET

;-----------------------------------------------------------------------------
; SUB_BAD_*: Subroutines that should NOT be called
; If called, they set L = 0xEE to indicate error
;-----------------------------------------------------------------------------
SUB_BAD_CP:
        MVI     L,0EEh          ; Error marker
        RET

SUB_BAD_CM:
        MVI     L,0EEh          ; Error marker
        RET

SUB_BAD_CPE:
        MVI     L,0EEh          ; Error marker
        RET

SUB_BAD_CPO:
        MVI     L,0EEh          ; Error marker
        RET

        end
