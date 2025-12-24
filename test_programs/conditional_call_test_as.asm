; Intel 8008 Conditional Call and Carry Immediate Test Program
; For AS Macro Assembler
;
; Purpose: Test conditional calls and carry-based immediate operations
;   - ACI (Add immediate with carry)
;   - SBI (Subtract immediate with borrow)
;   - CNC (Call on no carry)
;   - CC (Call on carry)
;   - CNZ (Call on not zero)
;   - CZ (Call on zero)
;   - RZ (Return on zero)
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After ACI with carry    - L=0x16 (0x10+0x05+1)
;   CP2:  After ACI no carry      - L=0x15 (0x10+0x05+0)
;   CP3:  After SBI with borrow   - L=0x1A (0x20-0x05-1)
;   CP4:  After SBI no borrow     - L=0x1B (0x20-0x05-0)
;   CP5:  After CC                - C=0xAA (called on carry)
;   CP6:  After CNC               - D=0xBB (called on no carry)
;   CP7:  After CNZ/CZ/RZ         - success
;   CP8:  Final                   - A=0x00
;
; Expected final state:
;   A = 0x00 (success)
;   B = 0x07 (test counter - 7 tests completed)
;   C = 0xAA (marker from CC subroutine)
;   D = 0xBB (marker from CNC subroutine)

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
        MVI     C,00h           ; C = CC marker (will be 0xAA)
        MVI     D,00h           ; D = CNC marker (will be 0xBB)

        ;===========================================
        ; TEST 1: ACI - Add Immediate with Carry (carry=1)
        ; A = 0x10, Carry = 1
        ; ACI 0x05 => A = 0x10 + 0x05 + 1 = 0x16
        ;===========================================
        MVI     A,0FFh          ; Set up to generate carry
        ADI     01h             ; 0xFF + 0x01 = 0x100, sets carry
        MVI     A,10h           ; A = 0x10 (carry preserved)
        ACI     05h             ; A = 0x10 + 0x05 + 1 = 0x16
        ; CHECKPOINT 1: Verify ACI with carry
        MOV     L,A             ; Save A to L
        MVI     A,01h
        OUT     CHKPT           ; CP1: L=0x16
        MOV     A,L             ; Restore A

        CPI     16h             ; Check result
        JNZ     FAIL            ; Fail if A != 0x16
        INR     B               ; Test 1 passed, B = 1

        ;===========================================
        ; TEST 2: ACI - Add Immediate with Carry (carry=0)
        ; A = 0x10, Carry = 0
        ; ACI 0x05 => A = 0x10 + 0x05 + 0 = 0x15
        ;===========================================
        MVI     A,10h           ; A = 0x10
        ADI     00h             ; Clear carry
        ACI     05h             ; A = 0x10 + 0x05 + 0 = 0x15
        ; CHECKPOINT 2: Verify ACI no carry
        MOV     L,A             ; Save A to L
        MVI     A,02h
        OUT     CHKPT           ; CP2: L=0x15
        MOV     A,L             ; Restore A

        CPI     15h             ; Check result
        JNZ     FAIL            ; Fail if A != 0x15
        INR     B               ; Test 2 passed, B = 2

        ;===========================================
        ; TEST 3: SBI - Subtract Immediate with Borrow (borrow=1)
        ; A = 0x20, Carry(borrow) = 1
        ; SBI 0x05 => A = 0x20 - 0x05 - 1 = 0x1A
        ;===========================================
        MVI     A,0FFh          ; Set up to generate carry
        ADI     01h             ; 0xFF + 0x01 = 0x100, sets carry
        MVI     A,20h           ; A = 0x20 (carry preserved)
        SBI     05h             ; A = 0x20 - 0x05 - 1 = 0x1A
        ; CHECKPOINT 3: Verify SBI with borrow
        MOV     L,A             ; Save A to L
        MVI     A,03h
        OUT     CHKPT           ; CP3: L=0x1A
        MOV     A,L             ; Restore A

        CPI     1Ah             ; Check result
        JNZ     FAIL            ; Fail if A != 0x1A
        INR     B               ; Test 3 passed, B = 3

        ;===========================================
        ; TEST 4: SBI - Subtract Immediate with Borrow (borrow=0)
        ; A = 0x20, Carry(borrow) = 0
        ; SBI 0x05 => A = 0x20 - 0x05 - 0 = 0x1B
        ;===========================================
        MVI     A,20h           ; A = 0x20
        ADI     00h             ; Clear carry
        SBI     05h             ; A = 0x20 - 0x05 - 0 = 0x1B
        ; CHECKPOINT 4: Verify SBI no borrow
        MOV     L,A             ; Save A to L
        MVI     A,04h
        OUT     CHKPT           ; CP4: L=0x1B
        MOV     A,L             ; Restore A

        CPI     1Bh             ; Check result
        JNZ     FAIL            ; Fail if A != 0x1B
        INR     B               ; Test 4 passed, B = 4

        ;===========================================
        ; TEST 5: CC - Call on Carry (carry=1)
        ; Set carry, call SUB_CC which sets C = 0xAA
        ;===========================================
        MVI     A,0FFh          ; Set up to generate carry
        ADI     01h             ; Sets carry
        CC      SUB_CC          ; Call if carry set (should call)
        ; CHECKPOINT 5: Verify CC called
        MVI     A,05h
        OUT     CHKPT           ; CP5: C=0xAA

        ; Check that C was set by subroutine
        MOV     A,C
        CPI     0AAh            ; Check C = 0xAA
        JNZ     FAIL            ; Fail if C != 0xAA
        INR     B               ; Test 5 passed, B = 5

        ;===========================================
        ; TEST 6: CNC - Call on No Carry (carry=0)
        ; Clear carry, call SUB_CNC which sets D = 0xBB
        ;===========================================
        MVI     A,00h
        ADI     00h             ; Clear carry
        CNC     SUB_CNC         ; Call if carry NOT set (should call)
        ; CHECKPOINT 6: Verify CNC called
        MVI     A,06h
        OUT     CHKPT           ; CP6: D=0xBB

        ; Check that D was set by subroutine
        MOV     A,D
        CPI     0BBh            ; Check D = 0xBB
        JNZ     FAIL            ; Fail if D != 0xBB
        INR     B               ; Test 6 passed, B = 6

        ;===========================================
        ; TEST 7: CNZ/CZ and RZ
        ; Test CNZ calls when not zero, CZ calls when zero
        ; RZ returns when zero flag is set
        ;===========================================
        ; First test CNZ - should call when A != 0
        MVI     A,01h           ; A = 1 (not zero)
        CPI     00h             ; Compare with 0 - sets flags, Z=0
        CNZ     SUB_CNZ         ; Call if not zero (should call)
        ; SUB_CNZ sets A = 0xCC

        CPI     0CCh            ; Check A = 0xCC
        JNZ     FAIL            ; Fail if A != 0xCC

        ; Now test CZ - should call when A == 0
        MVI     A,00h           ; A = 0 (zero)
        CPI     00h             ; Compare with 0 - Z=1
        CZ      SUB_CZ          ; Call if zero (should call)
        ; SUB_CZ sets A = 0xDD then uses RZ to return

        CPI     0DDh            ; Check A = 0xDD
        JNZ     FAIL            ; Fail if A != 0xDD
        INR     B               ; Test 7 passed, B = 7
        ; CHECKPOINT 7: Verify CNZ/CZ/RZ worked
        MVI     A,07h
        OUT     CHKPT           ; CP7: B=0x07

        ;===========================================
        ; All tests passed! Set success marker
        ;===========================================
        ; CHECKPOINT 8: Final success
        MVI     A,08h
        OUT     CHKPT           ; CP8: success
        MVI     A,00h           ; A = 0x00 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)

DONE:
        HLT

;-----------------------------------------------------------------------------
; SUB_CC: Subroutine called by CC (Call on Carry)
; Sets C = 0xAA as marker
;-----------------------------------------------------------------------------
SUB_CC:
        MVI     C,0AAh          ; Set marker
        RET

;-----------------------------------------------------------------------------
; SUB_CNC: Subroutine called by CNC (Call on No Carry)
; Sets D = 0xBB as marker
;-----------------------------------------------------------------------------
SUB_CNC:
        MVI     D,0BBh          ; Set marker
        RET

;-----------------------------------------------------------------------------
; SUB_CNZ: Subroutine called by CNZ (Call on Not Zero)
; Sets A = 0xCC as marker
;-----------------------------------------------------------------------------
SUB_CNZ:
        MVI     A,0CCh          ; Set marker
        RET

;-----------------------------------------------------------------------------
; SUB_CZ: Subroutine called by CZ (Call on Zero)
; Sets A = 0xDD and uses RZ to return (since zero flag should still be set)
;-----------------------------------------------------------------------------
SUB_CZ:
        MVI     A,0DDh          ; Set marker
        ; Use RZ to test it - zero flag should still be set from CPI 00h
        ; Actually no, MVI changes flags. Let's set zero flag explicitly
        MVI     E,00h           ; Load 0 into E
        CPI     0DDh            ; A = 0xDD, compare with 0xDD, sets Z=1
        RZ                      ; Return if zero (should return)
        MVI     A,0EEh          ; Should not reach here
        RET

        end
