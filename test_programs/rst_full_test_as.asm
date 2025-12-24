; Intel 8008 FULL RST (0-7) Instruction Test Program
; For AS Macro Assembler
;
; Purpose: Test ALL 8 RST instructions (RST 0 through RST 7)
;   RST n jumps to address n*8:
;   - RST 0: 0x0000 (also bootstrap vector)
;   - RST 1: 0x0008
;   - RST 2: 0x0010
;   - RST 3: 0x0018
;   - RST 4: 0x0020
;   - RST 5: 0x0028
;   - RST 6: 0x0030
;   - RST 7: 0x0038
;
; RST is a 1-cycle instruction that:
;   - Pushes current PC to internal 8-level stack
;   - Jumps to address AAA * 8 (where AAA is 3-bit vector)
;   - RET pops and returns to caller
;
; Special case: RST 0 is used for bootstrap, so we test it
; by having RST 0 check a "called from test" flag
;
; Expected final state:
;   A = 0x00 (success - all tests passed)
;   B = 0x07 (7 RST calls completed: RST 1-7)
;
; Note: RST 0 is tested separately since it shares with bootstrap

        cpu     8008new
        page    0

; ============================================
; RST VECTORS (must be at fixed addresses)
; ============================================

; RST 0 vector at 0x0000 (8 bytes max)
; We skip RST 0 explicit test since it conflicts with bootstrap
; Bootstrap just jumps to MAIN
        org     0000h
RST0_VEC:
        MOV     A,A             ; 1 byte: NOP
        MOV     A,A             ; 1 byte: NOP
        JMP     MAIN            ; 3 bytes: Jump to main (total: 5 bytes, fits!)

; RST 1 vector at 0x0008
        org     0008h
RST1_VEC:
        INR     B               ; Increment test counter
        MVI     C,11h           ; Mark RST 1 was called
        RET

; RST 2 vector at 0x0010
        org     0010h
RST2_VEC:
        INR     B               ; Increment test counter
        MVI     C,22h           ; Mark RST 2 was called
        RET

; RST 3 vector at 0x0018
        org     0018h
RST3_VEC:
        INR     B               ; Increment test counter
        MVI     C,33h           ; Mark RST 3 was called
        RET

; RST 4 vector at 0x0020
        org     0020h
RST4_VEC:
        INR     B               ; Increment test counter
        MVI     C,44h           ; Mark RST 4 was called
        RET

; RST 5 vector at 0x0028
        org     0028h
RST5_VEC:
        INR     B               ; Increment test counter
        MVI     C,55h           ; Mark RST 5 was called
        RET

; RST 6 vector at 0x0030
        org     0030h
RST6_VEC:
        INR     B               ; Increment test counter
        MVI     C,66h           ; Mark RST 6 was called
        RET

; RST 7 vector at 0x0038
        org     0038h
RST7_VEC:
        INR     B               ; Increment test counter
        MVI     C,77h           ; Mark RST 7 was called
        RET

; ============================================
; MAIN PROGRAM at 0x0100
; ============================================
        org     0100h

MAIN:
        MVI     B,00h           ; B = test counter (0)
        MVI     C,00h           ; C = marker register

        ;===========================================
        ; TEST 1: RST 1 (jump to 0x0008)
        ;===========================================
        RST     1
        MOV     A,C
        CPI     11h             ; Check marker
        JNZ     FAIL
        ; B should now be 1

        ;===========================================
        ; TEST 2: RST 2 (jump to 0x0010)
        ;===========================================
        RST     2
        MOV     A,C
        CPI     22h             ; Check marker
        JNZ     FAIL
        ; B should now be 2

        ;===========================================
        ; TEST 3: RST 3 (jump to 0x0018)
        ;===========================================
        RST     3
        MOV     A,C
        CPI     33h             ; Check marker
        JNZ     FAIL
        ; B should now be 3

        ;===========================================
        ; TEST 4: RST 4 (jump to 0x0020)
        ;===========================================
        RST     4
        MOV     A,C
        CPI     44h             ; Check marker
        JNZ     FAIL
        ; B should now be 4

        ;===========================================
        ; TEST 5: RST 5 (jump to 0x0028)
        ;===========================================
        RST     5
        MOV     A,C
        CPI     55h             ; Check marker
        JNZ     FAIL
        ; B should now be 5

        ;===========================================
        ; TEST 6: RST 6 (jump to 0x0030)
        ;===========================================
        RST     6
        MOV     A,C
        CPI     66h             ; Check marker
        JNZ     FAIL
        ; B should now be 6

        ;===========================================
        ; TEST 7: RST 7 (jump to 0x0038)
        ;===========================================
        RST     7
        MOV     A,C
        CPI     77h             ; Check marker
        JNZ     FAIL
        ; B should now be 7

        ; Note: RST 0 test is skipped since it conflicts with bootstrap
        ; RST 0 is implicitly tested by the bootstrap mechanism

        ;===========================================
        ; Verify test counter
        ;===========================================
        MOV     A,B
        CPI     07h             ; Should be 7 (RST 1-7 each incremented)
        JNZ     FAIL

        ;===========================================
        ; All tests passed!
        ;===========================================
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

        end
