#!/usr/bin/env python3
"""Build a synthetic 24 KB 'tempest.rom' that exercises the hardware paths the
real game uses, for simulation only (no Atari code involved).

Program (at $D000, reached through the $F000 mirror's reset vector):
  - init POKEYs and start a tone
  - set colour RAM entries 1 (yellow) and 2 (green)
  - write a display list to vector RAM: CNTR, SCAL, STAT, coloured VCTRs,
    then JMP 0 (Tempest's endless loop)
  - EAROM: write $5A to cell 5, read it back into $13
  - start the AVG, enable IRQ; the IRQ handler acks via $5000 and counts in $00
  - main loop copies POKEY1 ALLPOT, IN0, POKEY2 ALLPOT into $10, $11, $12
"""
import sys

code = []
labels = {}
fix = []
ORG = 0xD000

def b(*xs): code.extend(xs)
def lda_i(v): b(0xA9, v)
def sta(a): b(0x8D, a & 0xFF, a >> 8)
def lda(a): b(0xAD, a & 0xFF, a >> 8)
def sta_z(z): b(0x85, z)
def here(): return ORG + len(code)

b(0x78, 0xD8, 0xA2, 0xFF, 0x9A)            # SEI CLD LDX #$FF TXS
lda_i(0x03); sta(0x60CF); sta(0x60DF)      # SKCTL both POKEYs
lda_i(0x40); sta(0x60C0)                   # AUDF1
lda_i(0xAF); sta(0x60C1)                   # AUDC1 pure tone, volume 15
lda_i(0x04); sta(0x0801)                   # colour 1: R+G (yellow)
lda_i(0x06); sta(0x0802)                   # colour 2: G (green)

words = [0x8000,            # CNTR
         0x7000,            # SCAL 0
         0x60F0,            # STAT intensity 15
         0x6801,            # STAT colour 1
         0x0000, 0xE064,    # VCTR dy=0, dx=+100, z=7
         0x6802,            # STAT colour 2
         0x0064, 0xE000,    # VCTR dy=+100, dx=0, z=7
         0xE000]            # JMP 0
for i, w in enumerate(words):
    lda_i(w & 0xFF);  sta(0x2000 + 2*i)
    lda_i(w >> 8);    sta(0x2000 + 2*i + 1)

lda_i(0x5A); sta(0x6005)                   # EAROM addr 5, data $5A
lda_i(0x0C); sta(0x6040)                   # select, write mode
lda_i(0x09); sta(0x6040)                   # read mode, CK high
lda_i(0x08); sta(0x6040)                   # CK falls -> latch
lda(0x6050); sta_z(0x13)

sta(0x4800)                                # VG GO
b(0x58)                                    # CLI
loop = here()
lda(0x60C8); sta_z(0x10)
lda(0x0C00); sta_z(0x11)
lda(0x60D8); sta_z(0x12)
b(0x4C, loop & 0xFF, loop >> 8)
irq = here()
b(0x48)                                    # PHA
sta(0x5000)                                # ack
b(0xE6, 0x00, 0x68, 0x40)                  # INC $00, PLA, RTI

rom = bytearray(0x6000)
rom[0x4000:0x4000 + len(code)] = bytes(code)
# vectors at $FFFA (file 0x4FFA, mirrored from D000-DFFF)
for off, tgt in ((0xFFA, irq), (0xFFC, ORG), (0xFFE, irq)):
    rom[0x4000 + off] = tgt & 0xFF
    rom[0x4000 + off + 1] = tgt >> 8
open(sys.argv[1], 'wb').write(rom)
print(f"code {len(code)} bytes, loop at {loop:04X}, irq at {irq:04X}")
