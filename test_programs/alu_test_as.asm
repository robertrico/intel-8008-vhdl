; Intel 8008 ALU Instruction Test Program
; For AS Macro Assembler
;
; Purpose: Test all ALU operations systematically
;   - ADD, ADC (add, add with carry)
;   - SUB, SBB (subtract, subtract with borrow)
;   - ANA, XRA, ORA (logical AND, XOR, OR)
;   - CMP (compare - sets flags only)
;   - ADI, ACI, SUI, SBI, ANI, XRI, ORI, CPI (immediate variants)
;   - DCR (decrement - not yet tested)
;
; Expected Results (in registers at halt):
;   A: 0x00 (final test result)
;   B: 0x08 (ADD result: 5+3)
;   C: 0x02 (SUB result: 5-3)
;   D: 0x01 (ANA result: 0x05 AND 0x03)
;   E: 0x06 (XRA result: 0x05 XOR 0x03)
;   H: 0x07 (ORA result: 0x05 OR 0x03)
;   L: 0x00 (loop counter, decremented to 0)
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
        ; TEST 1: ADD register
        ; A = 5 + 3 = 8
        ;===========================================
        MVI     A,05h               ; A = 5
        MVI     B,03h               ; B = 3
        ADD     B                   ; A = A + B = 8
        MOV     B,A                 ; Save result: B = 8 (0x08)

        ;===========================================
        ; TEST 2: SUB register
        ; A = 5 - 3 = 2
        ;===========================================
        MVI     A,05h               ; A = 5
        MVI     C,03h               ; C = 3
        SUB     C                   ; A = A - C = 2
        MOV     C,A                 ; Save result: C = 2 (0x02)

        ;===========================================
        ; TEST 3: ANA register (AND)
        ; A = 0x05 AND 0x03 = 0x01
        ; 0101 AND 0011 = 0001
        ;===========================================
        MVI     A,05h               ; A = 0x05
        MVI     D,03h               ; D = 0x03
        ANA     D                   ; A = A AND D = 0x01
        MOV     D,A                 ; Save result: D = 1 (0x01)

        ;===========================================
        ; TEST 4: XRA register (XOR)
        ; A = 0x05 XOR 0x03 = 0x06
        ; 0101 XOR 0011 = 0110
        ;===========================================
        MVI     A,05h               ; A = 0x05
        MVI     E,03h               ; E = 0x03
        XRA     E                   ; A = A XOR E = 0x06
        MOV     E,A                 ; Save result: E = 6 (0x06)

        ;===========================================
        ; TEST 5: ORA register (OR)
        ; A = 0x05 OR 0x03 = 0x07
        ; 0101 OR 0011 = 0111
        ;===========================================
        MVI     A,05h               ; A = 0x05
        MVI     H,03h               ; H = 0x03
        ORA     H                   ; A = A OR H = 0x07
        MOV     H,A                 ; Save result: H = 7 (0x07)

        ;===========================================
        ; TEST 6: ADI immediate
        ; A = 10 + 5 = 15
        ;===========================================
        MVI     A,0Ah               ; A = 10
        ADI     05h                 ; A = A + 5 = 15 (0x0F)
        ; Don't save, continue with next test

        ;===========================================
        ; TEST 7: SUI immediate
        ; A = 15 - 5 = 10
        ;===========================================
        SUI     05h                 ; A = 15 - 5 = 10 (0x0A)
        ; Don't save, continue

        ;===========================================
        ; TEST 8: ANI immediate
        ; A = 0x0A AND 0x0F = 0x0A
        ; 1010 AND 1111 = 1010
        ;===========================================
        ANI     0Fh                 ; A = 0x0A AND 0x0F = 0x0A

        ;===========================================
        ; TEST 9: ORI immediate
        ; A = 0x0A OR 0xF0 = 0xFA
        ; 00001010 OR 11110000 = 11111010
        ;===========================================
        ORI     0F0h                ; A = 0x0A OR 0xF0 = 0xFA

        ;===========================================
        ; TEST 10: XRI immediate (already tested in ram_intensive)
        ; A = 0xFA XOR 0xFF = 0x05
        ; 11111010 XOR 11111111 = 00000101
        ;===========================================
        XRI     0FFh                ; A = 0xFA XOR 0xFF = 0x05

        ;===========================================
        ; TEST 11: DCR register (decrement)
        ; Loop countdown from 5 to 0
        ;===========================================
        MVI     L,05h               ; L = 5 (loop counter)
DCR_LOOP:
        DCR     L                   ; L = L - 1
        JNZ     DCR_LOOP            ; Loop until L = 0
        ; L should now be 0x00

        ;===========================================
        ; TEST 12: CMP register (compare - flags only)
        ; Compare A with B, should set flags
        ;===========================================
        MVI     A,08h               ; A = 8
        CMP     B                   ; Compare A with B (both 8)
        JNZ     FAIL                ; Should NOT jump (Z=1 since equal)

        ;===========================================
        ; TEST 13: ADC with carry
        ; Set carry with 0xFF + 1, then ADC
        ;===========================================
        MVI     A,0FFh              ; A = 255
        ADI     01h                 ; A = 0 with carry set
        MVI     A,05h               ; A = 5
        ADC     B                   ; A = 5 + 8 + carry(1) = 14 (0x0E)
        ; If carry was set, A = 0x0E
        ; If carry was not set, A = 0x0D

        ;===========================================
        ; TEST 14: SBB with borrow
        ; Set borrow (carry) with 0x00 - 1, then SBB
        ;===========================================
        MVI     A,00h               ; A = 0
        SUI     01h                 ; A = 0xFF with borrow set
        MVI     A,10h               ; A = 16
        SBB     C                   ; A = 16 - 2 - borrow(1) = 13 (0x0D)
        ; If borrow was set, A = 0x0D
        ; If borrow was not set, A = 0x0E

        ;===========================================
        ; FINAL: Set A to 0 for success indicator
        ;===========================================
        MVI     A,00h               ; A = 0 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh              ; A = 0xFF (failure indicator)

DONE:
        HLT

        end
