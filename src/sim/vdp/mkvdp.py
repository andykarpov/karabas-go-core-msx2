#!/usr/bin/env python3
"""Test cartridges for the VDP of the MSX2 core (the ESE-VDP, rtl/msx/vdp): 16 KB ROMs for slot 1,
assembled with sjasmplus, started by C-BIOS (sim_sys --cbios --fast-logo).

g4.rom, g6.rom, g7.rom, yjk.rom set a bitmap mode with the VDP registers alone (no BIOS), with the
interrupts off, then draw with the command engine (waiting for CE in S#2 after each command):
  - HMMV: the whole page (212 lines) with one byte;
  - HMMV: eight vertical bands, a byte each (the table of the mode);
  - LINE: from the top left to the bottom right and from the top right to the bottom left;
  - LMMV with XOR: a box in the middle.
  g4 = SCREEN 5 (GRAPHIC 4, 256 x 212, 4 bits), g6 = SCREEN 7 (GRAPHIC 6, 512 x 212, 4 bits: the
  VRAM of the two banks interleaved), g7 = SCREEN 8 (GRAPHIC 7, 256 x 212, 8 bits), yjk = SCREEN 12
  (GRAPHIC 7 with R25 YJK: the V9958). The picture stays; sim_sys takes the CRC of a frame (vdp.txt).

text80.rom: SCREEN 0 with 80 columns through the BIOS (LINL40 = 80, CHGMOD 0) and lines of text
with CHPUT (TEXT 2).

usage: mkvdp.py OUTDIR
"""
import os
import subprocess
import sys

SJASM = os.environ.get('SJASMPLUS', '/opt/sjasmplus/sjasmplus')

HEAD = """
	org	0x4000
	db	"AB"
	dw	start
	ds	12, 0
"""

COMMON = """
; VDP register B = A
wreg:	out	(0x99), a
	ld	a, b
	or	0x80
	out	(0x99), a
	ret

; the command: 11 bytes at HL to R36..R46 (indirect, auto increment), then wait for CE
cmd:	ld	a, 36
	ld	b, 17
	call	wreg
	ld	bc, 0x0B9B
	otir
wait:	ld	a, 2
	ld	b, 15
	call	wreg
	in	a, (0x99)
	ld	c, a
	xor	a
	ld	b, 15
	call	wreg
	bit	0, c
	jr	nz, wait
	ret
"""


def bitmap(r0, r25, width, fill, bands, c1, c2, cx):
    """the program of a bitmap test: R0 of the mode, R25, width in pixels, the bytes and colours"""
    w = width
    band = w // 8
    lines = []
    lines.append(HEAD)
    lines.append("""start:	di
	ld	sp, 0xF380
	ld	hl, regs
	ld	b, 0
""")
    lines.append("""setr:	ld	a, (hl)
	cp	0xFF
	jr	z, draw
	inc	hl
	ld	b, a
	ld	a, (hl)
	inc	hl
	call	wreg
	jr	setr
draw:	ld	hl, c_fill
	call	cmd
""")
    for i in range(8):
        lines.append("\tld\thl, c_band%d\n\tcall\tcmd\n" % i)
    lines.append("""	ld	hl, c_line1
	call	cmd
	ld	hl, c_line2
	call	cmd
	ld	hl, c_box
	call	cmd
stop:	jr	stop
""")
    lines.append(COMMON)
    # register, value pairs, FF ends: the mode, display on, sprites off, 212 lines, 60 Hz, border 4
    lines.append("regs:\tdb\t0, 0x%02X, 1, 0x40, 2, 0x1F, 7, 0x04, 8, 0x0A, 9, 0x80, 25, 0x%02X, 23, 0, 0xFF\n"
                 % (r0, r25))

    def hmmv(name, x, y, nx, ny, clr):
        return "%s:\tdw\t%d, %d, %d, %d\n\tdb\t0x%02X, 0, 0xC0\n" % (name, x, y, nx, ny, clr)

    lines.append(hmmv('c_fill', 0, 0, w, 212, fill))
    for i in range(8):
        lines.append(hmmv('c_band%d' % i, i * band, 20, band, 172, bands[i]))
    # LINE: DX, DY, the long side (NX), the short side (NY), the colour, ARG (DIX bit 2: left), LINE
    lines.append("c_line1:\tdw\t0, 0, %d, 211\n\tdb\t0x%02X, 0x00, 0x70\n" % (w - 1, c1))
    lines.append("c_line2:\tdw\t%d, 0, %d, 211\n\tdb\t0x%02X, 0x04, 0x70\n" % (w - 1, w - 1, c2))
    # LMMV with XOR (logical operation 3)
    lines.append("c_box:\tdw\t%d, 70, %d, 72\n\tdb\t0x%02X, 0, 0x83\n" % (w // 4, w // 2, cx))
    return ''.join(lines)


TEXT80 = HEAD + """
CHPUT	equ	0x00A2
CHGMOD	equ	0x005F
LINL40	equ	0xF3AE
start:	ld	sp, 0xF380
	ld	a, 80
	ld	(LINL40), a
	xor	a
	call	CHGMOD
	ld	b, 6
again:	push	bc
	ld	hl, text
pr:	ld	a, (hl)
	or	a
	jr	z, done
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	pr
done:	pop	bc
	djnz	again
stop:	jr	stop
text:	db	"0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ abcdefghijklmnopqrstuvwxyz !@#$%^&*()-=+[]", 13, 10, 0
"""

TESTS = (
    # name, R0, R25, width, fill byte, band bytes, line colours, xor colour
    ('g4', 0x06, 0x00, 256, 0x44, (0x00, 0x11, 0x22, 0x33, 0x88, 0x99, 0xAA, 0xFF), 0x0F, 0x08, 0x0F),
    ('g6', 0x0A, 0x00, 512, 0x44, (0x00, 0x11, 0x22, 0x33, 0x88, 0x99, 0xAA, 0xFF), 0x0F, 0x08, 0x0F),
    ('g7', 0x0E, 0x00, 256, 0x25, (0x00, 0x03, 0x1C, 0xE0, 0x1F, 0xE3, 0xFC, 0xFF), 0xFF, 0x1C, 0xFF),
    ('yjk', 0x0E, 0x08, 256, 0x80, (0x07, 0x37, 0x67, 0x97, 0xC7, 0xF7, 0x3F, 0xF8), 0xF8, 0x38, 0xFF),
)


def build(out, name, text):
    src = os.path.join(out, name + '.asm')
    raw = os.path.join(out, name + '.bin')
    open(src, 'w').write(text)
    subprocess.run([SJASM, '--nologo', '--raw=' + raw, src], check=True, stdout=subprocess.DEVNULL)
    code = open(raw, 'rb').read()
    assert len(code) <= 0x4000
    open(os.path.join(out, name + '.rom'), 'wb').write(code + b'\xFF' * (0x4000 - len(code)))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for t in TESTS:
        build(out, t[0], bitmap(*t[1:]))
    build(out, 'text80', TEXT80)


if __name__ == '__main__':
    main()
