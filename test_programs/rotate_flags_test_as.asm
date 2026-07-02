; Intel 8008 Rotate Flag-Preservation Test Program
; For AS Macro Assembler
;
; Purpose: rotates (RLC/RRC/RAL/RAR) must update CARRY ONLY.
; Z/S/P must hold their pre-rotate values (8008 datasheet). The period
; idiom this protects: set flags with arithmetic, rotate, then branch
; on the *preserved* flag (SCELBI FP and others rely on it).
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1: after XRA A then RLC(0x80)  - CF=1, ZF=1, SF=0, PF=1 (Z/S/P from XRA)
;   CP2: after ADI-carry then RAR(1) - CF=1, ZF=1, SF=0, PF=1 (Z/S/P from ADI)
;   CP3: after ANA(0x55) then RRC(1) - CF=1, ZF=0, SF=0, PF=1 (Z/S/P from ANA)
;   CP4: after ANA(0xFF) then RAL(0x80) - CF=1, ZF=0, SF=1, PF=1
;   CP5: final - success
;
; Final Register State:
;   A: 0x00 (success indicator)

        cpu     8008new
        page    0

CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

        org     0000h
STARTUP:
        MOV     A,A                 ; NOP (PC sync)
        MOV     A,A                 ; NOP
        JMP     MAIN

        org     0100h
MAIN:
        ;===========================================
        ; TEST 1: RLC preserves Z=1 S=0 P=1 from XRA A
        ; broken RTL recomputes from result 0x01: Z=0, P=0
        ;===========================================
        XRA     A                   ; A=0: ZF=1 SF=0 PF=1 CF=0
        MVI     A,80h               ; MVI touches no flags
        RLC                         ; A=0x01, CF=1; Z/S/P must hold
        MVI     A,01h
        OUT     CHKPT               ; CP1: CF=1 ZF=1 SF=0 PF=1

        ;===========================================
        ; TEST 2: RAR preserves Z=1 S=0 P=1 from ADI
        ; broken RTL recomputes from result 0x80: Z=0, S=1, P=0
        ;===========================================
        MVI     A,0FFh
        ADI     01h                 ; A=0: ZF=1 SF=0 PF=1 CF=1
        MVI     A,01h
        RAR                         ; A=0x80 (old CF to bit7), CF=1
        MVI     A,02h
        OUT     CHKPT               ; CP2: CF=1 ZF=1 SF=0 PF=1

        ;===========================================
        ; TEST 3: RRC preserves Z=0 S=0 P=1 from ANA 0x55
        ; broken RTL recomputes from result 0x80: S=1, P=0
        ;===========================================
        MVI     A,55h
        ANA     A                   ; A=0x55: ZF=0 SF=0 PF=1 CF=0
        MVI     A,01h
        RRC                         ; A=0x80, CF=1; Z/S/P must hold
        MVI     A,03h
        OUT     CHKPT               ; CP3: CF=1 ZF=0 SF=0 PF=1

        ;===========================================
        ; TEST 4: RAL preserves Z=0 S=1 P=1 from ANA 0xFF
        ; RAL of 0x80 with CF=0 gives A=0x00: broken RTL flips ZF to 1
        ;===========================================
        MVI     A,0FFh
        ANA     A                   ; A=0xFF: ZF=0 SF=1 PF=1 CF=0
        MVI     A,80h
        RAL                         ; A=0x00, CF=1; ZF must STAY 0
        MVI     A,04h
        OUT     CHKPT               ; CP4: CF=1 ZF=0 SF=1 PF=1

        MVI     A,00h               ; success indicator
        MVI     A,05h
        OUT     CHKPT               ; CP5: final
        MVI     A,00h

        HLT

        end
