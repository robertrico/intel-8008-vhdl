# SCELBAL on b8008 — Design

Date: 2026-07-03
Status: approved. Phase 1 implements now; Phase 2 outlined for the follow-on
project.

## Goal

SCELBI BASIC (SCELBAL, Wadsworth 1976) running on the b8008 — a live BASIC
prompt served by the FPGA 8008, `10 PRINT "HELLO WORLD"` / `20 GOTO 10` /
`RUN` looping on real silicon. The final VCF post. Source: Jim Loos's
AS-assembler port (`scelbal-in-eprom.asm`, github.com/jim11662418/8008-SBC),
same provenance as the six already-ported samples.

## Source facts (verified)

- 4,222 lines, `cpu 8008` (old mnemonics) body with `8008new` I/O wrappers.
- Code `ORG 2000H` (entry + bitbang serial shims at 0x2000-0x20FF,
  interpreter 0x2100-~0x3CFF).
- Variable pages via clean EQUs — 261 references, no hardcoded page loads:
  `OLDPG1=0x0000, OLDPG26=0x0100, OLDPG27=0x0200, OLDPG57=0x0300`.
- User program buffer: `BGNPGRAM=0x04`..`ENDPGRAM=0x20` (page numbers).
- Boot copies three ROM init images into variable pages: `page1@ORG 3D00H`,
  `page26@3E00H`, `page27@3F00H` (keyword table — extensible; the SCELBAL
  book documents adding statements).

## Phase 1 — RAM-resident under b8008_monitor (implement now)

The monitor board is the proven testing ground; SCELBAL becomes its seventh
and largest loadable program.

**Memory map change (the "more RAM" step):**
- `address_decoder` generics: ROM 0x0000-0x0FFF (4K claim — firmware is
  1.5K, rom_4kx8_bram already 4K), RAM 0x1000-0x3FFF (12K, `ram_sync`
  ADDR_BITS stays 8K? -> grows to cover 0x1000-0x3FFF: 12K BRAM).
- Everything existing keeps working: samples ORG 0x2000+, monitor scratch
  0x3F00, RST slots, trampoline — untouched.

**SCELBAL port (`test_programs/samples/scelbal_ram.asm`):**
- Variable EQUs: OLDPG1=0x1000, OLDPG26=0x1100, OLDPG27=0x1200,
  OLDPG57=0x1300.
- Program buffer: BGNPGRAM=0x14, ENDPGRAM=0x20 (user BASIC 0x1400-0x1FFF,
  3KB — more than a stock SCELBI 8B).
- I/O shims replace the 2400-bps bitbang block: IN 1 poll (rlc/jnc/rrc,
  register-transparent), OUT 9 with straight-line pacing, per
  docs/RAM_PROGRAMS.md. Register-contract audit against all callers
  (the pi-cout lesson).
- Init images re-ORG'd clear of monitor scratch: page1@0x3C00,
  page26@0x3D00, page27@0x3E00 (confirm code ends below 0x3C00; adjust
  down if not — plan pins exact addresses from the .lst).
- Exit/no-exit: SCELBAL has no exit; monitor reachable by reset. (MON
  statement is Phase 2.)

**Validation ladder:**
1. Emulator oracle (scratchpad emu8008, 16K flat): scripted session —
   banner, `SCR`, `10 PRINT "HELLO WORLD"`, `20 GOTO 10`, `LIST`, `RUN`,
   looping output. Also arithmetic smoke: `PRINT 2+2`, `PRINT 355/113`.
2. Sim: monitor boot TB on the 12K-RAM build (regression, not SCELBAL —
   loading 8K over sim UART is impractical; the emulator is the SCELBAL
   oracle, silicon is the proof).
3. Full regression suite 28/28 + cycle counts on the new decoder map.
4. Silicon: `send_hex.py scelbal_ram.hex` (~2 min, period-appropriate),
   `G 2000`, run the scripted session live.

## Phase 2 — b8008_basic: boot-to-BASIC, Apple-style (outline)

New project `projects/b8008_basic`, same RTL, inverted decoder map:
- RAM 0x0000-0x0FFF: page 0 = RST vectors + BRAM-init boot `JMP` +
  monitor scratch (nothing SCELBAL-writable — reset always works);
  0x0100-0x0BFF user BASIC programs; 0x0C00-0x0FFF variable pages.
- ROM 0x1000-0x3FFF: monitor reassembled at 0x1000, SCELBAL reassembled
  at 0x1800+ (10K of room), init images inline.
- Power-on: bootstrap jam RST 0 -> RAM[0] `JMP` -> BASIC banner.
- New `MON` keyword in the page27 keyword table -> monitor entry (our
  CALL -151). Monitor `G <warm>` re-enters SCELBAL preserving the program
  buffer (our 3D0G) — variables reset, `LIST`/`RUN` survive.
- RST vectors writable in RAM directly — period-authentic, forwarding
  slots retire in this personality.

Phase 2 gets its own spec/plan after Phase 1 is silicon-proven.

## Risks

- Hidden page-zero idioms surviving jsl's relocation (calc-FININP class):
  mitigated by the emulator oracle running full sessions before silicon,
  and by jsl having already relocated these pages once on real hardware.
- 12K RAM BRAM growth: trivial for the ECP5-45F, but timing re-verified
  by the standard build greps.
- SCELBAL bugs vs CPU bugs: any failure goes through the oracle first —
  emulator and RTL diverging means CPU; both failing identically means
  port.
