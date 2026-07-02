            PAGE 0               ; suppress page headings in AS listing file
;===========================================================================
; HLTWAKE - front-panel HLT-wake test
;
; HLT parks the CPU in the STOPPED state. Flipping sw(5) fires one
; debounced interrupt; the monitor jams RST 5 (sw(7) OFF) or RST 7
; (sw(7) ON), which vectors through the monitor's RAM slot to the
; handler below. The handler prints its identity and RETs - the jammed
; RST pushed HLT+1, so execution resumes right after the HLT.
;
; Serial output:   SLEEP        (then CPU is STOPPED - flip sw5)
;                  W5RESUM      (sw7 OFF)   or   W7RESUM  (sw7 ON)
; then jmp 0 back to the monitor prompt.
;
;   make assemble-sample PROG=hltwake_ram
;   ./send_hex.py test_programs/samples/hltwake_ram.hex   (minicom closed)
;   then in minicom:  G 2100
;===========================================================================

            cpu 8008new
CR          EQU 0Dh
LF          EQU 0Ah

            ORG 2100H
START:      mvi h,3Fh            ; monitor RST slot page
            mvi l,0E8h           ; RST 5 slot = 0x3FC0 + 5*8
            mvi m,44h            ; JMP opcode
            inr l
            mvi m,H5 & 0FFh
            inr l
            mvi m,H5 / 100h
            mvi l,0F8h           ; RST 7 slot = 0x3FC0 + 7*8
            mvi m,44h
            inr l
            mvi m,H7 & 0FFh
            inr l
            mvi m,H7 / 100h

            mvi a,'S'
            call PUTC
            mvi a,'L'
            call PUTC
            mvi a,'E'
            call PUTC
            mvi a,'E'
            call PUTC
            mvi a,'P'
            call PUTC
            hlt                  ; <- CPU STOPPED; flip sw(5) to wake
            mvi a,'R'            ; handler RET resumes HERE (HLT+1)
            call PUTC
            mvi a,'E'
            call PUTC
            mvi a,'S'
            call PUTC
            mvi a,'U'
            call PUTC
            mvi a,'M'
            call PUTC
            mvi a,CR
            call PUTC
            mvi a,LF
            call PUTC
            jmp 0                ; back to the monitor

H5:         mvi a,'W'
            call PUTC
            mvi a,'5'
            call PUTC
            ret                  ; return address = HLT+1

H7:         mvi a,'W'
            call PUTC
            mvi a,'7'
            call PUTC
            ret

; send the char in A; straight-line pacing (~45us/instr vs 87us frame)
PUTC:       out 09h
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            ret

            end 2100H
