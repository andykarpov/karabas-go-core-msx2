# MSX2 core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

**Work in progress.** An MSX2 / MSX2+ core: the MSX1 core
[karabas-go-core-msx](https://github.com/andykarpov/karabas-go-core-msx) with the ESE-VDP (V9938 /
V9958) of [OCM-PLD](https://github.com/gnogni/ocm-pld-dev) and a frame buffer in the SDRAM. There is
no core file yet; the plan is `docs/PLAN.md` (Russian). The text below still describes the MSX1 core
this one starts from.

An MSX1 computer for the Karabas Go family of boards. It is a port of
[MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer) by molekula to the Xilinx Spartan-6
XC6SLX25 of the Karabas boards. All file work (cartridges, disk images, tapes, the BIOS) goes through
the OSD and the file browser of the board firmware: the core has no loader of its own.

| Board | Core file | Video | Audio |
|---|---|---|---|
| Karabas Go | `msx.kg` | VGA, 640x480 60 Hz | I2S DAC (PCM5102) |
| Karabas Mini | `msx.kg` | HDMI, 640x480 60 Hz | HDMI, analog output (sigma-delta) |
| Karabas Mini G | `msx.kg` | HDMI, 640x480 60 Hz | HDMI, I2S DAC (PCM5102) |

The core file is in `src/` and in the release repo
[karabas-go](https://github.com/andykarpov/karabas-go) (`cores/`, one file for all the boards).

**State:** the Mini G build is tested on hardware (cartridges and games; the disk drive and the tape
with test cartridges, not yet with a real MSX BIOS). The Mini and Go builds are made from the same sources and are not tested on hardware yet.

## What it does

- **The MSX1 of MSX1_MiSTer:** Z80 (T80), TMS9918 VDP (vdp18), AY-3-8910 PSG (jt49), PPI, 512 KB of
  RAM in slot 3 with the memory mapper of the MSX2 (ports FC-FF; the OSD item RAM, 64K: the plain
  64 KB of an MSX1).
- **MSX-MUSIC:** the OPLL (YM2413, [jt2413](https://github.com/jotego/jtopl)) at the ports 7C-7D, as
  the internal MSX-MUSIC of later machines: without cartridge B, slot 2 shows its ROM signature
  (`APRLOPLL`), so games find it. The OSD item FM (MSX-MUSIC) turns it off.
- **BIOS:** [C-BIOS](http://cbios.sourceforge.net/) 0.29a is built into the core (EU version with
  its logo). It boots cartridges, but it has no BASIC and no tape or disk routines. For BASIC, disk
  and tape software load the BIOS of a real MSX1 with the OSD item BIOS (32 KB, or 48 KB with a
  ROM for page 2 of slot 0); it is loaded again at every start of the core.
- **Two cartridge slots** (A in slot 1, B in slot 2), up to 1 MB each, with the mapper found from
  the ROM: none (plain 16 / 32 / 48 KB), Konami, Konami SCC (with the SCC sound), ASCII 8, ASCII 16,
  Game Master 2, linear 64 KB. The OSD items Mapper A / Mapper B override the detection.
- **Disk drive:** the Philips VY-0010 interface (WD1793 FDC and its disk ROM) in slot 1 instead of
  cartridge A, with `.dsk` images of 360 or 720 KB. The image is read into the SRAM of the board in
  the background after it is mounted, so the drive works at the speed of a real one; writes go to
  the SRAM and to the image file at once. A read only image file (or a read only F item) is a
  write protected disk.
- **Physical floppy drives (Karabas Go):** Disk A and Disk B can be the drives of the floppy
  connector (`[ Physical A ]` / `[ Physical B ]` in the file browser, the drives DS0 / DS1). They
  are driven by a model of the WD1793 (the VG93 model of
  [FD1793_1818VG93](https://github.com/demyanenko-d/FD1793_1818VG93), as in the Profi core) at the
  pins, so the disk ROM reads, writes and formats real 720 KB / 360 KB MSX disks. Disk A can be an
  image or a physical drive, Disk B only a physical drive.
- **Nextor on a hard disk image:** the SD interface of MSX1FPGA in slot 1 (instead of cartridge A
  or the drive) with its Nextor driver, on an image file (`.img`, `.hdd`, `.vhd`, `.dsk`) of the SD
  card of the board: the core answers as an SD card, the sectors come from the image through the
  firmware. The Nextor ROM is a file (`NEXTOR.ROM` of MSX1FPGA, `Support/SD/MSX1FPGA`), not in the
  core. Nextor mounts `.dsk` files of its FAT partition itself.
- **Tape:** `.cas` files (up to 256 KB) played to the cassette input of the MSX at 2400 baud while
  the motor of the PPI is on, as on a real tape recorder (`RUN"CAS:"`, `BLOAD"CAS:",R`, `CLOAD`).
  The TAPE_IN pin of the board can be the cassette input instead (a real tape recorder), TAPE_OUT
  carries the cassette output (`CSAVE`).
- **Video:** the 256x192 picture with its border in the middle of 640x480 at 60 Hz (a frame buffer),
  the PAL (50 Hz) or NTSC (60 Hz) timing of the VDP chosen in the OSD. HDMI with sound on Mini and
  Mini G.
- **Input:** the USB keyboard as the MSX keyboard, two MSX joysticks: the joysticks of the board or
  USB gamepads.

Not there yet (see `docs/BACKLOG.md`): SCC MegaRAM, FM-PAC, the save RAM of Game Master 2 and other
battery cartridges.

## Getting started

1. Copy `msx.kg` (one file for Go, Mini and Mini G) to the root of the SD card.
2. Put your files into the folder `/msx` of the SD card: cartridges (`.rom`, `.mx1`, `.mx2`, `.bin`),
   disk images (`.dsk`), tapes (`.cas`), a BIOS (`.rom`), `NEXTOR.ROM` and hard disk images.
3. Choose MSX1 in the core menu, open the OSD with Menu+Esc and load a cartridge with Cart A
   (Menu+F1). The machine starts the cartridge when it is loaded.

Disks and tapes need a real MSX BIOS (OSD item BIOS): C-BIOS hangs in the INIT of the disk ROM.
For a disk: Machine > Slot 1 = Disk drive, then a `.dsk` in Disk A (on the Go also `[ Physical A ]`
or `[ Physical B ]` in Disk A / Disk B for the drives of the floppy connector). For Nextor: Machine > Slot 1 =
Nextor, then the image in HDD (Nextor needs a real BIOS too). For a tape: a `.cas` in Tape, then
`RUN"CAS:"` (BASIC programs), `BLOAD"CAS:",R` (machine code) or `CLOAD` + `RUN`; Tape rewind starts
the file again.

## OSD menu

The main page has the media, video and reset items; the machine settings are on the page Machine
(Enter / Right opens it, Esc goes back). The firmware v26103113 or later shows the pages; an older
one shows all items in one list.

| Item | Values | Hotkey |
|---|---|---|
| Cart A | a cartridge for slot 1 (shown when Slot 1 = Cartridge A) | Menu+F1 |
| Disk A | the `.dsk` image of the drive, on the Go also a physical drive (shown when Slot 1 = Disk drive) | Menu+F3 |
| Disk B | Go only: a physical drive as drive B (shown when Slot 1 = Disk drive) | Menu+F6 |
| HDD | the hard disk image of Nextor (shown when Slot 1 = Nextor) | Menu+F5 |
| Cart B | a cartridge for slot 2 | Menu+F2 |
| Tape | a `.cas` file (grey when Tape input = Tape in) | Menu+F4 |
| Tape rewind | the tape from its start (as Tape) | Menu+R |
| Video | PAL 50Hz / NTSC 60Hz | Menu+V |
| Joysticks | Normal / Swap | Menu+J |
| **Machine** ► | | |
| Reset | resets the MSX | F12 |
| Eject carts | removes both cartridges (and resets) | Menu+E |
| *Machine:* Slot 1 | Cartridge A / Disk drive / Nextor | Menu+D |
| Slot 1 ROM | On / Off (grey for Cartridge A) | |
| Mapper A | Auto / None / Game Master 2 / Konami / Konami SCC / ASCII 8 / ASCII 16 / Linear 64K (grey when Slot 1 is not Cartridge A) | |
| Mapper B | as Mapper A | |
| RAM | 512K mapper / 64K | |
| FM (MSX-MUSIC) | On / Off | |
| Tape input | CAS file / Tape in (TAPE_IN) | |
| BIOS | a BIOS file, loaded at every start | |
| Nextor ROM | the Nextor ROM (128 KB), loaded at every start (default `NEXTOR.ROM`) | |

"Menu" is the Windows key of the keyboard. Loading a cartridge, a BIOS or the Nextor ROM, or changing
a mapper, Slot 1, RAM or FM, resets the machine; loading a tape does not. Slot 1 ROM = Off leaves the
disk drive or the SD interface without its ROM (only its registers), for test programs that drive
them themselves under C-BIOS.

## Keyboard

The keys of the PC keyboard are the keys of the MSX in their places. The special keys of the MSX:

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

The core is built with Xilinx ISE 14.7 on Linux: `cd src && make` (all three boards, one after the
other), or `make go`, `make mini`, `make minig`; `make minig-report` shows the utilization and the
timing of the last build. The board modules are the submodule `modules/`
([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules)): clone with
`git clone --recursive` or run `git submodule update --init`. Packing the `.kg` files needs the
sibling repo [karabas-go-tools](https://github.com/andykarpov/karabas-go-tools) next to this one
(`make_core.py`).

The simulations (verilator with ghdl for the VHDL; regressions of the cartridge mappers, the disk
drive and the tape) are in `src/sim`. `CLAUDE.md` has the layout and the rules of the design,
`docs/PLAN.md` (Russian) the plan and the decisions, `docs/UPSTREAM.md` what was taken from the
upstream and what was changed.

The board firmware is [karabas-go-firmware](https://github.com/andykarpov/karabas-go-firmware).

## Credits and license

- [MSX1_MiSTer](https://github.com/MiSTer-devel/MSX1_MiSTer): molekula and the MiSTer contributors
  (the machine, the slots and mappers, the VY-0010 / WD1793 disk interface, the CAS player).
- T80: Daniel Wallner, MikeJ, Sorgelig and others. vdp18: Arnim Laeuger. jt49, jt8255 and jt2413 (jtopl): Jose
  Tejada.
- [C-BIOS](http://cbios.sourceforge.net/): the C-BIOS team.
- [FD1793_1818VG93](https://github.com/demyanenko-d/FD1793_1818VG93): the VG93 / WD1793 model of
  the physical floppy drives (thanks there to deathsoft and dr.Titus); the data separator after
  fapch_zek by ZEK (ZX-Evolution).
- Karabas Go boards and the port: Andy Karpov.

The core is under the GNU GPL v3 (`LICENSE`). Its parts keep their own licenses, all compatible with
it: MSX1_MiSTer GPL v2 or later, jt49 and jtopl GPL v3, T80 and vdp18 BSD-style licenses, jt8255 MIT,
C-BIOS a BSD 2-clause license (`src/roms/LICENSE.cbios`; the C-BIOS ROMs are built into the core
files). The disk ROM of the VY-0010 (`src/rtl/msx/rom`) comes from MSX1_MiSTer. The VG93 model
(`src/rtl/vg93`) states no license in its repository.

The ESE-VDP (`src/rtl/msx/vdp`, Kunihiko Ohnaka, from OCM-PLD of KdL) has a BSD-style license that
also says it may not be sold or used in a commercial product or activity without written
permission. That condition is not compatible with the GPL and it holds for the core files that
contain the VDP: they are for non-commercial use.
