; Intel 8008 PC Carry During CALL Test Program
; For AS Macro Assembler
;
; Purpose: Test that CALL instruction correctly handles PC carry propagation
; when the return address computation crosses a 256-byte boundary.
;
; The bug scenario:
;   - CALL instruction at 0x00FC-0x00FE
;   - PC increments during CALL execution to compute return address
;   - PC goes from 0x00FF to 0x0100 (lower byte wraps, upper byte should increment)
;   - BUG: Upper byte doesn't increment, return address becomes 0x0000
;   - RET then jumps to 0x0000 (which has HLT), halting prematurely
;
; This test places a CALL at address 0x00FC to trigger this scenario.
; The subroutine at 0x0200 returns immediately.
; After RET, execution should continue at 0x0100 (the instruction after CALL).
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  Before CALL            - D=0x00, E=0x01
;   CP2:  Inside subroutine      - D=0x00, E=0x02
;   CP3:  After RET              - D=0x00, E=0x03 (THIS IS THE KEY TEST)
;   CP4:  Final success          - A=0x00
;
; Expected final state:
;   A = 0x00 (success)
;   D = 0x00 (success marker)
;   E = 0x04 (checkpoint counter)

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

; Reset vector at 0x0000
        org     0000h
STARTUP:
        ; Jump to main code that sets up the test
        JMP     SETUP

; Padding to place CALL at exactly 0x00FC
        org     00F8h
        ; At 0x00F8: Set up checkpoint before CALL
        MVI     E,01h           ; E = 0x01 (pre-call marker)
        MVI     A,01h
        OUT     CHKPT           ; CP1: E=0x01

; At 0x00FC: The critical CALL instruction
; CALL is 3 bytes: opcode at 0x00FC, low addr at 0x00FD, high addr at 0x00FE
; After executing CALL, return address should be 0x00FF + 1 = 0x0100
        CALL    SUBROUTINE      ; This call at 0x00FC should return to 0x0100

; At 0x0100: Continuation after RET (the key test point)
        org     0100h
AFTER_RET:
        ; If we get here, the PC carry worked correctly!
        MVI     E,03h           ; E = 0x03 (post-return marker)
        MVI     A,03h
        OUT     CHKPT           ; CP3: E=0x03 (THE KEY CHECKPOINT)
        JMP     SUCCESS

; Setup code at 0x0040
        org     0040h
SETUP:
        MVI     D,00h           ; D = 0x00 (success marker, will be 0xFF on failure)
        MVI     E,00h           ; E = checkpoint counter
        ; Jump to the code just before the CALL
        JMP     00F8h           ; Jump to pre-call setup

; Success path
SUCCESS:
        MVI     E,04h           ; E = 0x04 (final checkpoint)
        MVI     A,04h
        OUT     CHKPT           ; CP4: Final success
        MVI     A,00h           ; A = 0x00 (success)
        HLT

; Failure path (should never reach here in correct execution)
FAIL:
        MVI     D,0FFh          ; D = 0xFF (failure marker)
        MVI     A,0FFh
        OUT     CHKPT           ; Failure checkpoint
        HLT

; Subroutine at 0x0200
        org     0200h
SUBROUTINE:
        ; Just set a checkpoint marker and return
        MVI     E,02h           ; E = 0x02 (inside subroutine marker)
        MVI     A,02h
        OUT     CHKPT           ; CP2: E=0x02
        RET                     ; Return to caller (should be 0x0100)

        end
