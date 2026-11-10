# MSX2 core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

**Work in progress.** An MSX2 / MSX2+ computer for the Karabas Go family of boards: the machine of
the MSX1 core [karabas-go-core-msx](https://github.com/andykarpov/karabas-go-core-msx) (a port of
[MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer) by molekula) with the ESE-VDP (V9958 /
V9938) and the RTC of [OCM-PLD](https://github.com/gnogni/ocm-pld-dev) (KdL), the picture through a
frame buffer in the SDRAM. The Xilinx Spartan-6 XC6SLX25 of the boards. All file work (cartridges,
disk images, tapes, the BIOS) goes through the OSD and the file browser of the board firmware: the
core has no loader of its own. The plan and the decisions are in `docs/PLAN.md` (Russian).

| Board | Core file | Video | Audio | State |
|---|---|---|---|---|
| Karabas Mini G | `msx2.kg` | HDMI, 640x480 60 Hz | HDMI, I2S DAC (PCM5102) | tested on hardware |
| Karabas Mini | — | | | not built yet |
| Karabas Go | — | | | not built yet |

The core file is `src/msx2.kg` (Mini G only for now). It needs the firmware v26103113 or later.

## What it does

- **MSX2 / MSX2+:** Z80 (T80) at 3.58 MHz, the ESE-VDP of OCM-PLD as a V9958 (MSX2+: YJK screens
  10..12, horizontal scroll) or a V9938 (OSD item VDP), 128 KB of VRAM, AY-3-8910 PSG (jt49), PPI,
  512 KB of RAM with the memory mapper (ports FC-FF; the OSD item RAM, 64K: plain 64 KB), the RTC
  RP5C01 (ports B4-B5) with the time of the board.
- **MSX-MUSIC:** the OPLL (YM2413, [jt2413](https://github.com/jotego/jtopl)) at the ports 7C-7D, the
  MSX-MUSIC ROM in its slot (C-BIOS: 3-1, the OCM BIOS: 0-2). The OSD item FM (MSX-MUSIC) turns it
  off.
- **Two cartridge slots** (A in slot 1, B in slot 2), up to 1 MB each, with the mapper found from
  the ROM: none (plain 16 / 32 / 48 KB), Konami, Konami SCC (with the SCC sound), ASCII 8, ASCII 16,
  Game Master 2, linear 64 KB. The OSD items Mapper A / Mapper B override the detection.
- **Disk drive:** the Philips VY-0010 interface (WD1793 FDC and its disk ROM, Disk BASIC 1.0) in
  slot 1 instead of cartridge A, with `.dsk` images of 360 or 720 KB, read into the SRAM of the board
  in the background; writes go to the SRAM and to the image file at once. A read only image file is
  a write protected disk. The physical floppy drives of the Karabas Go come with its build.
- **Nextor on a hard disk image:** the SD interface of MSX1FPGA in slot 1 (instead of cartridge A
  or the drive) with its Nextor driver, on an image file (`.img`, `.hdd`, `.vhd`, `.dsk`) of the SD
  card of the board. The Nextor ROM is a file (see "BIOS and Nextor"). Mounting the first image
  resets the machine, so Nextor finds its disk at the start of the core.
- **Tape:** `.cas` files (up to 128 KB) played to the cassette input while the motor of the PPI is
  on, as on a real tape recorder (`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD`). The TAPE_IN pin of the
  board can be the cassette input instead, TAPE_OUT carries the cassette output (`CSAVE`).
- **The settings of the MSX (the CMOS of the RTC)** are kept on the SD card: `SET SCREEN`,
  `SET PROMPT`, `SET BEEP`, `SET TITLE`, the password. The board firmware keeps them in
  `/config/msx2.eep` and gives them back at every start of the core. The time and the date are those
  of the clock of the board; setting them from the MSX (`TIME`, `DATE`, `SET TIME`) does not change
  the board clock.
- **Video:** the picture of the VDP (256 or 512 dots, 192 / 212 lines, with its border) in 640x480
  at 60 Hz from a frame buffer in the SDRAM; the VDP runs in its PAL (50 Hz) or NTSC (60 Hz) timing:
  Auto follows register 9 (the BIOS, the programs), or the OSD item Video forces one. Interlaced
  modes show one field.
- **Input:** the USB keyboard as the MSX keyboard, two MSX joysticks: the joysticks of the board or
  USB gamepads.

Checked on the Mini G: C-BIOS and the OCM BIOS (MSX BASIC 3.0), cartridges with sound (PSG, MSX-MUSIC),
the VDP screens of the V9958 (also YJK), Disk BASIC on a `.dsk`, Nextor 2.1 on a hard disk image,
a `.cas` game, the time of the board and the CMOS kept over a restart. Not checked on hardware yet:
TAPE_IN / TAPE_OUT, the joysticks, the 50 Hz timing, the V9938 setting.

Not there yet (`docs/PLAN.md`): the Karabas Go and Mini builds, the kanji ROM (ports D8-DB), turbo,
the interlace of two fields, SCC MegaRAM, FM-PAC, battery cartridges.

## BIOS and Nextor

The core boots with **C-BIOS** 0.29a (MSX2+, EU, with its logo), built into the core file. C-BIOS
starts cartridges, but has no BASIC, no tape and no disk routines (the disk ROM and Nextor hang with
it). For BASIC, disks, tapes and Nextor load a real BIOS with the OSD item **BIOS** (Machine page): it
is loaded again at every start of the core.

The BIOS item takes **a system ROM image of OCM-PLD** (1chipMSX / MSX++), the file `OCM-BIOS.DAT`
(512 KB: the SDBIOS of OCM-PLD, also in the uMSX SD card set). Other images, such as the 32 KB main ROM
of a real machine, are not supported yet: the core places the system ROMs as that image does.

| In `OCM-BIOS.DAT` | Contents | Slot |
|---|---|---|
| 000000 | ESE-RAM / Nextor of OCM | off (reads FF) |
| 020000 | MSX2+ main ROM (MSX BASIC 3.0) | 0-0 |
| 028000 | XBASIC | 3-3 |
| 02C000 | MSX-MUSIC | 0-2 |
| 030000 | sub-ROM, kanji BASIC | 3-1 |
| 040000 | kanji font | (no kanji ports yet) |

RAM is in slot 3-0. With C-BIOS the layout is that of its openMSX configuration instead: slot 0 not
expanded (main ROM, logo), 3-0 sub-ROM, 3-1 MSX-MUSIC, 3-2 RAM. The layout follows the file: the C-BIOS
one until a BIOS file is loaded.

What to know about the OCM BIOS:

- **Its keyboard is Japanese.** The keys of a PC keyboard give the characters of a Japanese MSX:
  Shift+2 is `"`, Shift+minus is `=`, Shift+8 / Shift+9 are `(` / `)`, the key right of `;` is `:`.
- **It sets the CMOS of the RTC at every start from its own image** (the 1chipMSX has no battery:
  the tool RTCSAVE of OCM writes the settings into the BIOS file on its SD card). The core gives it the
  settings of `/config/msx2.eep` instead, so `SET SCREEN` and the others are kept; RTCSAVE is not needed
  and not used.
- Its own Nextor (000000 of the image) is not used: Nextor runs in slot 1 (Machine > Slot 1 = Nextor)
  with the ROM of the OSD item Nextor ROM.
- MSX-MUSIC is in slot 0-2: a program that looks for it only in another slot does not find it.

**Nextor ROM:** the `NEXTOR.ROM` of MSX1FPGA (`Support/SD/MSX1FPGA`, Nextor 2.1 with the driver of its
SD interface, SHA-1 `ffb666c031edac8642c637a42af770ad2c10c764`), in `/msx2` (the default name of the
item). Nextor ROMs with the drivers of other hardware stop with "Bad drive name".

## Getting started

1. Copy `msx2.kg` to the root of the SD card.
2. Put your files into the folder `/msx2` of the SD card: cartridges (`.rom`, `.mx1`, `.mx2`,
   `.bin`), disk images (`.dsk`), tapes (`.cas`), `OCM-BIOS.DAT`, `NEXTOR.ROM` and hard disk images.
3. Choose MSX2 in the core menu, open the OSD with Menu+Esc and load a cartridge with Cart A
   (Menu+F1). The machine starts the cartridge when it is loaded.
4. For BASIC: Machine > BIOS = `OCM-BIOS.DAT` (MSX BASIC 3.0 starts).

For a disk: Machine > Slot 1 = Disk drive, then a `.dsk` in Disk A. For Nextor: Machine > Slot 1 =
Nextor, then the image in HDD (Nextor starts with `A:\>`; `BASIC` goes to BASIC, `CALL SYSTEM` back).
For a tape: a `.cas` in Tape (Menu+F4), then `RUN"CAS:"` (BASIC programs), `BLOAD"CAS:",R` (machine
code) or `CLOAD` + `RUN`; Tape rewind starts the file again. Disks, tapes and Nextor need the BIOS file.

## OSD menu

The main page has the media, video and reset items; the machine settings are on the page Machine
(Enter / Right opens it, Esc goes back).

| Item | Values | Hotkey |
|---|---|---|
| Cart A | a cartridge for slot 1 (shown when Slot 1 = Cartridge A) | Menu+F1 |
| Disk A | the `.dsk` image of the drive (shown when Slot 1 = Disk drive) | Menu+F3 |
| HDD | the hard disk image of Nextor (shown when Slot 1 = Nextor) | Menu+F5 |
| Cart B | a cartridge for slot 2 | Menu+F2 |
| Tape | a `.cas` file (grey when Tape input = Tape in) | Menu+F4 |
| Tape rewind | the tape from its start (as Tape) | Menu+R |
| Video | Auto / PAL 50Hz / NTSC 60Hz | Menu+V |
| Joysticks | Normal / Swap | Menu+J |
| **Machine** ► | | |
| Reset | resets the MSX | F12 |
| Eject carts | removes both cartridges (and resets) | Menu+E |
| *Machine:* Slot 1 | Cartridge A / Disk drive / Nextor | Menu+D |
| Slot 1 ROM | On / Off (grey for Cartridge A) | |
| Mapper A | Auto / None / Game Master 2 / Konami / Konami SCC / ASCII 8 / ASCII 16 / Linear 64K (grey when Slot 1 is not Cartridge A) | |
| Mapper B | as Mapper A | |
| VDP | V9958 (MSX2+) / V9938 (MSX2) | |
| RAM | 512K mapper / 64K | |
| FM (MSX-MUSIC) | On / Off | |
| Tape input | CAS file / Tape in (TAPE_IN) | |
| BIOS | the system ROM image (`OCM-BIOS.DAT`), loaded at every start | |
| Nextor ROM | the Nextor ROM (128 KB), loaded at every start (default `NEXTOR.ROM`) | |

"Menu" is the Windows key of the keyboard. Loading a cartridge, a BIOS or the Nextor ROM, or changing
a mapper, Slot 1, RAM or FM, resets the machine; loading a tape does not. Slot 1 ROM = Off leaves the
disk drive or the SD interface without its ROM (only its registers), for test programs that drive
them themselves under C-BIOS.

## Keyboard

The keys of the PC keyboard are the keys of the MSX in their places (see above for the Japanese
characters of the OCM BIOS). The special keys of the MSX:

| MSX | PC |
|---|---|
| GRAPH | Right Alt |
| CODE | F10 |
| SELECT | F11 |
| STOP | Print Screen |
| dead key | F9 |
| HOME, INS, DEL, arrows | the same keys |
| F1..F5 | F1..F5 |

## Building

The core is built with Xilinx ISE 14.7 on Linux: `cd src && make minig`; `make minig-report` shows
the utilization and the timing of the last build. The board modules are the submodule `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): clone with
`git clone --recursive` or run `git submodule update --init`. Packing the `.kg` file needs the sibling
repo [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this one
(`make_core.py`).

The simulations (verilator with ghdl for the VHDL) are in `src/sim`: the system with C-BIOS
(`sim/sys`, also with a BIOS file and the RTC / CMOS of the board), the regressions of the cartridge
mappers, the disk drive, the tape, Nextor's SD interface and the VDP screens, and the frame buffer.
`CLAUDE.md` has the layout and the rules of the design, `docs/PLAN.md` (Russian) the plan and the
decisions, `docs/UPSTREAM.md` what was taken from the upstream and what was changed.

The board firmware is [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Credits and license

- [MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer): molekula and the MiSTer contributors
  (the machine, the slots and mappers, the VY-0010 / WD1793 disk interface, the CAS player).
- [OCM-PLD](https://github.com/gnogni/ocm-pld-dev): KdL and the OCM contributors; the ESE-VDP by
  Kunihiko Ohnaka, the RTC module by HRA!.
- T80: Daniel Wallner, MikeJ, Sorgelig and others. jt49, jt8255 and jt2413 (jtopl): Jose Tejada.
- [MSX1FPGA](https://github.com/fbelavenuto/msx1fpga): Fabio Belavenuto (the memory mapper, the SD
  interface of Nextor).
- [C-BIOS](http://cbios.sourceforge.net/): the C-BIOS team.
- Karabas Go boards and the port: Andy Karpov.

The core's own code is under the GNU GPL v3 (`LICENSE`). Its parts keep their own licenses:
MSX1_MiSTer GPL v2 or later, jt49 and jtopl GPL v3, T80 a BSD-style license, jt8255 MIT, C-BIOS a BSD
2-clause license (`src/roms/LICENSE.cbios`; the C-BIOS ROMs are built into the core file). The disk ROM
of the VY-0010 (`src/rtl/msx/rom`) comes from MSX1_MiSTer.

The ESE-VDP (`src/rtl/msx/vdp`) and the RTC (`src/rtl/msx/rtc.v`) of OCM-PLD have a BSD-style license
that also says they may not be sold or used in a commercial product or activity without written
permission. That condition is not compatible with the GPL and it holds for the core file, which
contains them: **the core is for non-commercial use.**

No BIOS of a real machine is in this repository or in the core file.
