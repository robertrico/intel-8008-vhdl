            PAGE 0               ; suppress page headings in AS listing file
;===========================================================================
; STACKWRAP - proves the 8008's 8-register address stack (SP indexes the
; current PC; 7 nested returns) wraps per spec on the 8th nested CALL.
;
; Every character is sent INLINE (no subroutine) so the CALL ledger is
; exactly the eight L1..L8 calls:
;
;   descent: START calls L1, L1 calls L2, ... L7 calls L8 (8 pushes).
;   The 8th CALL wraps SP 7->0 and overwrites the return-to-START context.
;   While L8 runs, stack reg 0 is the live PC; it freezes pointing just
;   past L8's RET the moment that RET fires (SP 0->7).
;   unwind: RETs walk back through L7..L1's rets, then the final RET
;   (SP 1->0) resumes from reg 0 = the WRAP landing pad below L8.
;
; Serial output (this is a CHARACTERIZER - it reports which stack
; architecture the CPU actually has):
;   real 8008 (PC inside the 8 regs): STK 12345678 WRAP OK
;   b8008 today (separate PC block + 8 return slots - KNOWN DEVIATION,
;   see docs/superpowers/specs/2026-07-02-silicon-gaps-design.md):
;                                     STK 123456788RET
;   anything else: garbage / silence  (corrupted unwind)
;
;   make assemble-sample PROG=stackwrap_ram
;   ./send_hex.py test_programs/samples/stackwrap_ram.hex   (minicom closed)
;   then in minicom:  G 2100
;===========================================================================

            cpu 8008new
CR          EQU 0Dh
LF          EQU 0Ah

; send the char in A, inline pacing (~45us/instr vs 87us frame @115200)
PUTC        MACRO
            out 09h
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            ENDM

            ORG 2100H
START:      mvi a,'S'
            PUTC
            mvi a,'T'
            PUTC
            mvi a,'K'
            PUTC
            mvi a,' '
            PUTC
            call L1              ; 8-deep descent begins
; Reached only if the stack held all 8 returns (b8008's split-PC design;
; a real 8008 never gets here):
            mvi a,'8'
            PUTC
            mvi a,'R'
            PUTC
            mvi a,'E'
            PUTC
            mvi a,'T'
            PUTC
            mvi a,CR
            PUTC
            mvi a,LF
            PUTC
            jmp 0

L1:         mvi a,'1'
            PUTC
            call L2
            ret
L2:         mvi a,'2'
            PUTC
            call L3
            ret
L3:         mvi a,'3'
            PUTC
            call L4
            ret
L4:         mvi a,'4'
            PUTC
            call L5
            ret
L5:         mvi a,'5'
            PUTC
            call L6
            ret
L6:         mvi a,'6'
            PUTC
            call L7
            ret
L7:         mvi a,'7'
            PUTC
            call L8              ; the 8th CALL - SP wraps 7->0 here
            ret
L8:         mvi a,'8'
            PUTC
            ret                  ; stack reg 0 freezes pointing at WRAP

; WRAP landing pad: the final RET of the unwind resumes here (address
; just past L8's RET) because the wrapped 8th CALL replaced the
; return-to-START context with L8's own PC register.
WRAP:       mvi a,' '
            PUTC
            mvi a,'W'
            PUTC
            mvi a,'R'
            PUTC
            mvi a,'A'
            PUTC
            mvi a,'P'
            PUTC
            mvi a,' '
            PUTC
            mvi a,'O'
            PUTC
            mvi a,'K'
            PUTC
            mvi a,CR
            PUTC
            mvi a,LF
            PUTC
            jmp 0                ; back to the monitor

            end 2100H
