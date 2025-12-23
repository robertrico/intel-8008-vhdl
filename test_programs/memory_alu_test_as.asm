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
; Test data is stored at address 0x00F0-0x00FF
; Expected final state:
;   A = 0x00 (success)
;   B = 0x01 (completion marker)
;   H = 0x00
;   L = 0xF0

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
        JNZ     FAIL            ; Fail if not equal (zero flag not set)

        ;===========================================
        ; TEST 9: CMP M - Compare Memory (Greater)
        ; Memory[0x00F5] = 0x42
        ; A = 0x50
        ; Expected: Zero flag clear, Carry clear (A > M)
        ;===========================================
        MVI     A,50h           ; A = 0x50
        CMP     M               ; Compare A with memory (0x42)
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
        JZ      FAIL            ; Fail if zero flag set
        JNC     FAIL            ; Fail if carry NOT set (A should be less)

        ;===========================================
        ; All tests passed! Set success markers
        ;===========================================
        MVI     L,0F0h          ; Reset L to 0xF0
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
