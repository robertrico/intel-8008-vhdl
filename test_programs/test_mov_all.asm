; test_mov_all.asm
; Comprehensive MOV instruction test suite
; Tests MOV A,M instruction under various stress conditions

            cpu 8008new
            org 0000H

start:
            ; Test 1: Basic register MOV (quick sanity check)
            mvi a,55H             ; A = 0x55
            mov b,a               ; B = A (should be 0x55)

test6:
            ; Test 6: Register write hazard after MOV M,A
            mvi h,08H             ; H = 0x08 (address 0x0800)
            mvi l,00H             ; L = 0x00

            ; Pre-set registers to known bad values
            mvi b,0FFH            ; B = 0xFF
            mvi c,0FFH            ; C = 0xFF
            mvi d,0FFH            ; D = 0xFF

            ; Trigger the bug with MOV M,A
            mvi a,99H             ; A = 0x99
            mov m,a               ; Write to memory (may trigger register write lockout)

            ; These should work but may fail if bug exists
            mvi b,11H             ; B should become 0x11
            mvi c,22H             ; C should become 0x22
            mvi d,33H             ; D should become 0x33

            ; Expected: B=0x11, C=0x22, D=0x33
            ; If bug: B=0xFF, C=0xFF, D=0x33 or 0xFF
            hlt                   ; End test here

test7:
            ; Test 7: Sequential memory reads (the bug pattern!)
            mvi h,08H             ; H = 0x08
            mvi l,10H             ; L = 0x10 (address 0x0810)
            mvi a,0AAH
            mov m,a               ; Write 0xAA to 0x0810
            inr l                 ; L = 0x11
            mvi a,0BBH
            mov m,a               ; Write 0xBB to 0x0811
            inr l                 ; L = 0x12
            mvi a,0CCH
            mov m,a               ; Write 0xCC to 0x0812
            inr l                 ; L = 0x13
            mvi a,0DDH
            mov m,a               ; Write 0xDD to 0x0813

            ; Now read them back in sequence
            mvi l,10H             ; Reset to 0x0810
            mov a,m               ; Should read 0xAA
            mov b,a               ; Save to B
            inr l                 ; L = 0x11
            mov a,m               ; Should read 0xBB
            mov c,a               ; Save to C
            inr l                 ; L = 0x12
            mov a,m               ; Should read 0xCC
            mov d,a               ; Save to D
            inr l                 ; L = 0x13
            mov a,m               ; Should read 0xDD
            mov e,a               ; Save to E
            ; Expected: B=0xAA, C=0xBB, D=0xCC, E=0xDD

test8:
            ; Test 8: MOV A,M stress test - rapid consecutive reads
            mvi h,08H             ; H = 0x08
            mvi l,20H             ; L = 0x20 (address 0x0820)
            ; Write test pattern
            mvi a,12H
            mov m,a               ; 0x0820 = 0x12
            inr l
            mvi a,34H
            mov m,a               ; 0x0821 = 0x34
            inr l
            mvi a,56H
            mov m,a               ; 0x0822 = 0x56
            inr l
            mvi a,78H
            mov m,a               ; 0x0823 = 0x78

            ; Rapid consecutive MOV A,M operations
            mvi l,20H
            mov a,m               ; Read 0x12
            mov a,m               ; Read again (still 0x12)
            mov a,m               ; Read again (still 0x12)
            mov b,a               ; B should be 0x12
            inr l
            mov a,m               ; Read 0x34
            mov a,m               ; Read again
            mov c,a               ; C should be 0x34
            ; Expected: B=0x12, C=0x34

test9:
            ; Test 9: MOV A,M with ALU operations
            mvi h,08H
            mvi l,30H             ; Address 0x0830
            mvi a,0FH
            mov m,a               ; Write 0x0F
            mov a,m               ; Read back
            adi 01H               ; A = 0x10
            mov b,a               ; B = 0x10
            mov a,m               ; Read again (should still be 0x0F)
            ; Expected: A=0x0F, B=0x10

test10:
            ; Test 10: MOV A,M alternating with register moves
            mvi h,08H
            mvi l,40H             ; Address 0x0840
            mvi a,0AAH
            mov m,a               ; Write 0xAA
            mov a,m               ; Read 0xAA
            mov b,a               ; B = 0xAA
            mvi a,55H             ; A = 0x55
            mov c,a               ; C = 0x55
            mov a,m               ; Read memory again (should be 0xAA)
            mov d,a               ; D = 0xAA
            ; Expected: B=0xAA, C=0x55, D=0xAA

test11:
            ; Test 11: MOV A,M after increment pattern
            mvi h,08H
            mvi l,50H             ; Address 0x0850
            mvi a,01H
            mov m,a
            inr l
            mvi a,02H
            mov m,a
            inr l
            mvi a,04H
            mov m,a
            inr l
            mvi a,08H
            mov m,a
            ; Read back with increment between
            mvi l,50H
            mov a,m
            mov b,a               ; B = 0x01
            inr l
            mov a,m
            mov c,a               ; C = 0x02
            inr l
            mov a,m
            mov d,a               ; D = 0x04
            inr l
            mov a,m
            mov e,a               ; E = 0x08
            ; Expected: B=0x01, C=0x02, D=0x04, E=0x08

test12:
            ; Test 12: MOV A,M with H,L modifications
            mvi h,08H
            mvi l,60H             ; Address 0x0860
            mvi a,99H
            mov m,a               ; Write 0x99 to 0x0860
            mov a,m               ; Read it back
            mov b,a               ; Save to B
            mvi l,61H             ; Change address
            mvi a,88H
            mov m,a               ; Write 0x88 to 0x0861
            mov a,m               ; Read it back
            mov c,a               ; Save to C
            mvi l,60H             ; Back to first address
            mov a,m               ; Should read 0x99 again
            mov d,a               ; Save to D
            ; Expected: B=0x99, C=0x88, D=0x99
            hlt                   ; All MOV A,M tests complete

            end
