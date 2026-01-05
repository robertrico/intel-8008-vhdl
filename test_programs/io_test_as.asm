; Intel 8008 INP/OUT Instruction Test Program
; For AS Macro Assembler
;
; Purpose: Test I/O instructions
;   - INP (IN): Read from input port to accumulator
;   - OUT: Write accumulator to output port
;
; Port allocation (simulated in b8008_top.vhdl):
;   Input ports 0-7: Return test values
;     Port 0: 0x55
;     Port 1: 0xAA
;     Port 2: 0x42
;     Port 3-7: port number
;   Output ports 8-31: Latch values for verification
;
; Uses OUT 31 checkpoints for assertion-based verification.
;
; Checkpoint Results:
;   CP1:  After IN 0  - L=0x55
;   CP2:  After OUT 8 - port 8 written
;   CP3:  After IN 1  - L=0xAA
;   CP4:  After OUT 9 - port 9 written
;   CP5:  After IN 2  - L=0x42
;   CP6:  Final       - A=0x00
;
; Test sequence:
;   1. Read from input port 0 (expect 0x55)
;   2. Write to output port 8
;   3. Read from input port 1 (expect 0xAA)
;   4. Write to output port 9
;   5. Verify accumulator values match expected
;
; Expected final state:
;   A = 0x00 (success)
;   B = 0x03 (test count - 3 tests)
;   Output port 8 = 0x55
;   Output port 9 = 0xAA

        cpu     8008new
        page    0

; Checkpoint port constant
CHKPT   equ     31              ; Port 31 = checkpoint/assertion port

; RST 0 vector at 0x0000 (bootstrap handler - jumps to MAIN)
        org     0000h
RST0_VEC:
        jmp     MAIN

; Main program at 0x0100
        org     0100h
MAIN:
        mvi     b, 0            ; B = test counter

; Test 1: IN 0 -> OUT 8
        in      0               ; A = input from port 0 (expect 0x55)
        ; CHECKPOINT 1: Verify IN 0
        mov     l, a            ; Save A to L
        mvi     a, 01h
        out     CHKPT           ; CP1: L=0x55
        mov     a, l            ; Restore A

        out     8               ; Output A to port 8
        ; CHECKPOINT 2: Verify OUT 8
        mvi     a, 02h
        out     CHKPT           ; CP2: port 8 written

        mov     a, l            ; Restore A from L
        cpi     55h             ; Compare A with 0x55
        jnz     FAIL            ; If not equal, fail
        inr     b               ; Increment test counter

; Test 2: IN 1 -> OUT 9
        in      1               ; A = input from port 1 (expect 0xAA)
        ; CHECKPOINT 3: Verify IN 1
        mov     l, a            ; Save A to L
        mvi     a, 03h
        out     CHKPT           ; CP3: L=0xAA
        mov     a, l            ; Restore A

        out     9               ; Output A to port 9
        ; CHECKPOINT 4: Verify OUT 9
        mvi     a, 04h
        out     CHKPT           ; CP4: port 9 written

        mov     a, l            ; Restore A from L
        cpi     0AAh            ; Compare A with 0xAA
        jnz     FAIL            ; If not equal, fail
        inr     b               ; Increment test counter

; Test 3: IN 2 (expect 0x42)
        in      2               ; A = input from port 2 (expect 0x42)
        ; CHECKPOINT 5: Verify IN 2
        mov     l, a            ; Save A to L
        mvi     a, 05h
        out     CHKPT           ; CP5: L=0x42
        mov     a, l            ; Restore A

        cpi     42h             ; Compare A with 0x42
        jnz     FAIL            ; If not equal, fail
        inr     b               ; Increment test counter

; Test 4: CPI with 0x0A (LF character) - testing specific immediate value
        ; This tests if CPI works correctly with value 0x0A
        mvi     a, 0Ah          ; A = 0x0A
        ; CHECKPOINT 7: Before CPI 0x0A
        mov     l, a            ; Save A to L
        mvi     a, 07h
        out     CHKPT           ; CP7: L=0x0A, about to execute CPI 0x0A
        mov     a, l            ; Restore A (A = 0x0A)

        cpi     0Ah             ; Compare A with 0x0A (should set zero flag)
        jnz     FAIL            ; If not equal, fail (zero flag should be set)
        inr     b               ; Increment test counter

        ; CHECKPOINT 8: After CPI 0x0A succeeded
        mvi     a, 08h
        out     CHKPT           ; CP8: CPI 0x0A worked correctly

; Test 5: CPI with 0x0D (CR character) - for comparison
        mvi     a, 0Dh          ; A = 0x0D
        cpi     0Dh             ; Compare A with 0x0D (should set zero flag)
        jnz     FAIL            ; If not equal, fail
        inr     b               ; Increment test counter

; All tests passed
        ; CHECKPOINT 9: Final success
        mvi     a, 09h
        out     CHKPT           ; CP9: success
        mvi     a, 0            ; A = 0 (success)
        hlt

FAIL:
        mvi     a, 0FFh         ; A = 0xFF (failure)
        hlt
