; Cylon / Knight Rider LED sweep - RAM build for the b8008 monitor
; For AS Macro Assembler
;
; Port of projects/_legacy_projects/cylon/cylon.asm (the s8008-era ROM demo)
; to a monitor-loadable RAM program, driving the MEMORY-MAPPED LEDs:
;
;   RAM 0x3FFF bit n -> LED n, 1 = on (gateware shadow register). Bit 0 is
;   unused: LED0 (D25) is the CPU-running light. The same byte is plain RAM,
;   so the monitor can drive the LEDs by hand:
;       W 3FFF,FE    all seven on       W 3FFF,00    all off
;       W 3FFF,F0    the four reds      D 3FFF       read back
;
; Any keypress returns to the monitor.
;
; Load/run:
;   make assemble-sample PROG=cylon_ram
;   cd projects/b8008_monitor && make send-hex HEX=cylon_ram.hex GO=2100

        cpu     8008new
        page    0

LEDS    equ     3FFFh           ; memory-mapped LEDs
RXPORT  equ     1               ; USART RX: bit 7 = ready

        org     2100h
START:
        MVI     C,PATTERN&0FFH  ; C = table index (low byte of pointer)
STEP:
        MVI     H,PATTERN>>8
        MOV     L,C
        MOV     A,M             ; fetch pattern byte
        CPI     0FFH            ; end-of-table marker?
        JZ      START
        MVI     H,LEDS>>8
        MVI     L,LEDS&0FFH
        MOV     M,A             ; poke the LEDs
        CALL    DELAY
        IN      RXPORT          ; key pressed? (read clears the ready flag)
        ANI     80H
        JNZ     EXIT
        INR     C
        JMP     STEP
EXIT:
        MVI     H,LEDS>>8
        MVI     L,LEDS&0FFH
        MVI     M,0             ; all off
        JMP     0               ; back to the monitor (banner + prompt)

; ~110 ms at the board's 455 kHz: DCR (5 T) + JNZ taken (11 T) = 16 T-states
; = ~70 us per inner iteration, 40 x 40 iterations. Uses B and D; C holds
; the table index.
DELAY:
        MVI     B,40
DLY1:   MVI     D,40
DLY2:   DCR     D
        JNZ     DLY2
        DCR     B
        JNZ     DLY1
        RET

; One full bounce across the seven user LEDs (bit n = LED n; bit 0 is the
; CPU-running LED D25 and is skipped), 0FFH ends the table.
        org     2180h
PATTERN:
        db      02H,04H,08H,10H,20H,40H,80H
        db      40H,20H,10H,08H,04H
        db      0FFH
