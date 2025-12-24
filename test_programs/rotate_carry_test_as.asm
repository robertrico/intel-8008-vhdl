; Intel 8008 Rotate and Carry Conditional Test Program
; For AS Macro Assembler
;
; Purpose: Test rotate operations and carry-based conditionals
;   - RLC (rotate left through carry)
;   - RRC (rotate right through carry)
;   - RAL (rotate left through accumulator)
;   - RAR (rotate right through accumulator)
;   - JC/JNC (jump on carry/no carry)
;   - RC/RNC (return on carry/no carry)
;   - ADD M (add memory to accumulator)
;   - SUB M (subtract memory from accumulator)
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After RLC   - B=0x03, CF=1 (0x81 rotated left)
;   CP2:  After JC    - passed (carry was set)
;   CP3:  After RRC   - C=0xC0, CF=1 (0x81 rotated right)
;   CP4:  After JNC   - passed (did not jump when carry=1)
;   CP5:  After RAL   - D=0x03, CF=1 (old carry=1 to bit0)
;   CP6:  After RAR   - E=0xC0, CF=1 (old carry=1 to bit7)
;   CP7:  After JNC   - passed (carry was 0)
;   CP8:  After JC    - passed (carry was 1 from 0xFF+1)
;   CP9:  After RC    - A=0xAA (returned on carry)
;   CP10: After RNC   - A=0xBB (returned on no carry)
;   CP11: After ADD M - A=0x08 (3+5=8)
;   CP12: After SUB M - A=0x05 (10-5=5)
;   CP13: Final       - A=0x00 (success)
;
; Final Register State:
;   A: 0x00 (success indicator)
;   B: 0x03 (RLC result: 0x81 rotated left = 0x03, carry=1)
;   C: 0xC0 (RRC result: 0x81 rotated right = 0xC0, carry=1)
;   D: 0x03 (RAL result: 0x81 rotated left with carry=1 = 0x03)
;   E: 0xC0 (RAR result: 0x81 rotated right with carry=1 = 0xC0)
;   H: 0x10 (RAM pointer high)
;   L: 0x05 (test counter)

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

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
        ; TEST 1: RLC (Rotate Left Circular)
        ; 0x81 = 10000001 -> 00000011 = 0x03, Carry=1
        ; bit 7 goes to carry AND bit 0
        ;===========================================
        MVI     A,81h               ; A = 10000001
        RLC                         ; Rotate left, bit7->carry and bit0
        MOV     B,A                 ; Save result: B = 0x03
        ; CHECKPOINT 1: Verify RLC result
        MVI     A,01h
        OUT     CHKPT               ; CP1: B=0x03, CF=1

        ;===========================================
        ; TEST 2: JC - Jump if Carry (should jump)
        ; After RLC of 0x81, carry should be set
        ;===========================================
        JC      TEST2_PASS          ; Should jump (carry=1 from RLC)
        JMP     FAIL                ; Should not reach here

TEST2_PASS:
        ; CHECKPOINT 2: JC passed
        MVI     A,02h
        OUT     CHKPT               ; CP2: reached here, JC worked

        ;===========================================
        ; TEST 3: RRC (Rotate Right Circular)
        ; 0x81 = 10000001 -> 11000000 = 0xC0, Carry=1
        ; bit 0 goes to carry AND bit 7
        ;===========================================
        MVI     A,81h               ; A = 10000001
        RRC                         ; Rotate right, bit0->carry and bit7
        MOV     C,A                 ; Save result: C = 0xC0
        ; CHECKPOINT 3: Verify RRC result
        MVI     A,03h
        OUT     CHKPT               ; CP3: C=0xC0, CF=1

        ;===========================================
        ; TEST 4: JNC - Jump if No Carry (should NOT jump)
        ; After RRC of 0x81, carry should be set
        ;===========================================
        JNC     FAIL                ; Should NOT jump (carry=1)
        ; CHECKPOINT 4: JNC correctly did not jump
        MVI     A,04h
        OUT     CHKPT               ; CP4: JNC correctly skipped

        ;===========================================
        ; TEST 5: RAL (Rotate Left through Accumulator)
        ; Carry is currently 1 (from RRC)
        ; 0x81 = 10000001, carry=1 -> 00000011, carry=1
        ; Old carry goes to bit 0, bit 7 goes to new carry
        ;===========================================
        MVI     A,81h               ; A = 10000001
        RAL                         ; Rotate left through carry
        MOV     D,A                 ; Save result: D = 0x03 (old carry=1 went to bit0)
        ; CHECKPOINT 5: Verify RAL result
        MVI     A,05h
        OUT     CHKPT               ; CP5: D=0x03, CF=1

        ;===========================================
        ; TEST 6: RAR (Rotate Right through Accumulator)
        ; Carry is currently 1 (from RAL, bit 7 was 1)
        ; 0x81 = 10000001, carry=1 -> 11000000, carry=1
        ; Old carry goes to bit 7, bit 0 goes to new carry
        ;===========================================
        MVI     A,81h               ; A = 10000001
        RAR                         ; Rotate right through carry
        MOV     E,A                 ; Save result: E = 0xC0 (old carry=1 went to bit7)
        ; CHECKPOINT 6: Verify RAR result
        MVI     A,06h
        OUT     CHKPT               ; CP6: E=0xC0, CF=1

        ;===========================================
        ; TEST 7: Clear carry and test JNC
        ; Add 0 to clear carry, then test JNC
        ;===========================================
        MVI     A,00h               ; A = 0
        ADI     00h                 ; Add 0, clears carry
        JNC     TEST7_PASS          ; Should jump (carry=0)
        JMP     FAIL                ; Should not reach here

TEST7_PASS:
        ; CHECKPOINT 7: JNC passed (carry was 0)
        MVI     A,07h
        OUT     CHKPT               ; CP7: JNC worked

        ;===========================================
        ; TEST 8: Set carry and test JC
        ; 0xFF + 1 = 0x00 with carry
        ;===========================================
        MVI     A,0FFh              ; A = 255
        ADI     01h                 ; A = 0, carry = 1
        JC      TEST8_PASS          ; Should jump (carry=1)
        JMP     FAIL                ; Should not reach here

TEST8_PASS:
        ; CHECKPOINT 8: JC passed (carry was 1)
        MVI     A,08h
        OUT     CHKPT               ; CP8: JC worked

        ;===========================================
        ; TEST 9: CALL/RC - Return on Carry
        ; Set carry, call subroutine that returns on carry
        ;===========================================
        MVI     A,0FFh              ; A = 255
        ADI     01h                 ; Set carry
        CALL    SUB_RC              ; Call subroutine
        ; If RC worked, we return here with A=0xAA
        ; CHECKPOINT 9: Verify RC returned correctly
        MOV     L,A                 ; Save A to L for checkpoint
        MVI     A,09h
        OUT     CHKPT               ; CP9: L=0xAA
        MOV     A,L                 ; Restore A

        CPI     0AAh                ; Check A = 0xAA (marker from subroutine)
        JNZ     FAIL                ; Fail if A != 0xAA

        ;===========================================
        ; TEST 10: CALL/RNC - Return on No Carry
        ; Clear carry, call subroutine that returns on no carry
        ;===========================================
        MVI     A,00h               ; A = 0
        ADI     00h                 ; Clear carry
        CALL    SUB_RNC             ; Call subroutine
        ; If RNC worked, we return here with A=0xBB
        ; CHECKPOINT 10: Verify RNC returned correctly
        MOV     L,A                 ; Save A to L for checkpoint
        MVI     A,0Ah
        OUT     CHKPT               ; CP10: L=0xBB
        MOV     A,L                 ; Restore A

        CPI     0BBh                ; Check A = 0xBB (marker from subroutine)
        JNZ     FAIL                ; Fail if A != 0xBB

        ;===========================================
        ; TEST 11: ADD M (Add Memory)
        ; Set up H:L to point to test data, add from memory
        ;===========================================
        MVI     H,10h               ; H = 0x10 (RAM base)
        MVI     L,00h               ; L = 0x00
        MVI     A,05h               ; A = 5
        MOV     M,A                 ; Store 5 at RAM[0x1000]

        MVI     A,03h               ; A = 3
        ADD     M                   ; A = A + RAM[H:L] = 3 + 5 = 8
        ; CHECKPOINT 11: Verify ADD M result
        MOV     L,A                 ; Save A to L
        MVI     A,0Bh
        OUT     CHKPT               ; CP11: L=0x08
        MOV     A,L                 ; Restore A

        CPI     08h                 ; Check result
        JNZ     FAIL

        ;===========================================
        ; TEST 12: SUB M (Subtract Memory)
        ; Need to set up H:L and memory again
        ;===========================================
        MVI     H,10h               ; H = 0x10 (RAM base)
        MVI     L,00h               ; L = 0x00
        MVI     A,05h               ; A = 5
        MOV     M,A                 ; Store 5 at RAM[0x1000]

        MVI     A,0Ah               ; A = 10
        SUB     M                   ; A = A - RAM[H:L] = 10 - 5 = 5
        ; CHECKPOINT 12: Verify SUB M result
        MOV     L,A                 ; Save A to L
        MVI     A,0Ch
        OUT     CHKPT               ; CP12: L=0x05
        MOV     A,L                 ; Restore A

        CPI     05h                 ; Check result
        JNZ     FAIL

        ;===========================================
        ; FINAL: Set A to 0 for success indicator
        ;===========================================
        MVI     L,05h               ; L = 5 (test marker)
        ; CHECKPOINT 13: Final success
        MVI     A,0Dh
        OUT     CHKPT               ; CP13: success
        MVI     A,00h               ; A = 0 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh              ; A = 0xFF (failure indicator)

DONE:
        HLT

;-----------------------------------------------------------------------------
; SUB_RC: Subroutine that returns if carry is set
; Returns with A = 0xAA as marker
;-----------------------------------------------------------------------------
SUB_RC:
        MVI     A,0AAh              ; Set marker first
        RC                          ; Return if carry set
        MVI     A,0FFh              ; Should not reach here
        RET

;-----------------------------------------------------------------------------
; SUB_RNC: Subroutine that returns if carry is NOT set
; Returns with A = 0xBB as marker
;-----------------------------------------------------------------------------
SUB_RNC:
        MVI     A,0BBh              ; Set marker
        RNC                         ; Return if carry not set
        MVI     A,0FFh              ; Should not reach here
        RET

        end
