            PAGE 0               ; suppress page headings in AS listing file
;===========================================================================
; INTSTORM - runtime-interrupt storm test
;
; The main loop prints an incrementing hex counter forever. Each sw(5)
; flip fires one interrupt mid-execution; the handler prints '!' and
; RETs. An unbroken counter sequence with '!' interleaved proves full
; register/PC preservation across jammed RSTs. Works with either
; vector: both RST 5 and RST 7 slots point at the handler.
;
; Serial output:   00 01 02 03 !04 05 ...      (mash sw5!)
; Any typed character exits to the monitor (jmp 0).
;
; The handler clobbers only what it saves: A goes to RAM 0x2000
; (the 8008 has no push), H/L are reloaded by the main loop before
; every use. B (the counter) and D/E are never touched.
;
;   make assemble-sample PROG=intstorm_ram
;   ./send_hex.py test_programs/samples/intstorm_ram.hex   (minicom closed)
;   then in minicom:  G 2100
;===========================================================================

            cpu 8008new

            ORG 2100H
START:      mvi h,3Fh            ; monitor RST slot page
            mvi l,0E8h           ; RST 5 slot
            mvi m,44h            ; JMP opcode
            inr l
            mvi m,BANG & 0FFh
            inr l
            mvi m,BANG / 100h
            mvi l,0F8h           ; RST 7 slot
            mvi m,44h
            inr l
            mvi m,BANG & 0FFh
            inr l
            mvi m,BANG / 100h
            mvi b,0              ; the counter

LOOP:       in 1                 ; any typed char = exit
            rlc                  ; ready flag into carry
            jc DONE
            mov a,b              ; high nibble
            rrc
            rrc
            rrc
            rrc
            call NIB
            mov a,b              ; low nibble
            call NIB
            mvi a,' '
            call PUTC
            inr b
            mvi c,0FFh           ; ~0.2 s pause so the stream is readable
PAUSE:      mvi d,0FFh
P2:         dcr d
            jnz P2
            dcr c
            jnz PAUSE
            jmp LOOP

DONE:       jmp 0                ; back to the monitor

; print low nibble of A as a hex digit
NIB:        ani 0Fh
            adi '0'
            cpi '9'+1            ; digits 0-9: A < '9'+1 sets carry
            jc PUTC              ; tail call for 0-9
            adi 7                ; adjust A-F
PUTC:       out 09h              ; straight-line pacing (~45us/instr)
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            ret

; interrupt handler: preserve A (in RAM - no push on the 8008) and print '!'
; H and L are clobbered; the main loop never holds live state in them.
BANG:       mvi h,20h            ; scratch at 0x2000 (program is at 0x21xx)
            mvi l,00h
            mov m,a              ; save A
            mvi a,'!'
            out 09h
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,a
            mov a,m              ; restore A
            ret

            end 2100H
