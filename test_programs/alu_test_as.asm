; Intel 8008 ALU Instruction Test Program
; For AS Macro Assembler
;
; Purpose: Test all ALU operations systematically
;   - ADD, ADC (add, add with carry)
;   - SUB, SBB (subtract, subtract with borrow)
;   - ANA, XRA, ORA (logical AND, XOR, OR)
;   - CMP (compare - sets flags only)
;   - ADI, ACI, SUI, SBI, ANI, XRI, ORI, CPI (immediate variants)
;   - DCR (decrement)
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After ADD   - B=0x08 (5+3=8)
;   CP2:  After SUB   - C=0x02 (5-3=2)
;   CP3:  After ANA   - D=0x01 (0x05 AND 0x03)
;   CP4:  After XRA   - E=0x06 (0x05 XOR 0x03)
;   CP5:  After ORA   - H=0x07 (0x05 OR 0x03)
;   CP6:  After ADI   - L=0x0F (10+5=15)
;   CP7:  After SUI   - L=0x0A (15-5=10)
;   CP8:  After ANI   - L=0x0A (0x0A AND 0x0F)
;   CP9:  After ORI   - L=0xFA (0x0A OR 0xF0)
;   CP10: After XRI   - L=0x05 (0xFA XOR 0xFF)
;   CP11: After DCR   - L=0x00 (decremented from 5)
;   CP12: After CMP   - Z=1 (A==B, didn't jump to FAIL)
;   CP13: After ADC   - L=0x0E (5+8+carry=14)
;   CP14: After SBB   - L=0x0D (16-2-borrow=13)
;   CP15: Final       - A=0x00 (success)
;
; Final Register State:
;   A: 0x00 (success indicator)
;   B: 0x08 (ADD result: 5+3)
;   C: 0x02 (SUB result: 5-3)
;   D: 0x01 (ANA result: 0x05 AND 0x03)
;   E: 0x06 (XRA result: 0x05 XOR 0x03)
;   H: 0x07 (ORA result: 0x05 OR 0x03)
;   L: 0x00 (loop counter, decremented to 0)

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

; Reset vector
        org     0000h
STARTUP:
        MOV     A,A             ; NOP (PC sync)
        MOV     A,A             ; NOP
        JMP     MAIN

; Main program
        org     0100h
MAIN:
        ;===========================================
        ; TEST 1: ADD register
        ; A = 5 + 3 = 8
        ;===========================================
        MVI     A,05h           ; A = 5
        MVI     B,03h           ; B = 3
        ADD     B               ; A = A + B = 8
        MOV     B,A             ; Save result: B = 8 (0x08)
        ; CHECKPOINT 1: Verify ADD result
        MVI     A,01h
        OUT     CHKPT           ; CP1: B=0x08

        ;===========================================
        ; TEST 2: SUB register
        ; A = 5 - 3 = 2
        ;===========================================
        MVI     A,05h           ; A = 5
        MVI     C,03h           ; C = 3
        SUB     C               ; A = A - C = 2
        MOV     C,A             ; Save result: C = 2 (0x02)
        ; CHECKPOINT 2: Verify SUB result
        MVI     A,02h
        OUT     CHKPT           ; CP2: C=0x02

        ;===========================================
        ; TEST 3: ANA register (AND)
        ; A = 0x05 AND 0x03 = 0x01
        ; 0101 AND 0011 = 0001
        ;===========================================
        MVI     A,05h           ; A = 0x05
        MVI     D,03h           ; D = 0x03
        ANA     D               ; A = A AND D = 0x01
        MOV     D,A             ; Save result: D = 1 (0x01)
        ; CHECKPOINT 3: Verify ANA result
        MVI     A,03h
        OUT     CHKPT           ; CP3: D=0x01

        ;===========================================
        ; TEST 4: XRA register (XOR)
        ; A = 0x05 XOR 0x03 = 0x06
        ; 0101 XOR 0011 = 0110
        ;===========================================
        MVI     A,05h           ; A = 0x05
        MVI     E,03h           ; E = 0x03
        XRA     E               ; A = A XOR E = 0x06
        MOV     E,A             ; Save result: E = 6 (0x06)
        ; CHECKPOINT 4: Verify XRA result
        MVI     A,04h
        OUT     CHKPT           ; CP4: E=0x06

        ;===========================================
        ; TEST 5: ORA register (OR)
        ; A = 0x05 OR 0x03 = 0x07
        ; 0101 OR 0011 = 0111
        ;===========================================
        MVI     A,05h           ; A = 0x05
        MVI     H,03h           ; H = 0x03
        ORA     H               ; A = A OR H = 0x07
        MOV     H,A             ; Save result: H = 7 (0x07)
        ; CHECKPOINT 5: Verify ORA result
        MVI     A,05h
        OUT     CHKPT           ; CP5: H=0x07

        ;===========================================
        ; TEST 6: ADI immediate
        ; A = 10 + 5 = 15
        ;===========================================
        MVI     A,0Ah           ; A = 10
        ADI     05h             ; A = A + 5 = 15 (0x0F)
        ; CHECKPOINT 6: Verify ADI result (save to L first)
        MOV     L,A             ; Save A temporarily
        MVI     A,06h
        OUT     CHKPT           ; CP6: L=0x0F
        MOV     A,L             ; Restore A

        ;===========================================
        ; TEST 7: SUI immediate
        ; A = 15 - 5 = 10
        ;===========================================
        SUI     05h             ; A = 15 - 5 = 10 (0x0A)
        ; CHECKPOINT 7: Verify SUI result
        MOV     L,A
        MVI     A,07h
        OUT     CHKPT           ; CP7: L=0x0A
        MOV     A,L

        ;===========================================
        ; TEST 8: ANI immediate
        ; A = 0x0A AND 0x0F = 0x0A
        ; 1010 AND 1111 = 1010
        ;===========================================
        ANI     0Fh             ; A = 0x0A AND 0x0F = 0x0A
        ; CHECKPOINT 8: Verify ANI result
        MOV     L,A
        MVI     A,08h
        OUT     CHKPT           ; CP8: L=0x0A
        MOV     A,L

        ;===========================================
        ; TEST 9: ORI immediate
        ; A = 0x0A OR 0xF0 = 0xFA
        ; 00001010 OR 11110000 = 11111010
        ;===========================================
        ORI     0F0h            ; A = 0x0A OR 0xF0 = 0xFA
        ; CHECKPOINT 9: Verify ORI result
        MOV     L,A
        MVI     A,09h
        OUT     CHKPT           ; CP9: L=0xFA
        MOV     A,L

        ;===========================================
        ; TEST 10: XRI immediate
        ; A = 0xFA XOR 0xFF = 0x05
        ; 11111010 XOR 11111111 = 00000101
        ;===========================================
        XRI     0FFh            ; A = 0xFA XOR 0xFF = 0x05
        ; CHECKPOINT 10: Verify XRI result
        MOV     L,A
        MVI     A,0Ah
        OUT     CHKPT           ; CP10: L=0x05

        ;===========================================
        ; TEST 11: DCR register (decrement)
        ; Loop countdown from 5 to 0
        ;===========================================
        MVI     L,05h           ; L = 5 (loop counter)
DCR_LOOP:
        DCR     L               ; L = L - 1
        JNZ     DCR_LOOP        ; Loop until L = 0
        ; L should now be 0x00, Z=1
        ; CHECKPOINT 11: Verify DCR loop complete
        MVI     A,0Bh
        OUT     CHKPT           ; CP11: L=0x00, Z=1

        ;===========================================
        ; TEST 12: CMP register (compare - flags only)
        ; Compare A with B, should set flags
        ;===========================================
        MVI     A,08h           ; A = 8
        CMP     B               ; Compare A with B (both 8)
        JNZ     FAIL            ; Should NOT jump (Z=1 since equal)
        ; CHECKPOINT 12: Verify CMP passed
        MVI     A,0Ch
        OUT     CHKPT           ; CP12: Reached here, Z was 1

        ;===========================================
        ; TEST 13: ADC with carry
        ; Set carry with 0xFF + 1, then ADC
        ;===========================================
        MVI     A,0FFh          ; A = 255
        ADI     01h             ; A = 0 with carry set
        MVI     A,05h           ; A = 5
        ADC     B               ; A = 5 + 8 + carry(1) = 14 (0x0E)
        ; CHECKPOINT 13: Verify ADC result
        MOV     L,A
        MVI     A,0Dh
        OUT     CHKPT           ; CP13: L=0x0E

        ;===========================================
        ; TEST 14: SBB with borrow
        ; Set borrow (carry) with 0x00 - 1, then SBB
        ;===========================================
        MVI     A,00h           ; A = 0
        SUI     01h             ; A = 0xFF with borrow set
        MVI     A,10h           ; A = 16
        SBB     C               ; A = 16 - 2 - borrow(1) = 13 (0x0D)
        ; CHECKPOINT 14: Verify SBB result
        MOV     L,A
        MVI     A,0Eh
        OUT     CHKPT           ; CP14: L=0x0D

        ;===========================================
        ; FINAL: Set A to 0 for success indicator
        ;===========================================
        MVI     A,00h           ; A = 0 (success)
        ; CHECKPOINT 15: Final success
        MVI     A,0Fh
        OUT     CHKPT           ; CP15: Success checkpoint
        MVI     A,00h           ; Restore A=0
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure indicator)

DONE:
        HLT

        end
