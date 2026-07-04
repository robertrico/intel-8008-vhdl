#!/usr/bin/env python3
"""Merge basic_monitor.hex + scelbal_rom.hex (0x1000-0x3FFF) into the
rebased 12K ROM image rom_combined.hex / rom_combined.mem (offset 0)."""
rom = bytearray([0x00]*12288)
def load(path):
    for l in open(path):
        if l.startswith(':') and l[7:9]=='00':
            a=int(l[3:7],16); n=int(l[1:3],16)
            for i in range(n):
                assert 0x1000 <= a+i <= 0x3FFF, hex(a+i)
                rom[a+i-0x1000] = int(l[9+2*i:11+2*i],16)
load('basic_monitor.hex'); load('scelbal_rom.hex')
open('rom_combined.mem','w').write('\n'.join(f'{b:02X}' for b in rom)+'\n')
with open('rom_combined.hex','w') as f:
    for base in range(0, 12288, 16):
        rec = bytes([16,(base>>8)&0xFF,base&0xFF,0]) + bytes(rom[base:base+16])
        f.write(':' + rec.hex().upper() + f'{(-sum(rec))&0xFF:02X}\n')
    f.write(':00000001FF\n')
print(f'rom_combined: {sum(1 for b in rom if b)} nonzero bytes of 12288')
