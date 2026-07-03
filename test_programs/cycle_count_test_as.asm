; Intel 8008 Cycle-Count Test Program
; For AS Macro Assembler
;
; Purpose: one instruction from every timing class, executed linearly,
; so check_cycle_count_test.sh can count T-states per instruction from
; the simulation STATE log and diff against docs/isa.json
; (num_states_execution - the line-by-line ISA_CYCLES mapping).
;
; Flag choreography is deliberate: conditionals execute in KNOWN
; taken/not-taken variants so expected counts are exact.
;
; No checkpoints - the measurement IS the assertion. Ends in HLT.

        cpu     8008new
        page    0

        org     0000h
STARTUP:
        JMP     MAIN            ; JMP (11) - counted like any other

; RST 1 vector: minimal returning handler
        org     0008h
RST1V:
        RET                     ; RET (5)

        org     0100h
MAIN:
        ; --- memory pointer setup + immediate/memory classes ---
        MVI     H,20h           ; LrI (8)
        MVI     L,00h           ; LrI (8)
        MVI     M,5Ah           ; LMI (9)
        MOV     A,M             ; LrM (8)
        MOV     B,A             ; Lrr (5)
        MOV     M,B             ; LMr (7)

        ; --- single-cycle ALU classes ---
        INR     B               ; INr (5)
        DCR     B               ; DCr (5)
        ADD     B               ; ALU r (5)
        ADD     M               ; ALU M (8)
        ADI     01h             ; ALU I (8)

        ; --- rotates ---
        RLC                     ; (5)
        RRC                     ; (5)
        RAL                     ; (5)
        RAR                     ; (5)

        ; --- conditionals with known outcomes ---
        XRA     A               ; ALU r (5), clears carry
        JC      NEVER           ; JTc NOT taken (9)
        JNC     TAK1            ; JFc taken (11)
NEVER:
        HLT                     ; never reached

TAK1:
        CALL    SUB1            ; CAL (11)
        RST     1               ; RST (5) + vector RET (5)
        IN      0               ; INP (8)
        OUT     08h             ; OUT (6)
        HLT                     ; HLT (4)

SUB1:
        RC                      ; RFc NOT taken (3) - carry is clear
        RET                     ; RET (5)

        end
