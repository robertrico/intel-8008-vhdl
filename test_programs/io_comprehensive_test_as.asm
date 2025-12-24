; Intel 8008 Comprehensive I/O Instruction Test Program
; For AS Macro Assembler
;
; Purpose: Test all I/O instructions comprehensively
;   - INP 0-7: All 8 input ports
;   - OUT 8-15, 24-31: Multiple output ports
;
; Port allocation (simulated in b8008_top.vhdl):
;   Input ports:
;     Port 0: 0x55
;     Port 1: 0xAA
;     Port 2: 0x42
;     Port 3: 0x03
;     Port 4: 0x04
;     Port 5: 0x05
;     Port 6: 0x06
;     Port 7: 0x07
;   Output ports 8-31: Latch values for verification
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  IN 0 - L=0x55
;   CP2:  IN 1 - L=0xAA
;   CP3:  IN 2 - L=0x42
;   CP4:  IN 3 - L=0x03
;   CP5:  IN 4 - L=0x04
;   CP6:  IN 5 - L=0x05
;   CP7:  IN 6 - L=0x06
;   CP8:  IN 7 - L=0x07
;   CP9:  OUT 8-15 tests
;   CP10: OUT 16-23 tests
;   CP11: OUT 24-30 tests
;   CP12: Final success

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
        ; TEST ALL 8 INPUT PORTS
        ;===========================================

        ; IN 0 - expect 0x55
        IN      0               ; A = 0x55
        MOV     L,A             ; Save to L
        MVI     A,01h
        OUT     CHKPT           ; CP1: L=0x55
        MOV     A,L             ; Restore A
        CPI     55h
        JNZ     FAIL

        ; IN 1 - expect 0xAA
        IN      1               ; A = 0xAA
        MOV     L,A             ; Save to L
        MVI     A,02h
        OUT     CHKPT           ; CP2: L=0xAA
        MOV     A,L             ; Restore A
        CPI     0AAh
        JNZ     FAIL

        ; IN 2 - expect 0x42
        IN      2               ; A = 0x42
        MOV     L,A             ; Save to L
        MVI     A,03h
        OUT     CHKPT           ; CP3: L=0x42
        MOV     A,L             ; Restore A
        CPI     42h
        JNZ     FAIL

        ; IN 3 - expect 0x03
        IN      3               ; A = 0x03
        MOV     L,A             ; Save to L
        MVI     A,04h
        OUT     CHKPT           ; CP4: L=0x03
        MOV     A,L             ; Restore A
        CPI     03h
        JNZ     FAIL

        ; IN 4 - expect 0x04
        IN      4               ; A = 0x04
        MOV     L,A             ; Save to L
        MVI     A,05h
        OUT     CHKPT           ; CP5: L=0x04
        MOV     A,L             ; Restore A
        CPI     04h
        JNZ     FAIL

        ; IN 5 - expect 0x05
        IN      5               ; A = 0x05
        MOV     L,A             ; Save to L
        MVI     A,06h
        OUT     CHKPT           ; CP6: L=0x05
        MOV     A,L             ; Restore A
        CPI     05h
        JNZ     FAIL

        ; IN 6 - expect 0x06
        IN      6               ; A = 0x06
        MOV     L,A             ; Save to L
        MVI     A,07h
        OUT     CHKPT           ; CP7: L=0x06
        MOV     A,L             ; Restore A
        CPI     06h
        JNZ     FAIL

        ; IN 7 - expect 0x07
        IN      7               ; A = 0x07
        MOV     L,A             ; Save to L
        MVI     A,08h
        OUT     CHKPT           ; CP8: L=0x07
        MOV     A,L             ; Restore A
        CPI     07h
        JNZ     FAIL

        ;===========================================
        ; TEST OUTPUT PORTS 8-15
        ; Write unique values to each
        ;===========================================
        MVI     A,80h
        OUT     8               ; Port 8 = 0x80
        MVI     A,81h
        OUT     9               ; Port 9 = 0x81
        MVI     A,82h
        OUT     10              ; Port 10 = 0x82
        MVI     A,83h
        OUT     11              ; Port 11 = 0x83
        MVI     A,84h
        OUT     12              ; Port 12 = 0x84
        MVI     A,85h
        OUT     13              ; Port 13 = 0x85
        MVI     A,86h
        OUT     14              ; Port 14 = 0x86
        MVI     A,87h
        OUT     15              ; Port 15 = 0x87
        ; CHECKPOINT 9: OUT 8-15 complete
        MVI     A,09h
        OUT     CHKPT           ; CP9

        ;===========================================
        ; TEST OUTPUT PORTS 16-23
        ;===========================================
        MVI     A,90h
        OUT     16              ; Port 16 = 0x90
        MVI     A,91h
        OUT     17              ; Port 17 = 0x91
        MVI     A,92h
        OUT     18              ; Port 18 = 0x92
        MVI     A,93h
        OUT     19              ; Port 19 = 0x93
        MVI     A,94h
        OUT     20              ; Port 20 = 0x94
        MVI     A,95h
        OUT     21              ; Port 21 = 0x95
        MVI     A,96h
        OUT     22              ; Port 22 = 0x96
        MVI     A,97h
        OUT     23              ; Port 23 = 0x97
        ; CHECKPOINT 10: OUT 16-23 complete
        MVI     A,0Ah
        OUT     CHKPT           ; CP10

        ;===========================================
        ; TEST OUTPUT PORTS 24-30
        ; (Port 31 is the checkpoint port)
        ;===========================================
        MVI     A,0A0h
        OUT     24              ; Port 24 = 0xA0
        MVI     A,0A1h
        OUT     25              ; Port 25 = 0xA1
        MVI     A,0A2h
        OUT     26              ; Port 26 = 0xA2
        MVI     A,0A3h
        OUT     27              ; Port 27 = 0xA3
        MVI     A,0A4h
        OUT     28              ; Port 28 = 0xA4
        MVI     A,0A5h
        OUT     29              ; Port 29 = 0xA5
        MVI     A,0A6h
        OUT     30              ; Port 30 = 0xA6
        ; CHECKPOINT 11: OUT 24-30 complete
        MVI     A,0Bh
        OUT     CHKPT           ; CP11

        ;===========================================
        ; FINAL SUCCESS
        ;===========================================
        MVI     A,0Ch
        OUT     CHKPT           ; CP12: Final success
        MVI     A,00h           ; A = 0 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure indicator)

DONE:
        HLT

        end
