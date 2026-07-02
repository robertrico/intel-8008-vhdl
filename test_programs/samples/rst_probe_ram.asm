; RST forwarding probe - RAM build for the b8008 monitor
; For AS Macro Assembler
;
; Smallest possible test of the monitor's RST vector forwarding:
;   1. Install "JMP HANDLER" in the RST 7 RAM slot (0x3FF8)
;   2. Execute RST 7 - ROM 0x0038 forwards to 0x3FF8 - handler prints 'R'
;   3. Handler returns (RST pushes the PC like a CALL)
;   4. Print 'Q' and halt
;
; Expected output: RQ
; Also used as the monitor_load_tb sim payload (loader + RST in one shot).
;
; Load/run:
;   make assemble-sample PROG=rst_probe_ram
;   ./send_hex.py test_programs/samples/rst_probe_ram.hex   (minicom closed)
;   then in minicom:  G 2000

        cpu     8008new
        page    0

OUTPORT  equ    09H             ; monitor USART TX port (OUT 9)
RST7SLOT equ    3FF8h           ; monitor RAM slot for RST 7 (RSTVEC_BASE+7*8)

        org     2000h
START:
        ; Install "JMP HANDLER" in the RST 7 slot
        MVI     H,(RST7SLOT>>8)&0FFH
        MVI     L,RST7SLOT&0FFH
        MVI     M,44H           ; JMP opcode
        INR     L
        MVI     M,HANDLER&0FFH  ; target low byte
        INR     L
        MVI     M,(HANDLER>>8)&0FFH  ; target high byte

        RST     7               ; ROM 0x0038 -> 0x3FF8 -> HANDLER -> ret

        MVI     A,'Q'
        OUT     OUTPORT
        HLT

HANDLER:
        MVI     A,'R'
        OUT     OUTPORT
        RET

        end
