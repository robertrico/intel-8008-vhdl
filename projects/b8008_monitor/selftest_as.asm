; ================================================================================
; SELFTEST - Intel 8008 hardware ISA self-test ROM
; ================================================================================
; Runs the regression-suite coverage ON SILICON, reporting per-test results
; over the UART (OUT 9, 115200 8N1) instead of the simulation checkpoint port.
;
; Output:
;   SELFTEST
;   T01 P
;   T02 P
;   ...
;   DN P=xx F=yy      (hex counts; F=00 means the ISA is proven on hardware)
;
; Coverage: ADD/ADC/SUB/SBB/ANA/XRA/ORA/CMP (register), ADI/ACI/SUI/SBI/ANI/
; XRI/ORI/CPI (immediate), ALU-on-M, MVI M / MOV A,M, INR/DCR incl. wrap and
; zero, RLC/RRC/RAL/RAR incl. carry behaviour, JM/JP/JPE/JPO, conditional
; CALL and RET (taken and not taken), register MOV chain, 6-deep call
; nesting, RAM pattern write/readback, UART RX status read.
;
; Test numbers are assigned automatically in execution order (TESTNUM in RAM).
; Build:  make rom-freeze ASM=selftest_as.asm && make build   (first time)
;         make rom-update ASM=selftest_as.asm                 (afterwards)
; ================================================================================

        cpu 8008new
        org 0000h

rst0_vector:
        jmp main

CR      equ 0Dh
LF      equ 0Ah

; RAM usage (RAM at 0x2000-0x23FF)
TESTNUM equ 2300h               ; current test number (incremented per test)
PASSCNT equ 2301h               ; tests passed
FAILCNT equ 2302h               ; tests failed
SCRATCH equ 2310h               ; memory-operand test location

main:
        mvi a,0
        mvi b,0
        mvi c,0
        mvi d,0
        mvi e,0
        mvi h,0
        mvi l,0

        ; LED0 on: alive
        mvi a,0FEh
        out 8

        ; Zero the counters
        mvi h,23h
        mvi l,00h
        mvi m,0                 ; TESTNUM
        inr l
        mvi m,0                 ; PASSCNT
        inr l
        mvi m,0                 ; FAILCNT

        ; Banner "SELFTEST" + CRLF
        mvi a,'S'
        out 9
        call char_delay
        mvi a,'E'
        out 9
        call char_delay
        mvi a,'L'
        out 9
        call char_delay
        mvi a,'F'
        out 9
        call char_delay
        mvi a,'T'
        out 9
        call char_delay
        mvi a,'E'
        out 9
        call char_delay
        mvi a,'S'
        out 9
        call char_delay
        mvi a,'T'
        out 9
        call char_delay
        call send_crlf

; ================================================================================
; Group A: ALU register operations
; ================================================================================

        ; T01: ADD - 5 + 3 = 8
        mvi a,05h
        mvi b,03h
        add b
        mvi e,08h
        call check_a

        ; T02: ADC with carry set - 5 + 8 + 1 = 0x0E
        mvi a,0FFh
        adi 01h                 ; sets carry, A=0
        mvi a,05h
        mvi b,08h
        adc b
        mvi e,0Eh
        call check_a

        ; T03: SUB - 5 - 3 = 2
        mvi a,05h
        mvi b,03h
        sub b
        mvi e,02h
        call check_a

        ; T04: SBB with borrow set - 0x10 - 2 - 1 = 0x0D
        mvi a,00h
        sui 01h                 ; sets borrow, A=0xFF
        mvi a,10h
        mvi b,02h
        sbb b
        mvi e,0Dh
        call check_a

        ; T05: ANA - 0x05 AND 0x03 = 0x01
        mvi a,05h
        mvi b,03h
        ana b
        mvi e,01h
        call check_a

        ; T06: XRA - 0x05 XOR 0x03 = 0x06
        mvi a,05h
        mvi b,03h
        xra b
        mvi e,06h
        call check_a

        ; T07: ORA - 0x05 OR 0x03 = 0x07
        mvi a,05h
        mvi b,03h
        ora b
        mvi e,07h
        call check_a

        ; T08: CMP equal sets Z (A preserved)
        mvi a,07h
        mvi b,07h
        cmp b
        jz t08p
        call report_fail
        jmp t09
t08p:   call report_pass

        ; T09: CMP less sets carry (3 < 7)
t09:    mvi a,03h
        mvi b,07h
        cmp b
        jc t09p
        call report_fail
        jmp t10
t09p:   call report_pass

; ================================================================================
; Group B: ALU immediate operations
; ================================================================================

        ; T10: ADI - 0x0A + 5 = 0x0F
t10:    mvi a,0Ah
        adi 05h
        mvi e,0Fh
        call check_a

        ; T11: ACI with carry - 5 + 8 + 1 = 0x0E
        mvi a,0FFh
        adi 01h                 ; carry set
        mvi a,05h
        aci 08h
        mvi e,0Eh
        call check_a

        ; T12: SUI - 0x0F - 5 = 0x0A
        mvi a,0Fh
        sui 05h
        mvi e,0Ah
        call check_a

        ; T13: SBI with borrow - 0x10 - 2 - 1 = 0x0D
        mvi a,00h
        sui 01h                 ; borrow set
        mvi a,10h
        sbi 02h
        mvi e,0Dh
        call check_a

        ; T14: ANI - 0x3C AND 0x0F = 0x0C
        mvi a,3Ch
        ani 0Fh
        mvi e,0Ch
        call check_a

        ; T15: XRI - 0xFA XOR 0xFF = 0x05
        mvi a,0FAh
        xri 0FFh
        mvi e,05h
        call check_a

        ; T16: ORI - 0x0A OR 0xF0 = 0xFA
        mvi a,0Ah
        ori 0F0h
        mvi e,0FAh
        call check_a

        ; T17: CPI equal sets Z
        mvi a,42h
        cpi 42h
        jz t17p
        call report_fail
        jmp t18
t17p:   call report_pass

; ================================================================================
; Group C: ALU on memory operand (M = [HL])
; ================================================================================

        ; T18: ADD M - 0x22 + [0x2310]=0x11 = 0x33
t18:    mvi h,23h
        mvi l,10h               ; SCRATCH
        mvi m,11h
        mvi a,22h
        add m
        mvi e,33h
        call check_a

        ; T19: ANA M - 0x33 AND 0x11 = 0x11
        mvi h,23h
        mvi l,10h
        mvi a,33h
        ana m
        mvi e,11h
        call check_a

        ; T20: MVI M / MOV A,M round trip - 0x5A
        mvi h,23h
        mvi l,10h
        mvi m,5Ah
        mov a,m
        mvi e,5Ah
        call check_a

; ================================================================================
; Group D: INR / DCR
; ================================================================================

        ; T21: INR - 0x0F + 1 = 0x10
        mvi b,0Fh
        inr b
        mov a,b
        mvi e,10h
        call check_a

        ; T22: INR wrap 0xFF -> 0x00 sets Z
        mvi b,0FFh
        inr b
        jz t22p
        call report_fail
        jmp t23
t22p:   call report_pass

        ; T23: DCR - 0x10 - 1 = 0x0F
t23:    mvi c,10h
        dcr c
        mov a,c
        mvi e,0Fh
        call check_a

        ; T24: DCR to zero sets Z
        mvi c,01h
        dcr c
        jz t24p
        call report_fail
        jmp t25
t24p:   call report_pass

; ================================================================================
; Group E: Rotates
; ================================================================================

        ; T25: RLC - 0x81 -> 0x03
t25:    mvi a,81h
        rlc
        mvi e,03h
        call check_a

        ; T26: RLC carry out of bit 7
        mvi a,81h
        rlc
        jc t26p
        call report_fail
        jmp t27
t26p:   call report_pass

        ; T27: RRC - 0x81 -> 0xC0
t27:    mvi a,81h
        rrc
        mvi e,0C0h
        call check_a

        ; T28: RRC carry out of bit 0
        mvi a,81h
        rrc
        jc t28p
        call report_fail
        jmp t29
t28p:   call report_pass

        ; T29: RAL with carry in - carry=1, 0x40 -> 0x81
t29:    mvi a,0FFh
        adi 01h                 ; carry set
        mvi a,40h
        ral
        mvi e,81h
        call check_a

        ; T30: RAR with carry in - carry=1, 0x02 -> 0x81
        mvi a,0FFh
        adi 01h                 ; carry set
        mvi a,02h
        rar
        mvi e,81h
        call check_a

; ================================================================================
; Group F: Sign / parity conditional jumps
; ================================================================================

        ; T31: JM taken on negative
        mvi a,80h
        ora a
        jm t31p
        call report_fail
        jmp t32
t31p:   call report_pass

        ; T32: JP taken on positive
t32:    mvi a,10h
        ora a
        jp t32p
        call report_fail
        jmp t33
t32p:   call report_pass

        ; T33: JPE taken on even parity (0x03: two bits)
t33:    mvi a,03h
        ora a
        jpe t33p
        call report_fail
        jmp t34
t33p:   call report_pass

        ; T34: JPO taken on odd parity (0x07: three bits)
t34:    mvi a,07h
        ora a
        jpo t34p
        call report_fail
        jmp t35
t34p:   call report_pass

; ================================================================================
; Group G: Conditional CALL / RET
; ================================================================================

        ; T35: CZ taken - probe sets D=0xAA
t35:    mvi d,00h
        xra a                   ; A=0, Z set
        cz probe_d_aa
        mov a,d
        mvi e,0AAh
        call check_a

        ; T36: CZ not taken - D stays 0
        mvi d,00h
        mvi a,01h
        ora a                   ; Z clear
        cz probe_d_aa
        mov a,d
        mvi e,00h
        call check_a

        ; T37: RZ - probe returns early, D=0x55 survives
        call probe_rz
        mov a,d
        mvi e,55h
        call check_a

        ; T38: RC - probe returns early on carry, D=0x66 survives
        call probe_rc
        mov a,d
        mvi e,66h
        call check_a

; ================================================================================
; Group H: MOV chain and stack depth
; ================================================================================

        ; T39: MOV chain A->B->C->D->E->A preserves 0x5A
        mvi a,5Ah
        mov b,a
        mov c,b
        mov d,c
        mov e,d
        mov a,e
        mvi e,5Ah
        call check_a

        ; T40: 6-deep nested CALL/RET - deepest level sets D=0x77
        mvi d,00h
        call nest1
        mov a,d
        mvi e,77h
        call check_a

; ================================================================================
; Group I: RAM pattern and I/O status
; ================================================================================

        ; T41: RAM walk - write i*0x11 at 0x2310+i (i=0..7), verify sum
        ; 00+11+22+...+77 = 0x11*28 = 0x1DC -> 0xDC truncated to 8 bits
        mvi h,23h
        mvi l,10h
        mvi d,00h
t41w:   mov m,d
        mov a,d
        adi 11h
        mov d,a
        mov a,l
        adi 1
        mov l,a
        cpi 18h
        jnz t41w
        ; read back and sum
        mvi l,10h
        mvi d,00h               ; running sum
t41r:   mov a,m
        add d
        mov d,a
        mov a,l
        adi 1
        mov l,a
        cpi 18h
        jnz t41r
        mov a,d
        mvi e,0DCh
        call check_a

        ; T42: UART RX status - no pending char, bit 7 clear
        in 1
        ani 80h
        jz t42p
        call report_fail
        jmp done
t42p:   call report_pass

; ================================================================================
; Group J: Rotate flag preservation + carry across INR/DCR
; (regressions for the two silent ALU-fidelity bug classes found via
;  period software: rotates must write carry ONLY, INR/DCR must not
;  touch carry at all)
; ================================================================================

        ; T43: RLC preserves Z (set via XRA), updates C
        xra a                   ; Z=1 C=0
        mvi a,80h
        rlc                     ; A=01h C=1; Z must stay 1
        mvi a,00h
        jnz t43d                ; Z clobbered -> fail (A stays 0)
        jnc t43d                ; C not set -> fail
        mvi a,55h
t43d:   mvi e,55h
        call check_a

        ; T44: RAR preserves Z=1 and S=0 from prior ADD carry-out
        mvi a,0FFh
        adi 01h                 ; A=0: Z=1 S=0 C=1
        mvi a,01h
        rar                     ; A=80h C=1; Z/S must hold
        mvi a,00h
        jnz t44d
        jm  t44d
        mvi a,55h
t44d:   mvi e,55h
        call check_a

        ; T45: carry survives INR (SCELBAL ADC/INR interleave idiom)
        mvi a,0FFh
        adi 01h                 ; C=1
        mvi l,10h
        inr l                   ; must NOT touch C
        mvi a,00h
        jnc t45d
        mvi a,55h
t45d:   mvi e,55h
        call check_a

        ; T46: carry survives DCR (RAL/DCR rotate-loop idiom)
        xra a                   ; C=0
        mvi a,80h
        ral                     ; C=1
        mvi b,05h
        dcr b                   ; must NOT touch C
        mvi a,00h
        jnc t46d
        mvi a,55h
t46d:   mvi e,55h
        call check_a

; ================================================================================
; Summary: "DN P=xx F=yy"
; ================================================================================
done:
        call send_crlf
        mvi a,'D'
        out 9
        call char_delay
        mvi a,'N'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'P'
        out 9
        call char_delay
        mvi a,'='
        out 9
        call char_delay
        mvi h,23h
        mvi l,01h               ; PASSCNT
        mov a,m
        call send_hex_byte
        mvi a,' '
        out 9
        call char_delay
        mvi a,'F'
        out 9
        call char_delay
        mvi a,'='
        out 9
        call char_delay
        mvi h,23h
        mvi l,02h               ; FAILCNT
        mov a,m
        call send_hex_byte
        call send_crlf

idle:   jmp idle

; ================================================================================
; Probes for conditional call/return tests
; ================================================================================
probe_d_aa:
        mvi d,0AAh
        ret

probe_rz:
        mvi d,55h
        xra a                   ; Z set
        rz                      ; must return here
        mvi d,00h               ; only reached if RZ broken
        ret

probe_rc:
        mvi d,66h
        mvi a,0FFh
        adi 01h                 ; carry set
        rc                      ; must return here
        mvi d,00h               ; only reached if RC broken
        ret

nest1:  call nest2
        ret
nest2:  call nest3
        ret
nest3:  call nest4
        ret
nest4:  call nest5
        ret
nest5:  call nest6
        ret
nest6:  mvi d,77h
        ret

; ================================================================================
; CHECK_A - Compare A against expected value in E, report the result
; ================================================================================
; Input:  A = actual, E = expected
; Destroys: A, B, C, H, L
;
check_a:
        xra e                   ; zero iff equal
        jz check_a_pass
        jmp report_fail         ; tail call - its RET returns to the test
check_a_pass:
        jmp report_pass         ; tail call

; ================================================================================
; REPORT_PASS / REPORT_FAIL - Print "Tnn P" / "Tnn F" and count
; ================================================================================
; Destroy: A, B, C, H, L
;
report_pass:
        call print_tnum
        mvi a,'P'
        out 9
        call char_delay
        mvi h,23h
        mvi l,01h               ; PASSCNT
        mov a,m
        adi 1
        mov m,a
        jmp send_crlf           ; tail call

report_fail:
        call print_tnum
        mvi a,'F'
        out 9
        call char_delay
        mvi h,23h
        mvi l,02h               ; FAILCNT
        mov a,m
        adi 1
        mov m,a
        jmp send_crlf           ; tail call

; PRINT_TNUM - Increment TESTNUM, print "Tnn "
print_tnum:
        mvi h,23h
        mvi l,00h               ; TESTNUM
        mov a,m
        adi 1
        mov m,a
        mvi a,'T'
        out 9
        call char_delay
        mvi h,23h
        mvi l,00h
        mov a,m
        call send_hex_byte
        mvi a,' '
        out 9
        call char_delay
        ret

; ================================================================================
; SEND_HEX_BYTE - Print A as two hex digits (byte parked in C; char_delay eats B)
; ================================================================================
send_hex_byte:
        mov c,a
        rlc
        rlc
        rlc
        rlc
        ani 0Fh
        call send_hex_nibble
        mov a,c
        ani 0Fh
        call send_hex_nibble
        ret

send_hex_nibble:
        cpi 10
        jc shn_digit
        adi 'A'-10
        jmp shn_out
shn_digit:
        adi '0'
shn_out:
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
; CHAR_DELAY - UART pacing (same as monitor firmware)
; ================================================================================
char_delay:
        mvi b,20
char_delay_loop:
        dcr b
        jnz char_delay_loop
        ret
