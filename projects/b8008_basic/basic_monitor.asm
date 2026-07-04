; ================================================================================
; B8008_MONITOR.ASM - Interactive Console for b8008 CPU
; ================================================================================
; Interactive monitor with command processing.
;
; I/O Ports:
;   IN 1:   UART RX - bit 7 = ready flag, bits 6:0 = received data
;           Ready flag clears automatically when CPU reads the port
;   OUT 8:  LED bank (active low, used for status indication)
;   OUT 9:  Direct UART TX - sends byte immediately (115200 baud)
;
; UART Settings:
;   Baud Rate: 115200
;   Format: 8N1 (8 data bits, no parity, 1 stop bit)
;
; Connect FTDI USB-to-serial adapter and open terminal at 115200 baud.
; Local echo should be OFF in terminal (the 8008 will echo characters).
;
; Commands:
;   H          - help menu
;   D addr[,n] - dump memory
;   W addr,val - write byte to memory (readback-verified)
;   L          - load Intel HEX into RAM (paced sender required; ESC ends)
;   G addr     - run from addr (via JMP trampoline in RAM)
;
; Memory map (b8008_basic): RAM 0x0000-0x0FFF, ROM 0x1000-0x3FFF.
; Monitor scratch 0x0040-0x00BF; see projects/b8008_basic/MEMORY_MAP.md.
; ================================================================================

        cpu 8008new
; b8008_basic personality: ROM lives at 0x1000-0x3FFF; page 0 is RAM.
; The BRAM-initialized boot vector at RAM 0x0000 jumps into SCELBAL;
; this monitor is reached via SCELBAL's MON statement (entry 0x1000)
; - and RST 1-7 vectors at 0x0008-0x003F are plain writable RAM, so
; programs install their handlers directly, period-authentic.
        org 1000h
        jmp main                ; MON lands here -> banner + prompt

; ================================================================================
; CONSTANTS
; ================================================================================
CR      equ     0Dh             ; Carriage return
LF      equ     0Ah             ; Line feed
RX_READY equ    80h             ; Bit 7 mask for RX ready flag

; Monitor variables live in the page-0 scratch block (0x0040-0x00BF) so
; that programs loaded with L can use 0x2000-0x3EFF freely.
CMD_LEN equ     0040h           ; Buffer length storage (1 byte)
CMD_BUF equ     0041h           ; Command buffer start (16 bytes: 0x0041-0x0050)
CMD_MAX equ     16              ; Maximum command length

; Dump command variables (RAM)
DUMP_ADDR_H equ 0060h           ; Dump address high byte
DUMP_ADDR_L equ 0061h           ; Dump address low byte
DUMP_COUNT  equ 0062h           ; Dump byte count (1-255, 0 means 1)

; Intel HEX loader variables (RAM)
HEX_CNT     equ 0070h           ; Remaining data bytes in current record
HEX_ADDR_H  equ 0071h           ; Load address high byte
HEX_ADDR_L  equ 0072h           ; Load address low byte
HEX_TYPE    equ 0073h           ; Record type (00=data, 01=EOF)
HEX_SUM     equ 0074h           ; Running checksum (must be 0 after cksum byte)
HEX_ERRS    equ 0075h           ; Error count for the whole transfer

; G command trampoline: "JMP addr" is built here then executed
; (the 8008 has no indirect jump)
TRAMP       equ 00B0h

; RST vector forwarding: RST n calls ROM address n*8, which the monitor
; b8008_basic: RST vectors 0x0008-0x003F are writable RAM - no
; forwarding slots. Programs install "jmp handler" at 8*n directly.
                                ; RST1=3FC8 RST2=3FD0 RST3=3FD8 RST4=3FE0
                                ; RST5=3FE8 RST6=3FF0 RST7=3FF8

; ================================================================================
; MAIN PROGRAM
; ================================================================================
main:
	mvi a,0
	mvi b,0
	mvi c,0
	mvi d,0
	mvi e,0
	mvi h,0
	mvi l,0

        ; Turn on LED0 to show we're starting
        mvi a,0FEh              ; LED0 on (active low)
        out 8

        ; Initialize command buffer length to 0
        call clear_buffer

        ; Small startup delay
        call delay_short

        ; Send the banner then prompt
        call send_banner
        call send_prompt


        ; Fall through to echo loop

; ================================================================================
; COMMAND_LOOP - Main command loop
; ================================================================================
; Waits for a character from UART, buffers it, and echoes back.
; Commands are parsed only when Enter is pressed.
;
command_loop:

        ; Poll UART RX for incoming character
        call uart_rx_wait       ; Returns received char in A

        ; Save character in C (used by add_to_buffer)
        mov c,a

        ; Check for Enter key (CR)
        cpi CR
        jz handle_enter

        ; Check for Enter key (LF - some terminals send this)
        cpi LF
        jz handle_enter

        ; Backspace (Ctrl-H) or DEL: remove last buffered character
        cpi 08h
        jz handle_backspace
        cpi 7Fh
        jz handle_backspace

        ; Ignore all other control characters (< 0x20)
        cpi 20h
        jc command_loop

        ; Regular character - add to buffer
        call add_to_buffer      ; C = char

	mvi a,0FEh
	out 8

        ; Echo the character back
        mov a,c
        out 9
        call char_delay

        jmp command_loop

; ================================================================================
; HANDLE_BACKSPACE - Remove last character from buffer, erase it on terminal
; ================================================================================
handle_backspace:
        ; Ignore if the buffer is empty
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_LEN&0FFh               ; CMD_LEN
        mov a,m
        ora a
        jz command_loop

        ; Decrement buffer length
        sui 1
        mov m,a

        ; Erase on terminal: BS, space, BS
        mvi a,08h
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,08h
        out 9
        call char_delay

        jmp command_loop

; ================================================================================
; HANDLE_ENTER - Handle Enter key (new line + new prompt)
; ================================================================================
handle_enter:
	call delay_tiny

        ; Send CR+LF before running command
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; Parse and execute command in buffer
        call parse_command

        ; Clear buffer for next command
        call clear_buffer

        ; Send CR+LF
        mvi a,CR
        out 9
        call char_delay

        mvi a,LF
        out 9
        call char_delay

        ; Reprint the prompt
        call send_prompt

        jmp command_loop

; ================================================================================
; UART_RX_WAIT - Wait for and receive a character from UART
; ================================================================================
; Polls IN 1 until bit 7 (ready flag) is set, then returns the received
; character in the accumulator (bits 6:0).
; The ready flag is automatically cleared when IN 1 is executed.
;
; Returns: A = received character (7-bit ASCII)
; Destroys: A, B
;
uart_rx_wait:
        in 1                    ; Read UART status/data (clears ready flag)
        mov b,a                 ; Save the full byte (flag + data)
        ani RX_READY            ; Check bit 7 (ready flag)
        jz uart_rx_wait         ; Not ready, keep polling

        ; Ready flag was set - data is in B, extract the character
        mov a,b                 ; Restore the byte
        ani 7Fh                 ; Mask off bit 7 to get 7-bit ASCII
        ret

; ================================================================================
; SEND_BANNER - Send "8008 Monitor" + CR/LF
; ================================================================================
send_banner:
        mvi a,'8'
        out 9
        call char_delay

        mvi a,'0'
        out 9
        call char_delay

        mvi a,'0'
        out 9
        call char_delay

        mvi a,'8'
        out 9
        call char_delay

        mvi a,' '
        out 9
        call char_delay

        mvi a,'M'
        out 9
        call char_delay

        mvi a,'o'
        out 9
        call char_delay

        mvi a,'n'
        out 9
        call char_delay

        mvi a,'i'
        out 9
        call char_delay

        mvi a,'t'
        out 9
        call char_delay

        mvi a,'o'
        out 9
        call char_delay

        mvi a,'r'
        out 9
        call char_delay

        mvi a,CR
        out 9
        call char_delay

        mvi a,LF
        out 9
        call char_delay

        ret

; ================================================================================
; SEND_PROMPT - Send "> "
; ================================================================================
send_prompt:
        mvi a,'>'
        out 9
        call char_delay

        mvi a,' '
        out 9
        call char_delay

        ret

; ================================================================================
; SEND_HELP - Send help menu
; ================================================================================
send_help:
        ; "Help Menu" + CR/LF
        mvi a,'H'
        out 9
        call char_delay
        mvi a,'e'
        out 9
        call char_delay
        mvi a,'l'
        out 9
        call char_delay
        mvi a,'p'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'M'
        out 9
        call char_delay
        mvi a,'e'
        out 9
        call char_delay
        mvi a,'n'
        out 9
        call char_delay
        mvi a,'u'
        out 9
        call char_delay
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; "  H: Show Help" + CR/LF
        mvi a,' '
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'H'
        out 9
        call char_delay
        mvi a,':'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'S'
        out 9
        call char_delay
        mvi a,'h'
        out 9
        call char_delay
        mvi a,'o'
        out 9
        call char_delay
        mvi a,'w'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'H'
        out 9
        call char_delay
        mvi a,'e'
        out 9
        call char_delay
        mvi a,'l'
        out 9
        call char_delay
        mvi a,'p'
        out 9
        call char_delay
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; "  D addr[,n]: Dump" + CR/LF
        mvi a,' '
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'D'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'a'
        out 9
        call char_delay
        mvi a,'d'
        out 9
        call char_delay
        mvi a,'d'
        out 9
        call char_delay
        mvi a,'r'
        out 9
        call char_delay
        mvi a,'['
        out 9
        call char_delay
        mvi a,','
        out 9
        call char_delay
        mvi a,'n'
        out 9
        call char_delay
        mvi a,']'
        out 9
        call char_delay
        mvi a,':'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'D'
        out 9
        call char_delay
        mvi a,'u'
        out 9
        call char_delay
        mvi a,'m'
        out 9
        call char_delay
        mvi a,'p'
        out 9
        call char_delay
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; "  W addr,val: Write" + CR/LF
        mvi a,' '
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'W'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'a'
        out 9
        call char_delay
        mvi a,'d'
        out 9
        call char_delay
        mvi a,'d'
        out 9
        call char_delay
        mvi a,'r'
        out 9
        call char_delay
        mvi a,','
        out 9
        call char_delay
        mvi a,'v'
        out 9
        call char_delay
        mvi a,'a'
        out 9
        call char_delay
        mvi a,'l'
        out 9
        call char_delay
        mvi a,':'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay
        mvi a,'W'
        out 9
        call char_delay
        mvi a,'r'
        out 9
        call char_delay
        mvi a,'i'
        out 9
        call char_delay
        mvi a,'t'
        out 9
        call char_delay
        mvi a,'e'
        out 9
        call char_delay
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        ; "  L: Load HEX" / "  G addr: Go" lines (new commands use strings)
        mvi h,(msg_help_lg>>8)&0FFh
        mvi l,msg_help_lg&0FFh
        call send_string

        ret

; ================================================================================
; CLEAR_BUFFER - Reset command buffer length to 0
; ================================================================================
; Destroys: A, H, L
;
clear_buffer:
        mvi h,(CMD_LEN>>8)&0FFh               ; CMD_LEN high byte
        mvi l,CMD_LEN&0FFh               ; CMD_LEN low byte
        mvi m,0                 ; Store 0 to buffer length
        ret

; ================================================================================
; ADD_TO_BUFFER - Add character to command buffer
; ================================================================================
; Input:  C = character to add
; Output: B = 1 if added successfully, 0 if buffer full
; Destroys: A, B, D, H, L
;
add_to_buffer:
        ; Load current buffer length
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_LEN&0FFh               ; Point to CMD_LEN (0x1000)
        mov a,m                 ; A = current length

        ; Check if buffer is full
        cpi CMD_MAX             ; Compare with max (16)
        jnc buffer_full         ; Jump if length >= 16

        ; Calculate target address: CMD_BUF + length (symbolic - the
        ; hardcoded "adi 01h" only worked while CMD_BUF ended in 01)
        mov d,a                 ; Save length in D
        adi CMD_BUF&0FFh        ; A = CMD_BUF low byte + length
        mov l,a                 ; HL = CMD_BUF + length

        ; Store the character
        mov m,c                 ; Store character at buffer[length]

        ; Increment and save new length
        mvi l,CMD_LEN&0FFh               ; Point back to CMD_LEN (0x1000)
        mov a,d                 ; Get saved length
        adi 1                   ; Increment
        mov m,a                 ; Store new length

        mvi b,1                 ; Return success
        ret

buffer_full:
        mvi b,0                 ; Return failure
        ret

; ================================================================================
; PARSE_COMMAND - Parse and execute command in buffer
; ================================================================================
; Checks the first character in the buffer and dispatches to the appropriate
; command handler.
;
; Commands:
;   H or h - Show help menu
;   D addr[,n] - Dump memory
;   W addr,val - Write byte to memory (readback-verified)
;
; Destroys: A, H, L
;
parse_command:
        ; Empty buffer: nothing to parse (avoids dispatching on stale bytes)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_LEN&0FFh               ; CMD_LEN
        mov a,m
        ora a
        rz

        ; Point HL to first character in buffer (CMD_BUF = 0x2001)
        mvi l,CMD_BUF&0FFh
        mov a,m                 ; Load first character

        ; Check for 'H'
        cpi 'H'
        jz cmd_help

        ; Check for 'h'
        cpi 'h'
        jz cmd_help

        ; Check for 'D'
        cpi 'D'
        jz cmd_dump

        ; Check for 'd'
        cpi 'd'
        jz cmd_dump

        ; Check for 'W'
        cpi 'W'
        jz cmd_write

        ; Check for 'w'
        cpi 'w'
        jz cmd_write

        ; Check for 'L'
        cpi 'L'
        jz cmd_load

        ; Check for 'l'
        cpi 'l'
        jz cmd_load

        ; Check for 'G'
        cpi 'G'
        jz cmd_go

        ; Check for 'g'
        cpi 'g'
        jz cmd_go

        ; Unknown command - just return
        ret

cmd_help:
        call send_help
        ret

; ================================================================================
; CMD_DUMP - Dump memory contents
; ================================================================================
; Format: D addr[,count]
;   D 1000     - dumps single byte at 0x1000
;   D 1000,4   - dumps 4 bytes starting at 0x1000
;
; Output format: ADDR - XX [XX XX ...]
;
cmd_dump:
        ; Parse the address and count from buffer
        call parse_dump_args    ; Sets DUMP_ADDR_H/L and DUMP_COUNT

        ; Get count (0 means 1)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_COUNT&0FFh               ; DUMP_COUNT
        mov a,m
        ora a                   ; Check if zero
        jnz dump_loop_start
        mvi a,1                 ; Default to 1 if zero
        mov m,a

dump_loop_start:
        ; Load address into DE (we'll use HL for memory access)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_ADDR_H&0FFh               ; DUMP_ADDR_H
        mov d,m                 ; D = high byte
        inr l
        mov e,m                 ; E = low byte

        ; Send address
        mov a,d
        call send_hex_byte
        mov a,e
        call send_hex_byte

        ; Send " - "
        mvi a,' '
        out 9
        call char_delay
        mvi a,'-'
        out 9
        call char_delay
        mvi a,' '
        out 9
        call char_delay

dump_loop:
        ; Read byte at address DE
        mov h,d
        mov l,e
        mov a,m                 ; A = byte at [HL]

        ; Send as hex
        call send_hex_byte

        ; Decrement count
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_COUNT&0FFh               ; DUMP_COUNT
        mov a,m
        sui 1                   ; Decrement (8008 has no DCR A)
        mov m,a
        jz dump_done            ; Count reached zero

        ; Increment address in DE
        inr e
        jnz dump_no_carry
        inr d
dump_no_carry:

        ; Send space between bytes
        mvi a,' '
        out 9
        call char_delay

        jmp dump_loop

dump_done:
        ret

; ================================================================================
; CMD_WRITE - Write a byte to memory
; ================================================================================
; Format: W addr,val   (both hex, e.g. "W 2030,AA")
;
; Reuses parse_dump_args: address lands in DUMP_ADDR_H/L, value in DUMP_COUNT.
; After storing, tail-jumps into the dump printer with count=1 so the response
; line ("ADDR - VV") is a genuine readback of the written location.
;
cmd_write:
        call parse_dump_args    ; DUMP_ADDR_H/L = target, DUMP_COUNT = value

        ; Fetch value then target, store (no calls in between - B stays live)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_COUNT&0FFh               ; DUMP_COUNT holds the value byte
        mov b,m
        mvi l,DUMP_ADDR_H&0FFh               ; DUMP_ADDR_H
        mov d,m
        inr l                   ; DUMP_ADDR_L
        mov e,m
        mov h,d
        mov l,e
        mov m,b                 ; Write the byte

        ; Readback verify: print "ADDR - VV" via the dump path
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_COUNT&0FFh
        mvi m,1                 ; DUMP_COUNT = 1
        jmp dump_loop_start

; ================================================================================
; CMD_GO - Jump to an address
; ================================================================================
; Format: G addr   (hex, e.g. "G 2000")
;
; The 8008 has no indirect jump, so build "JMP addr" at TRAMP (0x3F80) in RAM
; and jump to it. Reuses parse_dump_args: the target lands in DUMP_ADDR_H/L.
; No return - the loaded program owns the CPU (jmp 0 restarts the monitor).
;
cmd_go:
        call parse_dump_args    ; DUMP_ADDR_H/L = target address

        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_ADDR_H&0FFh               ; DUMP_ADDR_H
        mov d,m                 ; D = target high
        inr l
        mov e,m                 ; E = target low

        mvi l,TRAMP&0FFh               ; TRAMP (0x3F80)
        mvi m,44h               ; JMP opcode
        inr l
        mov m,e                 ; target low byte
        inr l
        mov m,d                 ; target high byte

        jmp TRAMP               ; execute the trampoline

; ================================================================================
; CMD_LOAD - Load Intel HEX records from the UART into memory
; ================================================================================
; Streams records directly from the UART (the 16-byte command buffer is far
; too small for a HEX line). Characters outside records are ignored, so CR/LF
; between records is fine. ESC ends the transfer at any point between records.
;
; Record: ":llaaaatt<data>cc" - ll count, aaaa address, tt type, cc checksum.
;   type 00 = data (stored at aaaa), type 01 = EOF, others consumed + ignored.
; Running sum of all record bytes including cc must be 0 (mod 256); a bad
; checksum or a bad hex digit counts an error and resyncs at the next ':'.
; Prints '.' per good data record, '?' per bad record, then OK or ERR n.
;
; The sender must pace characters (~2 ms apart): the 8008 polls the USART
; and cannot take back-to-back characters at 115200 baud. Use send_hex.py.
;
; Destroys: A, B, C, D, E, H, L
;
cmd_load:
        ; Clear the error counter
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,HEX_ERRS&0FFh               ; HEX_ERRS
        mvi m,0

        ; Announce load mode
        mvi h,(msg_load>>8)&0FFh
        mvi l,msg_load&0FFh
        call send_string

hexload_rec:
        call uart_rx_wait       ; A = next character
        cpi 1Bh                 ; ESC ends the transfer
        jz hexload_end
        cpi ':'
        jnz hexload_rec         ; ignore everything between records

        ; Start of record: clear the running checksum
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,HEX_SUM&0FFh               ; HEX_SUM
        mvi m,0

        call get_hex_byte       ; byte count (get_hex_byte leaves H=3Fh)
        mvi l,HEX_CNT&0FFh               ; HEX_CNT
        mov m,a
        call get_hex_byte       ; address high byte
        mvi l,HEX_ADDR_H&0FFh               ; HEX_ADDR_H
        mov m,a
        call get_hex_byte       ; address low byte
        mvi l,HEX_ADDR_L&0FFh               ; HEX_ADDR_L
        mov m,a
        call get_hex_byte       ; record type
        mvi l,HEX_TYPE&0FFh               ; HEX_TYPE
        mov m,a

hexload_data:
        mvi l,HEX_CNT&0FFh               ; HEX_CNT
        mov a,m
        ora a
        jz hexload_cksum        ; all data bytes consumed
        sui 1
        mov m,a

        call get_hex_byte       ; data byte in A and C

        ; Only record type 00 stores to memory; others are consumed
        mvi l,HEX_TYPE&0FFh               ; HEX_TYPE
        mov a,m
        ora a
        jnz hexload_data

        ; Store C at [HEX_ADDR] and increment the address
        mvi l,HEX_ADDR_H&0FFh               ; HEX_ADDR_H
        mov d,m
        inr l
        mov e,m
        mov h,d
        mov l,e
        mov m,c                 ; write the byte
        inr e
        jnz hexload_stadr
        inr d
hexload_stadr:
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,HEX_ADDR_H&0FFh               ; HEX_ADDR_H
        mov m,d
        inr l
        mov m,e
        jmp hexload_data

hexload_cksum:
        call get_hex_byte       ; checksum byte folds into HEX_SUM
        mvi l,HEX_SUM&0FFh               ; HEX_SUM (H=3Fh after get_hex_byte)
        mov a,m
        ora a
        jz hexload_ckok

        ; Bad checksum: count it, mark it, resync at next ':'
        mvi l,HEX_ERRS&0FFh               ; HEX_ERRS
        mov a,m
        adi 1
        mov m,a
        mvi a,'?'
        out 9
        call char_delay
        jmp hexload_rec

hexload_ckok:
        mvi l,HEX_TYPE&0FFh               ; HEX_TYPE
        mov a,m
        cpi 1
        jz hexload_end          ; EOF record - done

        mvi a,'.'               ; progress marker per good record
        out 9
        call char_delay
        jmp hexload_rec

hexload_end:
        ; CR/LF then verdict
        mvi a,CR
        out 9
        call char_delay
        mvi a,LF
        out 9
        call char_delay

        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,HEX_ERRS&0FFh               ; HEX_ERRS
        mov a,m
        ora a
        jnz hexload_err_report

        mvi h,(msg_ok>>8)&0FFh
        mvi l,msg_ok&0FFh
        call send_string
        ret

hexload_err_report:
        mvi h,(msg_err>>8)&0FFh
        mvi l,msg_err&0FFh
        call send_string
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,HEX_ERRS&0FFh               ; HEX_ERRS
        mov a,m
        call send_hex_byte
        ret

; Invalid hex digit inside a record: count the error and resync at the
; next ':'. Jumped to from inside get_hex_byte - the abandoned return
; address is harmless (the 8008 stack is a ring; only relative depth counts).
hexload_badchar:
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,HEX_ERRS&0FFh               ; HEX_ERRS
        mov a,m
        adi 1
        mov m,a
        jmp hexload_rec

; ================================================================================
; GET_HEX_BYTE - Read two hex characters from the UART as one byte
; ================================================================================
; Returns: A = C = byte value; byte also added to HEX_SUM; H=3Fh, L=34h
; Invalid hex digit: abandons the call frame and resyncs (hexload_badchar)
; Destroys: A, B, C, H, L
;
get_hex_byte:
        call uart_rx_wait       ; A = first character
        call hex_char_to_nibble
        jc hexload_badchar
        rlc
        rlc
        rlc
        rlc
        ani 0F0h
        mov c,a                 ; C = high nibble in position

        call uart_rx_wait       ; A = second character
        call hex_char_to_nibble
        jc hexload_badchar
        ora c                   ; A = full byte
        mov c,a                 ; keep a copy in C

        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,HEX_SUM&0FFh               ; HEX_SUM
        add m
        mov m,a                 ; HEX_SUM += byte
        mov a,c                 ; return byte in A
        ret

; ================================================================================
; PARSE_DUMP_ARGS - Parse address and optional count from command buffer
; ================================================================================
; Buffer format: "D addr" or "D addr,count"
; Sets DUMP_ADDR_H, DUMP_ADDR_L, DUMP_COUNT
;
; Destroys: A, B, C, D, E, H, L
;
parse_dump_args:
        ; Initialize count to 1
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_COUNT&0FFh               ; DUMP_COUNT
        mvi m,1

        ; Initialize address to 0
        mvi l,DUMP_ADDR_H&0FFh               ; DUMP_ADDR_H
        mvi m,0
        inr l
        mvi m,0                 ; DUMP_ADDR_L = 0

        ; Start at buffer position 2 (skip 'D' and space)
        ; Buffer index in E
        mvi e,2                 ; Start after "D "

parse_addr_loop:
        ; Check buffer bounds first (compare E with CMD_LEN)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_LEN&0FFh               ; CMD_LEN at 0x1000
        mov a,m                 ; A = buffer length
        mov b,a                 ; Save length in B
        mov a,e
        cmp b                   ; Compare index with length
        jnc parse_addr_done     ; Index >= length, stop

        ; Get character at CMD_BUF + E
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_BUF&0FFh               ; CMD_BUF base
        mov a,e
        add l
        mov l,a                 ; HL = CMD_BUF + E

        mov a,m                 ; A = character

        ; Check for comma (end of address, start of count)
        cpi ','
        jz parse_count_start

        ; Check for null/end (spaces count as end too)
        cpi ' '
        jz parse_addr_done
        cpi 0
        jz parse_addr_done

        ; Convert hex char to nibble
        call hex_char_to_nibble ; A = nibble value (0-15), carry set if invalid
        jc parse_addr_done      ; Invalid char, stop parsing

        ; Shift address left 4 bits and add new nibble
        ; DUMP_ADDR = (DUMP_ADDR << 4) | nibble
        mov c,a                 ; Save nibble in C

        ; Load current address into D (high) and A (low)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_ADDR_H&0FFh
        mov d,m                 ; D = high byte
        inr l
        mov a,m                 ; A = low byte

        ; Shift left 4 bits: move high nibble of low byte to low nibble of high byte
        ; D = (D << 4) | (A >> 4)
        ; A = (A << 4) | nibble

        mov b,a                 ; Save low byte in B

        ; Shift A left 4 (lose high nibble)
        rlc
        rlc
        rlc
        rlc
        ani 0F0h                ; Keep only shifted bits
        ora c                   ; Add new nibble
        mov c,a                 ; Save new low byte in C

        ; Get high nibble of old low byte
        mov a,b
        rlc
        rlc
        rlc
        rlc
        ani 0Fh                 ; Keep only high nibble (now in low position)
        mov b,a                 ; B = high nibble of old low byte

        ; Shift D left 4 and add B
        mov a,d
        rlc
        rlc
        rlc
        rlc
        ani 0F0h
        ora b                   ; Add carry from low byte
        mov d,a                 ; D = new high byte

        ; Store back
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_ADDR_H&0FFh
        mov m,d                 ; Store high byte
        inr l
        mov m,c                 ; Store low byte

        ; Next character
        inr e
        jmp parse_addr_loop

parse_addr_done:
        ret

parse_count_start:
        ; Skip the comma
        inr e

        ; Initialize count to 0 (we'll build it up)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_COUNT&0FFh
        mvi m,0

        ; Skip any spaces after comma
parse_count_skip_spaces:
        ; Check buffer bounds first (compare E with CMD_LEN)
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_LEN&0FFh               ; CMD_LEN at 0x1000
        mov a,m                 ; A = buffer length
        mov b,a                 ; Save length in B
        mov a,e
        cmp b                   ; Compare index with length
        jnc parse_count_done    ; Index >= length, stop

        ; Get character at CMD_BUF + E
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_BUF&0FFh
        mov a,e
        add l
        mov l,a
        mov a,m                 ; A = character

        ; Skip spaces
        cpi ' '
        jnz parse_count_loop_entry
        inr e
        jmp parse_count_skip_spaces

parse_count_loop:
        ; Check buffer bounds first
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_LEN&0FFh               ; CMD_LEN
        mov a,m
        mov b,a
        mov a,e
        cmp b
        jnc parse_count_done    ; Index >= length, stop

        ; Get character at CMD_BUF + E
        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,CMD_BUF&0FFh
        mov a,e
        add l
        mov l,a

        mov a,m                 ; A = character

parse_count_loop_entry:
        ; Check for end
        cpi ' '
        jz parse_count_done
        cpi 0
        jz parse_count_done

        ; Convert hex char to nibble
        call hex_char_to_nibble
        jc parse_count_done     ; Invalid char, stop

        ; count = (count << 4) | nibble
        mov c,a                 ; Save nibble in C

        mvi h,(CMD_LEN>>8)&0FFh
        mvi l,DUMP_COUNT&0FFh
        mov a,m                 ; A = current count

        ; Shift left 4
        rlc
        rlc
        rlc
        rlc
        ani 0F0h
        ora c                   ; Add new nibble

        mov m,a                 ; Store back

        inr e
        jmp parse_count_loop

parse_count_done:
        ret

; ================================================================================
; HEX_CHAR_TO_NIBBLE - Convert hex ASCII character to nibble value
; ================================================================================
; Input:  A = ASCII character ('0'-'9', 'A'-'F', 'a'-'f')
; Output: A = nibble value (0-15), carry clear
;         If invalid, carry set
;
; Destroys: A
;
hex_char_to_nibble:
        ; Check for '0'-'9'
        cpi '0'
        jc hex_invalid          ; Below '0'
        cpi '9'+1
        jc hex_digit            ; '0'-'9'

        ; Check for 'A'-'F'
        cpi 'A'
        jc hex_invalid          ; Between '9' and 'A'
        cpi 'F'+1
        jc hex_upper            ; 'A'-'F'

        ; Check for 'a'-'f'
        cpi 'a'
        jc hex_invalid          ; Between 'F' and 'a'
        cpi 'f'+1
        jc hex_lower            ; 'a'-'f'

        ; Above 'f'
hex_invalid:
        ; Set carry to indicate error (8008 has no STC)
        mvi a,0
        sui 1                   ; 0 - 1 sets carry
        ret

hex_digit:
        sui '0'                 ; Convert '0'-'9' to 0-9
        ora a                   ; Clear carry
        ret

hex_upper:
        sui 'A'-10              ; Convert 'A'-'F' to 10-15
        ora a                   ; Clear carry
        ret

hex_lower:
        sui 'a'-10              ; Convert 'a'-'f' to 10-15
        ora a                   ; Clear carry
        ret

; ================================================================================
; SEND_HEX_BYTE - Send a byte as two hex digits
; ================================================================================
; Input:  A = byte to send
; Destroys: A, B
;
send_hex_byte:
        mov c,a                 ; Save byte in C (char_delay destroys B!)

        ; Send high nibble
        rlc
        rlc
        rlc
        rlc
        ani 0Fh
        call send_hex_nibble

        ; Send low nibble
        mov a,c
        ani 0Fh
        call send_hex_nibble

        ret

; ================================================================================
; SEND_HEX_NIBBLE - Send a nibble as one hex digit
; ================================================================================
; Input:  A = nibble (0-15)
; Destroys: A
;
send_hex_nibble:
        cpi 10
        jc nibble_digit         ; 0-9
        ; 10-15: convert to 'A'-'F'
        adi 'A'-10
        jmp nibble_out
nibble_digit:
        adi '0'                 ; 0-9 to '0'-'9'
nibble_out:
        out 9
        call char_delay
        ret

; ================================================================================
; SEND_STRING - Send a NUL-terminated string from ROM
; ================================================================================
; Input:  HL = string address
; Destroys: A, B, H, L  (B via char_delay)
;
send_string:
        mov a,m
        ora a
        rz                      ; NUL terminator - done
        out 9
        call char_delay
        inr l
        jnz send_string
        inr h                   ; carry into high byte at page boundary
        jmp send_string

; ================================================================================
; CHAR_DELAY - Small delay between characters
; ================================================================================
; At 115200 baud, each character takes ~87us to transmit.
; The 8008 runs at ~455kHz, so each instruction cycle is ~2.2us.
; A short delay ensures the UART TX buffer is ready for next byte.
;
char_delay:
        mvi b,20                ; ~100 instruction cycles
char_delay_loop:
        dcr b
        jnz char_delay_loop
        ret

; ================================================================================
; DELAY_TINY - Very short delay for LED blink
; ================================================================================
delay_tiny:
        mvi b,10
delay_tiny_loop:
        dcr b
        jnz delay_tiny_loop
        ret

; ================================================================================
; DELAY_SHORT - Short delay (~50ms)
; ================================================================================
delay_short:
        mvi b,100
delay_short_outer:
        mvi c,40
delay_short_inner:
        dcr c
        jnz delay_short_inner
        dcr b
        jnz delay_short_outer
        ret

; ================================================================================
; STRINGS (NUL-terminated, sent with send_string)
; ================================================================================
msg_load:
        db 'SEND HEX (ESC ends)',CR,LF,0
msg_ok:
        db 'OK',0
msg_err:
        db 'ERR ',0
msg_help_lg:
        db '  L: Load HEX',CR,LF,'  G addr: Go',CR,LF,0

        end
