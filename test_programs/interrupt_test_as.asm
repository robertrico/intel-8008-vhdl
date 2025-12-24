; Intel 8008 Interrupt Test Program
; For AS Macro Assembler
;
; Purpose: Test interrupt handling mechanism
;   - Bootstrap interrupt (RST 0) starts execution
;   - Runtime interrupt (RST 7) calls handler during execution
;   - HLT wake-up via interrupt
;
; Memory Map:
;   0x0000 (RST 0): Bootstrap jump to MAIN
;   0x0038 (RST 7): Interrupt handler
;   0x0100 (MAIN): Main program
;
; Test Sequence:
;   1. Bootstrap interrupt (RST 0) starts CPU
;   2. MAIN initializes registers and outputs CP1
;   3. Program runs a loop, incrementing B, outputs CP2
;   4. Program enters HLT (STOPPED state)
;   5. Testbench triggers RST 7 interrupt
;   6. RST 7 handler runs, sets D=0xAA, outputs CP3, returns
;   7. After RET, CPU continues after HLT (or halts again)
;   8. Final state verified
;
; Checkpoint Results:
;   CP1: Initial state after bootstrap - B=0x01, D=0x00
;   CP2: After loop - B=0x05, D=0x00
;   CP3: Inside RST 7 handler - D=0xAA
;   CP4: After interrupt return - D=0xAA (handler ran)

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

; =========================================================================
; RST 0 Vector (0x0000) - Bootstrap entry point
; =========================================================================
        org     0000h
RST0:
        JMP     MAIN            ; Jump to main program

; =========================================================================
; RST 7 Vector (0x0038) - Interrupt handler
; =========================================================================
        org     0038h
RST7:
        ; Interrupt handler: Set flag in D register
        MVI     D,0AAh          ; D = 0xAA (interrupt handler was called)

        ; CHECKPOINT 3: Inside interrupt handler
        MVI     A,03h
        OUT     CHKPT           ; CP3: D=0xAA

        ; Return from interrupt
        RET

; =========================================================================
; MAIN Program (0x0100)
; =========================================================================
        org     0100h
MAIN:
        ; Initialize registers
        MVI     B,00h           ; B = 0 (loop counter)
        MVI     C,00h           ; C = 0 (unused)
        MVI     D,00h           ; D = 0 (will be set by interrupt handler)
        MVI     E,00h           ; E = 0 (unused)
        MVI     H,00h           ; H = 0 (unused)
        MVI     L,00h           ; L = 0 (unused)

        ; Increment B to show program is running
        INR     B               ; B = 1

        ; CHECKPOINT 1: Initial state after bootstrap
        MVI     A,01h
        OUT     CHKPT           ; CP1: B=0x01, D=0x00

        ; Run a counting loop
        MVI     B,00h           ; Reset B
LOOP:
        INR     B               ; B++
        MVI     A,05h           ; Compare target
        CMP     B               ; A - B
        JNZ     LOOP            ; Loop until B = 5

        ; CHECKPOINT 2: After loop
        MVI     A,02h
        OUT     CHKPT           ; CP2: B=0x05, D=0x00

        ; Now HALT and wait for interrupt
        ; The testbench will trigger RST 7 interrupt to wake us
        HLT

        ; After interrupt handler returns, we continue here
        ; (Actually, after RST 7 RET, execution continues from after HLT)

        ; CHECKPOINT 4: After interrupt return
        MVI     A,04h
        OUT     CHKPT           ; CP4: D=0xAA (interrupt handler set this)

        ; Verify D was set by interrupt handler
        MVI     A,0AAh
        CMP     D               ; D should be 0xAA
        JNZ     FAIL

        ; SUCCESS: Final checkpoint
        MVI     A,05h
        OUT     CHKPT           ; CP5: Success
        MVI     A,00h           ; A = 0 (success)
        JMP     DONE

FAIL:
        MVI     A,0FFh          ; A = 0xFF (failure)

DONE:
        HLT

        end
