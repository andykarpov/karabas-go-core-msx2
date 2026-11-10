#!/usr/bin/env python3
"""Test cartridges for the mappers of the MSX1 core (rtl/msx/cart): 128 KB ROMs, assembled with
sjasmplus. Each bank of the mapper (8 KB, ASCII 16: 16 KB) has its number at offset BANK-16 (the
last 16 bytes of the bank). The program (in bank 0, at 4000) maps page 2 to its slot (port A8), writes the bank registers the way
games of that mapper do (so the mapper detection of rom_detect.v sees it), then maps every bank
into the window at 8000, reads its number there and prints it with CHPUT of the BIOS:
    KONAMI 0123456789ABCDEF OK
A wrong mapper gives other digits; "OK" only when all of them match.

rammap.rom (16 KB, no mapper) tests the memory mapper of the RAM (ports FC-FF): it maps each of the
32 segments into page 2 (port FE), writes its number there, then maps them again and checks the
number, its complement and the value read back from the port (the segment with bits 7..5 set), and
that segment 32 is segment 0; it prints the number of good segments in hex:
    RAMMAP 20 OK
With the RAM of 64 KB (sim_sys --ram64) the ports do nothing and it must fail.

fmtest.rom (16 KB, no mapper, for cartridge A) tests the OPLL: it looks for "APRLOPLL" at 4018 of
slot 3-1 with RDSLT (the MSX-MUSIC ROM of C-BIOS in the layout of msx2_slots), prints
"FM OK" or "FM NONE", then keys on a note (violin) on the OPLL at the ports 7C-7D: the audio
output is loud with the OPLL (sim_sys --audio-min) and quiet without it (--no-opll, --audio-max).

kanjitest.rom (16 KB, no mapper) tests the kanji ROM ports (D8-D9 JIS level 1, DA-DB level 2): for
eight characters (four of each level) it sets the character, reads its 32 bytes and compares their
16-bit sum with the one of kanjifont.bin (256 KB, a pattern: sim_sys --rom kanjifont.bin:0x40000),
prints "o" for a match, "x" else, then " OK" when all match; the second read of each character must
start at byte 0 again (the counter is cleared by the writes):
    KANJI oooooooo OK
Without the font (no --rom) it must fail.

usage: mkcarts.py OUTDIR      (writes konami.rom, konami_scc.rom, ascii8.rom, ascii16.rom, keys.rom,
                               rammap.rom, fmtest.rom, kanjitest.rom, kanjifont.bin)
"""
import os
import subprocess
import sys

SJASM = os.environ.get('SJASMPLUS', '/opt/sjasmplus/sjasmplus')

# name, bank size, the init writes (address, value) the games do, the register of the window 8000
MAPPERS = [
    ('KONAMI', 0x2000, [(0x6000, 1), (0x8000, 2), (0xA000, 3)], 0x8000),
    ('KONAMI_SCC', 0x2000, [(0x5000, 0), (0x7000, 1), (0x9000, 2), (0xB000, 3)], 0x9000),
    ('ASCII8', 0x2000, [(0x6000, 0), (0x6800, 1), (0x7000, 2), (0x7800, 3)], 0x7000),
    ('ASCII16', 0x4000, [(0x6000, 0), (0x7000, 1)], 0x7000),
]
SIZE = 0x20000


def asm(name, bank, init, reg):
    n = SIZE // bank
    marker = 0x8000 + bank - 16
    inits = '\n'.join('\tld a,%d\n\tld (0x%04X),a' % (v, a) for a, v in init)
    return f"""
CHPUT	equ	0x00A2
	org	0x4000
	db	"AB"
	dw	start
	ds	12, 0
start:
	di
	ld	sp, 0xF380
	; page 2 to the slot of page 1 (the BIOS starts a cartridge with page 1 only), as games do
	in	a, (0xA8)
	ld	b, a
	and	0x0C
	add	a, a
	add	a, a
	ld	c, a
	ld	a, b
	and	0xCF
	or	c
	out	(0xA8), a
{inits}
	ld	hl, title
	call	print
	ld	c, 0		; errors
	ld	b, 0
loop:
	ld	a, b
	ld	(0x{reg:04X}), a
	ld	a, (0x{marker:04X})
	cp	b
	jr	z, same
	inc	c
same:
	call	hex
	inc	b
	ld	a, b
	cp	{n}
	jr	nz, loop
	ld	hl, bad
	ld	a, c
	or	a
	jr	nz, result
	ld	hl, good
result:
	call	print
stop:	jr	stop

hex:	push	bc
	and	0x0F
	add	a, '0'
	cp	'9' + 1
	jr	c, digit
	add	a, 7
digit:	call	CHPUT
	pop	bc
	ret

print:	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	print

title:	db	"{name} ", 0
good:	db	" OK", 0
bad:	db	" FAIL", 0
"""


KEYS = """
CHPUT	equ	0x00A2
CHGET	equ	0x009F
	org	0x4000
	db	"AB"
	dw	start
	ds	12, 0
start:
	ld	hl, title
print:	ld	a, (hl)
	or	a
	jr	z, keys
	call	CHPUT
	inc	hl
	jr	print
keys:	call	CHGET		; the BIOS reads the key matrix (PPI) in its interrupt
	call	CHPUT
	jr	keys
title:	db	"KEYS ", 0
"""


RAMMAP = """
CHPUT	equ	0x00A2
NSEG	equ	32
	org	0x4000
	db	"AB"
	dw	start
	ds	12, 0
start:
	di
	ld	sp, 0xF380	; page 3 = segment 0 (port FF), never changed here
	; page 2 to the slot of page 3 (the RAM)
	in	a, (0xA8)
	ld	b, a
	and	0xC0
	rrca
	rrca
	ld	c, a
	ld	a, b
	and	0xCF
	or	c
	out	(0xA8), a
	ld	b, 0
fill:	ld	a, b
	out	(0xFE), a
	ld	(0x8000), a
	cpl
	ld	(0x8001), a
	inc	b
	ld	a, b
	cp	NSEG
	jr	nz, fill
	ld	c, 0		; good segments
	ld	b, 0
check:	ld	a, b
	out	(0xFE), a
	in	a, (0xFE)
	ld	d, a
	ld	a, b
	or	0xE0
	cp	d
	jr	nz, next
	ld	a, (0x8000)
	cp	b
	jr	nz, next
	ld	a, (0x8001)
	cpl
	cp	b
	jr	nz, next
	inc	c
next:	inc	b
	ld	a, b
	cp	NSEG
	jr	nz, check
	; segment 32 is segment 0 (5 bits)
	ld	a, NSEG
	out	(0xFE), a
	ld	a, (0x8000)
	or	a
	jr	z, wrap
	ld	c, 0
wrap:	ld	a, 1
	out	(0xFE), a	; page 2 back to segment 1
	ld	hl, title
	call	print
	ld	a, c
	rrca
	rrca
	rrca
	rrca
	call	hex
	ld	a, c
	call	hex
	ld	hl, bad
	ld	a, c
	cp	NSEG
	jr	nz, result
	ld	hl, good
result:	call	print
stop:	jr	stop

hex:	push	bc
	and	0x0F
	add	a, '0'
	cp	'9' + 1
	jr	c, digit
	add	a, 7
digit:	call	CHPUT
	pop	bc
	ret

print:	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	print

title:	db	"RAMMAP ", 0
good:	db	" OK", 0
bad:	db	" FAIL", 0
"""


FMTEST = """
CHPUT	equ	0x00A2
RDSLT	equ	0x000C
	org	0x4000
	db	"AB"
	dw	start
	ds	12, 0
start:
	ld	sp, 0xF380
	ld	hl, 0x4018
	ld	de, sig
	ld	b, 8
find:	push	bc
	push	de
	ld	a, 0x87		; slot 3-1 (expanded)
	call	RDSLT
	pop	de
	pop	bc
	ld	c, a
	ld	a, (de)
	cp	c
	jr	nz, none
	inc	hl
	inc	de
	djnz	find
	ld	hl, ok
	jr	result
none:	ld	hl, nofm
result:	call	print
	di
	ld	bc, 0x3010	; instrument 1 (violin), volume 0 (the loudest)
	call	opll
	ld	bc, 0x10AC	; F-number low
	call	opll
	ld	bc, 0x2019	; key on, block 4, F-number bit 8
	call	opll
stop:	jr	stop

; OPLL register B = C, with the waits of the YM2413 (12 / 84 cycles of 3.58 MHz)
opll:	ld	a, b
	out	(0x7C), a
	ld	a, 4
w1:	dec	a
	jr	nz, w1
	ld	a, c
	out	(0x7D), a
	ld	a, 30
w2:	dec	a
	jr	nz, w2
	ret

print:	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	print

sig:	db	"APRLOPLL"
ok:	db	"FM OK", 0
nofm:	db	"FM NONE", 0
"""


def kanji_font():
    """the pattern font of kanjitest: 256 KB, byte o"""
    return bytes(((o * 37) ^ (o >> 7) ^ (o >> 13)) & 0xFF for o in range(0x40000))


KANJI_CHARS = [(1, 0x000), (1, 0x03F), (1, 0x5A5), (1, 0xFFF), (2, 0x000), (2, 0x1C3), (2, 0xA5A), (2, 0xFFF)]


def kanji_test():
    font = kanji_font()
    lines = []
    for lvl, c in KANJI_CHARS:
        base = (0x20000 if lvl == 2 else 0) + c * 32
        sm = sum(font[base:base + 32]) & 0xFFFF
        port = 0xD8 if lvl == 1 else 0xDA
        lines.append('\tdb\t0x%02X, 0x%02X, 0x%02X\n\tdw\t0x%04X' % (port, c & 63, c >> 6, sm))
    return KANJI_ASM.replace('@CHARS@', '\n'.join(lines)).replace('@N@', str(len(KANJI_CHARS)))


KANJI_ASM = """
CHPUT	equ	0x00A2
	org	0x4000
	db	"AB"
	dw	start
	ds	12, 0
start:
	ld	sp, 0xF380
	ld	hl, title
	call	print
	ld	ix, chars
	ld	b, @N@
	ld	e, 0		; the characters that did not match
next:	push	bc
	push	de
	call	sum		; the first read
	push	hl
	call	sum		; again: the counter starts at 0 after the writes
	pop	de
	or	a
	sbc	hl, de
	jr	nz, bad		; the two reads differ
	ex	de, hl
	ld	e, (ix+3)
	ld	d, (ix+4)
	or	a
	sbc	hl, de
	jr	nz, bad
	ld	a, 'o'
	pop	de
	jr	shown
bad:	ld	a, 'x'
	pop	de
	inc	e
shown:	push	de
	call	CHPUT
	pop	de
	ld	bc, 5
	add	ix, bc
	pop	bc
	djnz	next
	ld	a, e
	or	a
	jr	nz, stop
	ld	hl, ok
	call	print
stop:	jr	stop

; HL = the sum of the 32 bytes of the character at IX (port, low 6 bits, high 6 bits)
sum:	ld	c, (ix+0)
	ld	a, (ix+1)
	out	(c), a
	inc	c
	ld	a, (ix+2)
	out	(c), a
	ld	hl, 0
	ld	b, 32
s1:	in	a, (c)
	add	a, l
	ld	l, a
	jr	nc, s2
	inc	h
s2:	djnz	s1
	ret

print:	ld	a, (hl)
	or	a
	ret	z
	push	hl
	call	CHPUT
	pop	hl
	inc	hl
	jr	print

title:	db	"KANJI ", 0
ok:	db	" OK", 0
chars:
@CHARS@
"""


def plain(out, name, text):
    """a 16 KB cartridge without a mapper"""
    src = os.path.join(out, name + '.asm')
    raw = os.path.join(out, name + '.bin')
    open(src, 'w').write(text)
    subprocess.run([SJASM, '--nologo', '--raw=' + raw, src], check=True)
    code = open(raw, 'rb').read()
    open(os.path.join(out, name + '.rom'), 'wb').write(code + b'\xFF' * (0x4000 - len(code)))


def main():
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    # keys.rom: prints the keys it gets (the keyboard test of carts.txt)
    plain(out, 'keys', KEYS)
    plain(out, 'rammap', RAMMAP)
    plain(out, 'fmtest', FMTEST)
    plain(out, 'kanjitest', kanji_test())
    open(os.path.join(out, 'kanjifont.bin'), 'wb').write(kanji_font())
    for name, bank, init, reg in MAPPERS:
        src = os.path.join(out, name.lower() + '.asm')
        raw = os.path.join(out, name.lower() + '.bin')
        open(src, 'w').write(asm(name, bank, init, reg))
        subprocess.run([SJASM, '--nologo', '--raw=' + raw, src], check=True)
        code = open(raw, 'rb').read()
        rom = bytearray(b'\xFF' * SIZE)
        rom[:len(code)] = code
        for k in range(SIZE // bank):
            rom[k * bank + bank - 16] = k
        assert len(code) < bank - 16
        open(os.path.join(out, name.lower() + '.rom'), 'wb').write(rom)
        print(name.lower() + '.rom', len(code), 'bytes of code')


if __name__ == '__main__':
    main()
