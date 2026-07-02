; Intel 8008 INR/DCR Carry-Preservation Test Program
; For AS Macro Assembler
;
; Purpose: Verify that INR/DCR do NOT touch the Carry flag (8008 spec:
; increment/decrement affect Z/S/P only). This is load-bearing for any
; multi-byte arithmetic: SCELBAL's ADDER does "ADC M / INR L / ADC M"
; chains and its rotate loops do "RAL / DCR B / RAL" - both corrupt if
; INR/DCR clobber carry. (Regression for the bug that made the RAM-loaded
; mandelbrot print all asterisks: escape test never fired because every
; FP add and mantissa rotate lost its carry.)
;
; Checkpoint Results:
;   CP1: INR with carry=1        - B=0x06, CF=1 (carry survives INR)
;   CP2: INR 0xFF wrap, carry=0  - B=0x00, CF=0 (wrap leaks no carry)
;   CP3: DCR 0x00 borrow, carry=1- C=0xFF, CF=1 (borrow doesn't clobber)
;   CP4: ADC/INR/ADC chain       - B=0x00, C=0x01 (16-bit 0x00FF+1=0x0100)
;   CP5: RAL/DCR/RAL chain       - B=0x00, C=0x01 (16-bit rotate through C)
;   CP6: Final                   - A=0x10 (success)

        cpu     8008new
        page    0

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
        ; TEST 1: INR must preserve carry=1
        ;===========================================
        MVI     A,0FFh
        ADI     02h             ; A=0x01, carry=1
        MVI     B,05h
        INR     B               ; B=6; carry must STAY 1
        MVI     A,01h
        OUT     CHKPT           ; CP1: B=0x06, CF=1

        ;===========================================
        ; TEST 2: INR wrap (0xFF->0x00) must not leak a carry
        ;===========================================
        MVI     A,01h
        ADI     01h             ; A=0x02, carry=0
        MVI     B,0FFh
        INR     B               ; B=0x00 (internal add carries); flag must STAY 0
        MVI     A,02h
        OUT     CHKPT           ; CP2: B=0x00, CF=0

        ;===========================================
        ; TEST 3: DCR borrow (0x00->0xFF) must preserve carry=1
        ;===========================================
        MVI     A,0FFh
        ADI     02h             ; carry=1
        MVI     C,00h
        DCR     C               ; C=0xFF (internal subtract borrows); flag must STAY 1
        MVI     A,03h
        OUT     CHKPT           ; CP3: C=0xFF, CF=1

        ;===========================================
        ; TEST 4: SCELBAL ADDER pattern
        ; 16-bit add 0x00FF + 0x0001 with a pointer INR between the
        ; low-byte and high-byte adds. Correct result 0x0100.
        ;===========================================
        MVI     E,10h           ; stand-in memory pointer
        MVI     A,0FFh
        ADI     01h             ; low byte: 0xFF+0x01 = 0x00, carry=1
        MOV     B,A             ; B = low result (0x00)
        INR     E               ; pointer++ - must NOT eat the carry
        MVI     A,00h
        ACI     00h             ; high byte: 0+0+carry = 0x01 if carry survived
        MOV     C,A             ; C = high result
        MVI     A,04h
        OUT     CHKPT           ; CP4: B=0x00, C=0x01

        ;===========================================
        ; TEST 5: SCELBAL ROTATL pattern
        ; 16-bit rotate left through carry with the loop counter DCR
        ; between the two RALs. 0x0080 << 1 = 0x0100.
        ; (Carry entering is 0: TEST 4's ACI produced no carry out.)
        ;===========================================
        MVI     D,02h           ; stand-in loop counter
        MVI     A,80h
        RAL                     ; A=0x00, carry=1 (bit 7 rotated out)
        MOV     B,A             ; B = low result (0x00)
        DCR     D               ; counter-- - must NOT eat the carry
        MVI     A,00h
        RAL                     ; A=0x01 (carry rotated in) if carry survived
        MOV     C,A             ; C = high result
        MVI     A,05h
        OUT     CHKPT           ; CP5: B=0x00, C=0x01

        ;===========================================
        ; FINAL: success checkpoint
        ;===========================================
        MVI     A,10h
        OUT     CHKPT           ; CP6: A=0x10
        HLT

        end
