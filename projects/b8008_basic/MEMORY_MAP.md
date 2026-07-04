# b8008_basic — Memory Map (Plan of Record)

Boot-to-BASIC personality. RAM low, ROM high — the inverse of
b8008_monitor. Every EQU in basic_monitor.asm and scelbal_rom.asm
cites this ledger.

## RAM 0x0000-0x0FFF (4K, BRAM)

| Range | Owner | Notes |
|---|---|---|
| 0x0000-0x0002 | boot vector | `JMP SCELBAL_COLD` — BRAM-initialized at config; NOTHING may write here (reset re-jam depends on it) |
| 0x0003-0x0007 | reserved | zeros |
| 0x0008-0x003F | RST 1-7 vectors | writable RAM — programs install `JMP handler` directly, period-authentic; no forwarding slots in this personality |
| 0x0040-0x00BF | monitor scratch | CMD_LEN 0x0040, CMD_BUF 0x0041-0x0050, DUMP vars 0x0060-0x0062, HEX loader vars 0x0070-0x0075, trampoline 0x00B0-0x00B2 |
| 0x00C0-0x00FF | reserved | |
| 0x0100-0x0BFF | user BASIC programs | BGNPGRAM=0x01, ENDPGRAM=0x0C (~2.75KB) |
| 0x0C00-0x0FFF | SCELBAL variables | OLDPG1=0x0C00, OLDPG26=0x0D00, OLDPG27=0x0E00, OLDPG57=0x0F00 |

## ROM 0x1000-0x3FFF (12K, BRAM)

| Range | Owner |
|---|---|
| 0x1000-0x17FF | monitor (basic_monitor.asm, ORG 0x1000) — entry 0x1000 = the MON target |
| 0x1800-0x3FFF | SCELBAL (scelbal_rom.asm, ORG 0x1800) — cold entry 0x1800; warm entry `exec` (address from .lst) |

## Invariants

- Page 0 boot vector + scratch sit OUTSIDE every SCELBAL-writable
  region: reset always works, BASIC can never brick the console.
- SCELBAL writes only 0x0100-0x0FFF (programs + vars). The monitor's
  W command can write anywhere in RAM (operator's privilege).
- SW2 remains FPGA reconfiguration: RAM wipe by physics, then the
  boot vector is re-initialized — power-on and SW2 behave identically
  in this personality (both land in BASIC, which is the point).
