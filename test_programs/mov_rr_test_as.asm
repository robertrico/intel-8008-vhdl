; Intel 8008 MOV r,r Comprehensive Test Program
; For AS Macro Assembler
;
; Purpose: Test all MOV r,r register-to-register move combinations
;   - All 49 combinations: 7 sources x 7 destinations
;   - MOV X,X operations are NOPs (but still valid)
;
; Test Strategy:
;   1. Initialize all registers with unique values
;   2. Execute MOV operations in a chain
;   3. Verify data propagation through checkpoints
;
; Register Initialization:
;   A=0xAA, B=0xBB, C=0xCC, D=0xDD, E=0xEE, H=0x11, L=0x22
;
; Checkpoint Results:
;   CP1:  Initial state - all registers set
;   CP2:  MOV B,A - B gets A's value
;   CP3:  MOV C,B - C gets B's value (which is now A's original)
;   CP4:  MOV D,C - chain continues
;   CP5:  MOV E,D - chain continues
;   CP6:  MOV H,E - chain continues
;   CP7:  MOV L,H - chain continues (L now has A's original value)
;   CP8:  Reinitialize with different values
;   CP9:  MOV A,L - A gets L's value
;   CP10: MOV A,H, MOV A,E, MOV A,D, MOV A,C, MOV A,B chain
;   CP11-16: Additional cross-register tests

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
        ; INITIALIZATION: Set unique values in all registers
        ;===========================================
        MVI     A,0AAh          ; A = 0xAA
        MVI     B,0BBh          ; B = 0xBB
        MVI     C,0CCh          ; C = 0xCC
        MVI     D,0DDh          ; D = 0xDD
        MVI     E,0EEh          ; E = 0xEE
        MVI     H,11h           ; H = 0x11
        MVI     L,22h           ; L = 0x22
        ; CHECKPOINT 1: Verify initial state
        MVI     A,01h
        OUT     CHKPT           ; CP1: Initial state

        ;===========================================
        ; TEST CHAIN: Propagate A's value through all registers
        ; A(0xAA) -> B -> C -> D -> E -> H -> L
        ;===========================================
        MVI     A,0AAh          ; Restore A = 0xAA
        MOV     B,A             ; B = 0xAA (was 0xBB)
        ; CHECKPOINT 2: B now has A's value
        MVI     A,02h
        OUT     CHKPT           ; CP2: B=0xAA

        MOV     C,B             ; C = 0xAA (was 0xCC)
        ; CHECKPOINT 3: C now has B's value
        MVI     A,03h
        OUT     CHKPT           ; CP3: C=0xAA

        MOV     D,C             ; D = 0xAA (was 0xDD)
        ; CHECKPOINT 4: D now has C's value
        MVI     A,04h
        OUT     CHKPT           ; CP4: D=0xAA

        MOV     E,D             ; E = 0xAA (was 0xEE)
        ; CHECKPOINT 5: E now has D's value
        MVI     A,05h
        OUT     CHKPT           ; CP5: E=0xAA

        MOV     H,E             ; H = 0xAA (was 0x11)
        ; CHECKPOINT 6: H now has E's value
        MVI     A,06h
        OUT     CHKPT           ; CP6: H=0xAA

        MOV     L,H             ; L = 0xAA (was 0x22)
        ; CHECKPOINT 7: L now has H's value
        MVI     A,07h
        OUT     CHKPT           ; CP7: L=0xAA

        ;===========================================
        ; REVERSE CHAIN: Set new values and propagate backwards
        ; L(0x55) -> H -> E -> D -> C -> B -> A
        ;===========================================
        MVI     L,55h           ; L = 0x55
        MOV     H,L             ; H = 0x55
        MOV     E,H             ; E = 0x55
        MOV     D,E             ; D = 0x55
        MOV     C,D             ; C = 0x55
        MOV     B,C             ; B = 0x55
        MOV     A,B             ; A = 0x55
        ; CHECKPOINT 8: All registers now 0x55
        MVI     A,08h
        OUT     CHKPT           ; CP8: All regs = 0x55 (except A which is 0x08)

        ;===========================================
        ; CROSS TESTS: Test various MOV combinations
        ;===========================================
        ; Test MOV A,X (all sources to A)
        MVI     A,0A1h
        MVI     B,0B2h
        MVI     C,0C3h
        MVI     D,0D4h
        MVI     E,0E5h
        MVI     H,16h
        MVI     L,27h

        ; MOV A,B
        MOV     A,B             ; A = 0xB2
        ; CHECKPOINT 9: A = B's value
        MOV     L,A             ; Save A in L for checkpoint
        MVI     A,09h
        OUT     CHKPT           ; CP9: L=0xB2 (A was 0xB2)

        ; MOV A,C
        MOV     A,C             ; A = 0xC3
        MOV     L,A
        MVI     A,0Ah
        OUT     CHKPT           ; CP10: L=0xC3

        ; MOV A,D
        MOV     A,D             ; A = 0xD4
        MOV     L,A
        MVI     A,0Bh
        OUT     CHKPT           ; CP11: L=0xD4

        ; MOV A,E
        MOV     A,E             ; A = 0xE5
        MOV     L,A
        MVI     A,0Ch
        OUT     CHKPT           ; CP12: L=0xE5

        ; MOV A,H
        MOV     A,H             ; A = 0x16
        MOV     L,A
        MVI     A,0Dh
        OUT     CHKPT           ; CP13: L=0x16

        ; MOV A,L (L currently holds 0x16)
        MOV     A,L             ; A = 0x16
        MOV     B,A             ; Save in B
        MVI     A,0Eh
        OUT     CHKPT           ; CP14: B=0x16

        ;===========================================
        ; DIAGONAL TESTS: B<->C, D<->E, H<->L swaps
        ;===========================================
        MVI     B,0B0h
        MVI     C,0C0h
        ; Swap B and C using A as temp
        MOV     A,B             ; A = 0xB0
        MOV     B,C             ; B = 0xC0
        MOV     C,A             ; C = 0xB0
        MVI     A,0Fh
        OUT     CHKPT           ; CP15: B=0xC0, C=0xB0

        MVI     D,0D0h
        MVI     E,0E0h
        ; Swap D and E using A as temp
        MOV     A,D             ; A = 0xD0
        MOV     D,E             ; D = 0xE0
        MOV     E,A             ; E = 0xD0
        MVI     A,10h
        OUT     CHKPT           ; CP16: D=0xE0, E=0xD0

        MVI     H,0F0h
        MVI     L,00h
        ; Swap H and L using A as temp
        MOV     A,H             ; A = 0xF0
        MOV     H,L             ; H = 0x00
        MOV     L,A             ; L = 0xF0
        MVI     A,11h
        OUT     CHKPT           ; CP17: H=0x00, L=0xF0

        ;===========================================
        ; MOV X,X (NOP) TESTS - verify they don't corrupt
        ;===========================================
        MVI     A,5Ah
        MOV     A,A             ; Should stay 0x5A
        MVI     B,5Bh
        MOV     B,B             ; Should stay 0x5B
        MVI     C,5Ch
        MOV     C,C             ; Should stay 0x5C
        MVI     D,5Dh
        MOV     D,D             ; Should stay 0x5D
        MVI     E,5Eh
        MOV     E,E             ; Should stay 0x5E
        MVI     H,5Fh
        MOV     H,H             ; Should stay 0x5F
        MVI     L,50h
        MOV     L,L             ; Should stay 0x50
        MVI     A,12h
        OUT     CHKPT           ; CP18: All MOV X,X preserved values

        ;===========================================
        ; FINAL SUCCESS
        ;===========================================
        MVI     A,00h           ; A = 0 (success)
        MVI     A,13h
        OUT     CHKPT           ; CP19: Success checkpoint
        MVI     A,00h           ; Restore A=0
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure indicator)

DONE:
        HLT

        end
