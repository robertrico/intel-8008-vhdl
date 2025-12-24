; Intel 8008 Memory ALU Operations Test Program
; For AS Macro Assembler
;
; Purpose: Test all memory-based ALU operations
;   - ADC M (Add memory with carry)
;   - SBB M (Subtract memory with borrow)
;   - ANA M (AND memory)
;   - XRA M (XOR memory)
;   - ORA M (OR memory)
;   - CMP M (Compare memory)
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After ADC M with carry   - L=0x16 (0x05+0x10+1)
;   CP2:  After ADC M no carry     - L=0x15 (0x05+0x10+0)
;   CP3:  After SBB M with borrow  - L=0x0C (0x10-0x03-1)
;   CP4:  After SBB M no borrow    - L=0x0D (0x10-0x03-0)
;   CP5:  After ANA M              - L=0x0B (0xAB AND 0x0F)
;   CP6:  After XRA M              - L=0x55 (0xAA XOR 0xFF)
;   CP7:  After ORA M              - L=0xAF (0xA0 OR 0x0F)
;   CP8:  After CMP M (equal)      - ZF=1
;   CP9:  After CMP M (greater)    - ZF=0, CF=0
;   CP10: After CMP M (less)       - ZF=0, CF=1
;   CP11: Final                    - success
;
; Test data is stored at address 0x00F0-0x00FF
; Expected final state:
;   A = 0x00 (success)
;   B = 0x01 (completion marker)
;   H = 0x00
;   L = 0xF0

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
        ;===========================================
        ; Setup: Point H:L to test data area (0x00F0)
        ;===========================================
        MVI     H,00h
        MVI     L,0F0h          ; H:L = 0x00F0

        ;===========================================
        ; TEST 1: ADC M - Add Memory with Carry
        ; Memory[0x00F0] = 0x10
        ; A = 0x05, Carry = 1
        ; Expected: A = 0x05 + 0x10 + 1 = 0x16
        ;===========================================
        MVI     A,05h           ; A = 0x05
        MVI     B,0FFh          ; Set up to generate carry
        ADD     B               ; 0x05 + 0xFF = 0x104, sets carry
        MVI     A,05h           ; A = 0x05 again (carry still set)
        ADC     M               ; A = 0x05 + mem[0xF0](0x10) + carry(1) = 0x16
        ; CHECKPOINT 1: Verify ADC M with carry
        MOV     E,A             ; Save A to E
        MVI     A,01h
        OUT     CHKPT           ; CP1: E=0x16
        MOV     A,E             ; Restore A

        CPI     16h             ; Check result
        JNZ     FAIL            ; Fail if A != 0x16

        ;===========================================
        ; TEST 2: ADC M - Add Memory without Carry
        ; Memory[0x00F0] = 0x10
        ; A = 0x05, Carry = 0
        ; Expected: A = 0x05 + 0x10 + 0 = 0x15
        ;===========================================
        MVI     A,05h           ; A = 0x05
        ADI     00h             ; Clear carry (add 0)
        ADC     M               ; A = 0x05 + 0x10 + 0 = 0x15
        ; CHECKPOINT 2: Verify ADC M no carry
        MOV     E,A             ; Save A to E
        MVI     A,02h
        OUT     CHKPT           ; CP2: E=0x15
        MOV     A,E             ; Restore A

        CPI     15h             ; Check result
        JNZ     FAIL            ; Fail if A != 0x15

        ;===========================================
        ; TEST 3: SBB M - Subtract Memory with Borrow
        ; Memory[0x00F1] = 0x03
        ; A = 0x10, Carry(borrow) = 1
        ; Expected: A = 0x10 - 0x03 - 1 = 0x0C
        ;===========================================
        MVI     L,0F1h          ; Point to 0x00F1 (contains 0x03)
        MVI     A,0FFh          ; Set up to generate carry
        MVI     B,01h
        ADD     B               ; 0xFF + 0x01 = 0x100, sets carry (borrow)
        MVI     A,10h           ; A = 0x10
        SBB     M               ; A = 0x10 - 0x03 - 1 = 0x0C
        ; CHECKPOINT 3: Verify SBB M with borrow
        MOV     E,A             ; Save A to E
        MVI     A,03h
        OUT     CHKPT           ; CP3: E=0x0C
        MOV     A,E             ; Restore A

        CPI     0Ch             ; Check result
        JNZ     FAIL            ; Fail if A != 0x0C

        ;===========================================
        ; TEST 4: SBB M - Subtract Memory without Borrow
        ; Memory[0x00F1] = 0x03
        ; A = 0x10, Carry(borrow) = 0
        ; Expected: A = 0x10 - 0x03 - 0 = 0x0D
        ;===========================================
        MVI     A,10h           ; A = 0x10
        ADI     00h             ; Clear carry
        SBB     M               ; A = 0x10 - 0x03 - 0 = 0x0D
        ; CHECKPOINT 4: Verify SBB M no borrow
        MOV     E,A             ; Save A to E
        MVI     A,04h
        OUT     CHKPT           ; CP4: E=0x0D
        MOV     A,E             ; Restore A

        CPI     0Dh             ; Check result
        JNZ     FAIL            ; Fail if A != 0x0D

        ;===========================================
        ; TEST 5: ANA M - AND Memory
        ; Memory[0x00F2] = 0x0F
        ; A = 0xAB (10101011)
        ; Expected: A = 0xAB AND 0x0F = 0x0B
        ;===========================================
        MVI     L,0F2h          ; Point to 0x00F2 (contains 0x0F)
        MVI     A,0ABh          ; A = 0xAB
        ANA     M               ; A = 0xAB AND 0x0F = 0x0B
        ; CHECKPOINT 5: Verify ANA M
        MOV     E,A             ; Save A to E
        MVI     A,05h
        OUT     CHKPT           ; CP5: E=0x0B
        MOV     A,E             ; Restore A

        CPI     0Bh             ; Check result
        JNZ     FAIL            ; Fail if A != 0x0B

        ;===========================================
        ; TEST 6: XRA M - XOR Memory
        ; Memory[0x00F3] = 0xFF
        ; A = 0xAA (10101010)
        ; Expected: A = 0xAA XOR 0xFF = 0x55
        ;===========================================
        MVI     L,0F3h          ; Point to 0x00F3 (contains 0xFF)
        MVI     A,0AAh          ; A = 0xAA
        XRA     M               ; A = 0xAA XOR 0xFF = 0x55
        ; CHECKPOINT 6: Verify XRA M
        MOV     E,A             ; Save A to E
        MVI     A,06h
        OUT     CHKPT           ; CP6: E=0x55
        MOV     A,E             ; Restore A

        CPI     55h             ; Check result
        JNZ     FAIL            ; Fail if A != 0x55

        ;===========================================
        ; TEST 7: ORA M - OR Memory
        ; Memory[0x00F4] = 0x0F
        ; A = 0xA0 (10100000)
        ; Expected: A = 0xA0 OR 0x0F = 0xAF
        ;===========================================
        MVI     L,0F4h          ; Point to 0x00F4 (contains 0x0F)
        MVI     A,0A0h          ; A = 0xA0
        ORA     M               ; A = 0xA0 OR 0x0F = 0xAF
        ; CHECKPOINT 7: Verify ORA M
        MOV     E,A             ; Save A to E
        MVI     A,07h
        OUT     CHKPT           ; CP7: E=0xAF
        MOV     A,E             ; Restore A

        CPI     0AFh            ; Check result
        JNZ     FAIL            ; Fail if A != 0xAF

        ;===========================================
        ; TEST 8: CMP M - Compare Memory (Equal)
        ; Memory[0x00F5] = 0x42
        ; A = 0x42
        ; Expected: Zero flag set (equal)
        ;===========================================
        MVI     L,0F5h          ; Point to 0x00F5 (contains 0x42)
        MVI     A,42h           ; A = 0x42
        CMP     M               ; Compare A with memory
        ; CHECKPOINT 8: Verify CMP M equal (ZF=1)
        MVI     A,08h
        OUT     CHKPT           ; CP8: ZF=1, CF=0
        MVI     A,42h           ; Restore A for next test
        CMP     M               ; Re-do compare for JNZ
        JNZ     FAIL            ; Fail if not equal (zero flag not set)

        ;===========================================
        ; TEST 9: CMP M - Compare Memory (Greater)
        ; Memory[0x00F5] = 0x42
        ; A = 0x50
        ; Expected: Zero flag clear, Carry clear (A > M)
        ;===========================================
        MVI     A,50h           ; A = 0x50
        CMP     M               ; Compare A with memory (0x42)
        ; CHECKPOINT 9: Verify CMP M greater (ZF=0, CF=0)
        MVI     A,09h
        OUT     CHKPT           ; CP9: ZF=0, CF=0
        MVI     A,50h           ; Restore A
        CMP     M               ; Re-do compare for checks
        JZ      FAIL            ; Fail if zero flag set (should not be equal)
        JC      FAIL            ; Fail if carry set (A should be greater)

        ;===========================================
        ; TEST 10: CMP M - Compare Memory (Less)
        ; Memory[0x00F5] = 0x42
        ; A = 0x30
        ; Expected: Zero flag clear, Carry set (A < M)
        ;===========================================
        MVI     A,30h           ; A = 0x30
        CMP     M               ; Compare A with memory (0x42)
        ; CHECKPOINT 10: Verify CMP M less (ZF=0, CF=1)
        MVI     A,0Ah
        OUT     CHKPT           ; CP10: ZF=0, CF=1
        MVI     A,30h           ; Restore A
        CMP     M               ; Re-do compare for checks
        JZ      FAIL            ; Fail if zero flag set
        JNC     FAIL            ; Fail if carry NOT set (A should be less)

        ;===========================================
        ; All tests passed! Set success markers
        ;===========================================
        MVI     L,0F0h          ; Reset L to 0xF0
        ; CHECKPOINT 11: Final success
        MVI     A,0Bh
        OUT     CHKPT           ; CP11: success
        MVI     A,00h           ; A = 0x00 (success)
        MVI     B,01h           ; B = 0x01 (completion marker)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure marker)
        MVI     B,0FFh          ; B = 0xFF

DONE:
        HLT

;===========================================
; Test data area at 0x00F0
;===========================================
        org     00F0h
DATA_START:
        db      10h             ; 0x00F0: ADC test value (0x10)
        db      03h             ; 0x00F1: SBB test value (0x03)
        db      0Fh             ; 0x00F2: ANA test value (0x0F)
        db      0FFh            ; 0x00F3: XRA test value (0xFF)
        db      0Fh             ; 0x00F4: ORA test value (0x0F)
        db      42h             ; 0x00F5: CMP test value (0x42)

        end
