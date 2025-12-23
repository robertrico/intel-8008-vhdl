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
        out     8               ; Output A to port 8
        cpi     55h             ; Compare A with 0x55
        jnz     FAIL            ; If not equal, fail
        inr     b               ; Increment test counter

; Test 2: IN 1 -> OUT 9
        in      1               ; A = input from port 1 (expect 0xAA)
        out     9               ; Output A to port 9
        cpi     0AAh            ; Compare A with 0xAA
        jnz     FAIL            ; If not equal, fail
        inr     b               ; Increment test counter

; Test 3: IN 2 (expect 0x42)
        in      2               ; A = input from port 2 (expect 0x42)
        cpi     42h             ; Compare A with 0x42
        jnz     FAIL            ; If not equal, fail
        inr     b               ; Increment test counter

; All tests passed
        mvi     a, 0            ; A = 0 (success)
        hlt

FAIL:
        mvi     a, 0FFh         ; A = 0xFF (failure)
        hlt
