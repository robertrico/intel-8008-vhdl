; ================================================================================
; ROM_DIAG - ROM/RAM read-path diagnostic for b8008 monitor hardware debug
; ================================================================================
; No UART RX, no command parsing. On boot, repeatedly:
;   1. Print "DIAG" banner
;   2. Hex-dump the CPU's own view of ROM 0x0000-0x00FF (this program's code)
;   3. Print "RAM" then hex-dump RAM 0x2000-0x200F (pre-write contents)
;   4. Write pattern 00 11 22 ... FF to 0x2000-0x200F, dump readback
;   5. Delay ~1s, repeat forever
;
; Compare the ROM dump against rom_diag.bin: any mismatch = corruption in the
; EEPROM read path (address/data bus, level shifters, sampling). Differences
; between iterations = unstable reads. RAM readback errors = internal BRAM path.
;
; Expected RAM readback: 00 11 22 33 44 55 66 77 88 99 AA BB CC DD EE FF
;
; UART: 115200 8N1 on OUT 9, same as monitor firmware.
; ================================================================================

        cpu 8008new
        org 0000h

rst0_vector:
        jmp main

CR      equ     0Dh
LF      equ     0Ah

main:
        mvi a,0
        mvi b,0
        mvi c,0
        mvi d,0
        mvi e,0
        mvi h,0
        mvi l,0

        ; LED0 on to show life
        mvi a,0FEh
        out 8

diag_pass:
        ; Banner: "DIAG" + CRLF
        mvi a,'D'
        out 9
        call char_delay
        mvi a,'I'
        out 9
        call char_delay
        mvi a,'A'
        out 9
        call char_delay
        mvi a,'G'
        out 9
        call char_delay
        call send_crlf

        ; ------------------------------------------------------------
        ; ROM dump: 0x0000 - 0x00FF, 16 bytes per row
        ; ------------------------------------------------------------
        mvi h,00h
        mvi l,00h
rom_dump_loop:
        mov a,m                 ; Read ROM byte (CPU's view)
        call print_hex_byte
        mvi a,' '
        out 9
        call char_delay

        ; Advance pointer
        mov a,l
        adi 1
        mov l,a
        jz rom_dump_done        ; Wrapped 0xFF -> 0x00: 256 bytes done

        ; Row break every 16 bytes
        ani 0Fh
        jnz rom_dump_loop
        call send_crlf
        jmp rom_dump_loop

rom_dump_done:
        call send_crlf

        ; ------------------------------------------------------------
        ; RAM pre-write dump: "RAM" + CRLF, then 0x2000 - 0x200F
        ; ------------------------------------------------------------
        mvi a,'R'
        out 9
        call char_delay
        mvi a,'A'
        out 9
        call char_delay
        mvi a,'M'
        out 9
        call char_delay
        call send_crlf

        mvi h,20h
        mvi l,00h
ram_pre_loop:
        mov a,m
        call print_hex_byte
        mvi a,' '
        out 9
        call char_delay
        mov a,l
        adi 1
        mov l,a
        cpi 10h
        jnz ram_pre_loop
        call send_crlf

        ; ------------------------------------------------------------
        ; RAM write pattern: 0x2000+i = i*0x11
        ; ------------------------------------------------------------
        mvi h,20h
        mvi l,00h
        mvi d,00h
ram_write_loop:
        mov m,d
        mov a,d
        adi 11h
        mov d,a
        mov a,l
        adi 1
        mov l,a
        cpi 10h
        jnz ram_write_loop

        ; ------------------------------------------------------------
        ; RAM readback dump
        ; ------------------------------------------------------------
        mvi h,20h
        mvi l,00h
ram_read_loop:
        mov a,m
        call print_hex_byte
        mvi a,' '
        out 9
        call char_delay
        mov a,l
        adi 1
        mov l,a
        cpi 10h
        jnz ram_read_loop
        call send_crlf
        call send_crlf

        ; ~1s pause, then repeat
        call delay_long
        call delay_long
        call delay_long
        jmp diag_pass

; ================================================================================
; PRINT_HEX_BYTE - Print A as two hex digits
; ================================================================================
; Destroys: A, B (via char_delay), E
;
print_hex_byte:
        mov e,a                 ; Save byte (char_delay destroys B)
        rrc
        rrc
        rrc
        rrc
        ani 0Fh
        call print_nibble
        mov a,e
        ani 0Fh
        call print_nibble
        ret

print_nibble:
        cpi 0Ah
        jc pn_digit
        adi 37h                 ; 10-15 -> 'A'-'F'
        jmp pn_send
pn_digit:
        adi 30h                 ; 0-9 -> '0'-'9'
pn_send:
        out 9
        call char_delay
        ret

; ================================================================================
; SEND_CRLF
; ================================================================================
send_crlf:
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay
        ret

; ================================================================================
; CHAR_DELAY - Same pacing as monitor firmware (proven on hardware)
; ================================================================================
char_delay:
        mvi b,20
char_delay_loop:
        dcr b
        jnz char_delay_loop
        ret

; ================================================================================
; DELAY_LONG - ~300ms pause between diagnostic passes
; ================================================================================
delay_long:
        mvi d,255
delay_long_outer:
        mvi e,255
delay_long_inner:
        dcr e
        jnz delay_long_inner
        dcr d
        jnz delay_long_outer
        ret
