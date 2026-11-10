# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## MSX2 (this repository)

`karabas-go-core-msx2` is the MSX2 / MSX2+ core, started 2026-11-10 from the history of `karabas-go-core-msx` (remote `msx1`, its `master` 65e67db): variant A of `docs/PLAN.md` (Russian) = the MSX1 machine with the ESE-VDP (V9958) of OCM-PLD instead of `vdp18`, the picture through a frame buffer in the SDRAM. Follow the phases of `docs/PLAN.md` and record decisions in its "Решения". The MSX1 plan and backlog are in `docs/msx1/`. Fixes of the MSX1 core (the Go physical floppy among them) come in by merging `msx1/master`.

State: Ф0 merged (#1). Ф1 (branch `f1-sim`): the ESE-VDP (`src/rtl/msx/vdp`, OCM-PLD `0a0f049`, imported unchanged in `3d16ab3`, then `-- karabas:` fixes, see `docs/UPSTREAM.md`) in the machine `src/rtl/msx/msx2.v` (module `msx2`, was `msx1.v`) on its own clock `clk21` (clk / 2 of the same PLL); its VRAM (128 KB at 3C0000) is a slot in four of `msx_sram` aligned to the VDP's DLCLK (the contract is in `docs/PLAN.md` "Решения"). `msx2_slots.v`: the expanded slots in two layouts, C-BIOS (slot 0 not expanded: C-BIOS stops otherwise) and OCM (for the system ROM image `OCM-BIOS.DAT`, FL slot 2, 512 KB at 000000); the system ROMs fill 000000-07FFFF as that image. `rtc.v` (RP5C01 of OCM) at B4-B5. The tape is 128 KB at 3E0000. `make msx2-xst` / `make msx2-report` synthesize the machine alone (`msx2.prj`, `msx2.xst` are force-added: `.gitignore` has `*.prj` / `*.xst`). The core is `msx2` (`core.json`: C-BIOS MSX2+ EU, `/msx2`, `msx2.kg`). **Not working yet:** `msx_video.v` and the board tops still have the `vdp18` interface: the boards build again in Ф2 (frame buffer in the SDRAM). The VDP gives hsync at twice the line rate in the vertical sync (equalizing pulses of `vdp_ntsc_pal`): count lines by time, not by hsync edges.

Simulation (Ф1): `sim_sys` runs on the 15 kHz output of the VDP (684 pixels a line, 262 / 313 lines, about 0.35 frames per second: the VDP netlist of ghdl is big). `--cbios DIR` loads C-BIOS MSX2+ EU at its places, `--fast-logo` skips the logo animation and the 120-frame wait of C-BIOS (a cartridge starts at about frame 25), `--bios FILE` loads a system ROM image (OCM-BIOS.DAT boots to its logo at about frame 200: about ten minutes, ask before such runs), `SIM_TRACE=N` (opcode fetches, writes to A8 / FFFF), `SIM_ISR=1` (interrupts and the address bus per frame). The suites `run_carts`, `run_fdd`, `run_tape`, `run_hdd` take 5-8 minutes each: **run them one at a time** (`run_tape` and `run_fdd` both write `sim/build/fdd`). Real BIOS files are never in the repo (the user's copies are outside it). In the rest of this file read `msx1` as `msx2` where it names the machine; the description of the boards, the loaders and the old MSX1 details stay until the phases change them.

## Overview

A port of an MSX1 machine to the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25-2, ISE 14.7 (XST). One core, three tops (`src/rtl/karabas_go_top.v` VGA + PCM5102, `karabas_mini_top.v` HDMI + sigma-delta + PCM1808 ADC, `karabas_minig_top.v` HDMI + PCM5102), as in `karabas-go-core-nes` and `karabas-go-core-tsconf`. Mini G is the first target.

Status: Ф0..Ф4 merged (#1..#5), Ф5 memory mapper (#7), OPLL (#8, jt2413), tree OSD (#9) and Nextor on a HDD image (#10, `nextor_sd.v`) merged; build 26103108 of Go / Mini / Mini G released 2026-10-31 (karabas-go, karabas-mini `cores/`; needs firmware v26103113+). Nextor itself is untested (needs a real BIOS; the list of checks is in `docs/BACKLOG.md`); next in Ф5: the physical floppy on Go. Mini G works on hardware: cartridges, the disk drive (DSK cached in the SRAM by `msx_fdd_cache.v`), the cassette (`.cas` via the FL item Tape into the SRAM at 3C0000 by `msx_tape.v`; TAPE_IN / TAPE_OUT untested); Go and Mini not tested on hardware. The repo is public (2026-10-31): `README.md` / `README.ru.md` (keep both in step with the OSD of `core*.json`), `LICENSE` GPL v3. What comes next (Ф5: mapper, OPLL, Nextor, the Go floppy) and the open checks: `docs/BACKLOG.md`. The disk ROM needs a real MSX BIOS (C-BIOS hangs with it): the OSD item `Slot 1 ROM` = Off (the disk ROM or the Nextor ROM reads FF) is for tests with C-BIOS. The plan is `docs/PLAN.md` (Russian): the upstream candidates, the architecture, the phases Ф0..Ф5 and the decisions. Follow its phases and record each decision in its "Решения" section. `docs/UPSTREAM.md`: what was taken from the upstream and what was changed. One branch and one PR per phase, merged at its end.

The main rule of this port: **all file work goes through the MCU firmware** (the OSD, the file loader `FL` items with `autoload`, the file mounter `F` items = `CMD_IMG_*`, bursts). The core has no soft CPU, no IPL, no FAT driver and no OSD menu of its own: only the MSX machine and a thin layer from `kg_mcu` to its interfaces. Do not bring in the SD / FAT / IPL boot of MSX1FPGA or OCM.

Base (variant C, decided 2026-10-30): MiSTer MSX1 (`MiSTer-devel/MSX1_MiSTer`, branch `main`, `d947f4a`): its `ioctl` (BIOS, cartridges, CAS) maps to the file loader of `kg_mcu`, its `img_mount` / `sd_*` (DSK on the VY0010 + WD1793 FDC) to `img_sdc`, the mapper detection is in RTL. Donor: MSX1FPGA (`fbelavenuto/msx1fpga`, the MSX core of ZX-Uno / ZXDOS) for the memory mapper, MegaRAM SCC, OPLL and Nextor on a HDD image (Ф5).

## Related repositories (siblings in `..`)

- `karabas-go-modules` (submodule `modules/`, from Ф0): `kg_mcu` (`ENABLE_IMG`), `img_sdc`, `kg_pll`, `kg_dcm`, the `kg_*` memories, `zhdmi`, `kg_osd_overlay`, the DACs. Its `CLAUDE.md` has the rules (Verilog-2001 for XST, no coregen, `ENABLE_*` parameters, clock crossings, tests). A change to them is made there and taken here by updating the submodule commit.
- `karabas-go-firmware`: the MCU side. `docs/protocol.md` (file loader, file mounter section 6, `CMD_CAPS` section 7) and `docs/burst_protocol.md`. This port needs no firmware change for Ф0..Ф4.
- `karabas-go-tools`: `make_core.py` packs `core.json` (one file for all boards: the common keys, `boards` for what differs; kgo2, karabas-go-tools `docs/kgo2.md`) into `msx.kg` (`make <board>-core`: `make_core.py core.json msx.kg --boards <board>` puts that board's bitstream in); `src/make_core.py` will be a symlink to it.
- Examples: `karabas-go-core-nes` (Makefile, `sv2v` of upstream SV, frame buffer video, `hid_parser`, burst sim), `karabas-go-core-nanomig` (`img_sdc` with a floppy, `FL` autoload of the Kickstart), `karabas-go-core-next186` (`img_sdc` + `hdf_ata`, `tb_ata` with an MCU model), `karabas-go-core-snes` (a port plan with a fit gate; the video timing lessons on the user's monitor).

## Build

- `cd src && make` builds the three boards (`make go`, `make mini`, `make minig`; steps `minig-xst`, `-impl`, `-core`; `make minig-report` the utilization and timing), the ISE command-line flow, sourcing `/opt/Xilinx/14.7/ISE_DS/settings64.sh`. No `.xise`, no `ipcore_dir`. The boards share `xst/` and `_ngo/` in `src/`: one build at a time.
- Inputs per board: `karabas_<board>.prj` (sources, the shared modules as `"../modules/rtl/..."`), `.xst`, `.ut`, `.ucf`. Map / par with cost table `-t 2` by default (`MAP_T_<board>`).
- Check `*_map.mrp` (LUTs, slices, RAMB16) and `*.par` (timing) after a change. The `.bin` and `.kg` files are committed as the release.
- `make msx1-xst` synthesizes the machine alone (`msx1.prj`, `msx1.xst`, `-iobuf NO`) in about a minute; `make msx1-report` prints its LUTs, registers and block RAMs. Use it to check a change of `src/rtl/msx` (errors, the one clock in "Clock Information" of `msx1.syr`, no latches) before a board build.
- Builds take 10..30 minutes: run them in the background, one board at a time, do not edit RTL while XST runs, and do not run builds of all boards without need.

## Layout

- `src/rtl/msx`: the machine (`msx1.v` and what it instantiates, see `docs/UPSTREAM.md`). Its memory port `mem_addr` / `mem_we` / `mem_din` / `mem_dout` goes to the SRAM; the map is at the end of `msx1.v` (000000 BIOS, 008000 the ROM of slot 0 page 2, 020000 the Nextor ROM 128 KB, 080000 RAM 512 KB of the memory mapper `ram_mapper.v`, 100000 cartridge B, 200000 cartridge A, 300000 the disk image, 3C0000 the tape). `spram.v` is the MiSTer `spram` on `kg_spram`. `tape.v` is the CAS player, used by `msx_tape.v`.
- `src/roms`: C-BIOS 0.29a (BSD-2, `LICENSE.cbios`) for the `roms` of `core.json`.
- `src/tools/mif2hex.py`: the `.mif` of the upstream to `$readmemh` files.
- `src/rtl/msx_system.v` (the machine, `msx_sram`, the loaders by FL slot, `msx_ps2_key`, the joysticks; the unit the simulation runs), `msx_video.v` (frame buffer 256 x 192 x 4 bits -> 640 x 480 at 60 Hz on clk_vga), `karabas_minig_top.v` (clocks, `kg_mcu`, soft switches, the OSD command fifo into clk_vga, `kg_osd_overlay`, `hdmi_tx` of zhdmi, audio). The soft switch indexes are listed at the top of the board top; they must match the `osd` of `core*.json`.
- `kg_mcu` `FILELOAD_SLOT` (modules branch `msx-core`, not in modules master yet): which FL item a file came from.

## Simulation

- `src/sim/sys/build.sh` builds `sim_sys` (verilator) into `src/sim/build/sys`: `tb_sys.v` = `msx_system` + `msx_video` + a model of the SRAM; the VHDL of the machine becomes Verilog through `ghdl --synth` (`vhdl2v.sh`, its comments list the fixes). `sim_sys --rom FILE:ADDR --cart FILE --frames N --ppm OUT [--every N] [--hash] [--key F:CODES] [--mapper-a N] [--pal] [--ram64]`, run from `src/` (the VY0010 `.hex` path). It loads as the mcu does (ROM loader, file loader), about 0.8 frames per second; C-BIOS reaches its text screen after about 150 frames. `SIM_DBG=1` prints the border colour changes.
- `src/sim/fdd/run_fdd.sh`: `fdctest.rom` (mkfdd.py) reads and writes sectors of a 720K and a 360K image through the mounter model of `sim_sys` (`--disk`, `--fdd-latency`, `--fdd-drop`), also with a lost answer and 40 ms per sector.
- `src/sim/tape/run_tape.sh`: `tapetest.rom` (mktape.py) decodes the tape of `test.cas` itself (C-BIOS has no tape routines), the CAS loaded at the burst rate while the disk image fills the SRAM, then cartridge B (its load starts with the slot of the CAS, as the firmware sends it); `bad.cas` must fail.
- `src/sim/hdd/run_hdd.sh`: `sdtest.rom` (mkhdd.py) drives the SD card of `nextor_sd.v` (slot 1 = Nextor without its ROM) as the Nextor driver of MSX1FPGA does: init, CSD, single and multiple block reads and writes on a 1 MB image (`--hdd`, F slot 6), then the saved image is checked.
- `src/sim/carts/run_carts.sh` (about 3 minutes, parallel): the test cartridges of `mkcarts.py` (sjasmplus: each maps every bank into 8000 and prints its number, `OK` when all match) against the frame CRCs of `carts.txt`, including one with a wrong mapper that must fail. A change of the machine, the SRAM or the video that changes a CRC: look at the `.ppm` in `src/sim/build/out`, then update `carts.txt`. No commercial ROMs in the repo or the tests.
- The modules have their own tests (`modules/sim/run_all.sh`).

## Rules

- **Upstream code** is in `src/rtl/msx` at a fixed commit (`docs/UPSTREAM.md`; the import commit `7085126` has the files unchanged) and keeps its form; local changes are marked `// karabas:` (`-- karabas:` in VHDL) with the reason. SystemVerilog is converted with `sv2v` (`/opt/sv2v/sv2v`); Altera memories become `kg_*`, `.mif` become `.hex`. The upstream clones for study go to `src/sim/build/upstream` (not in git).
- **Verilog-2001 that XST accepts** for our code (see the modules `CLAUDE.md`). No clocks from logic, no latches (check "Clock Information" of the `.syr`). What Quartus takes and XST does not (found in Ф0): wires used before their declaration, regs of a generate block used by their short name outside it, `x : work.y` without `entity`, constants on output ports, async resets to non-constant values (latches), registers clocked by strobes or clock enables.
- **Mini / Mini G must always drive `FT_CLK_OUT`** (~8 MHz) from the start of the core.
- **Video: standard timing only, syncs always present** (640x480@60 from a frame buffer); the user's Mini G monitor rejects anything else.
- **OSD switch index** = position of the item in the `osd` list of `core.json`, file items included: moving an item renumbers the soft switch registers after it.
- A test is worth something only if it fails without the code it covers. Simulators: verilator, iverilog, ghdl, ISim. If a tool is missing, ask the user to install it.
- Hardware tests are done by the user: ask before flashing anything.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`, `link.sh` there makes the links). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
