`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_system.v

 The MSX2 part of the three tops: the machine (msx2: msx1 of MiSTer MSX1 with the ESE-VDP, rtl/msx),
 the SRAM, the loaders of the mcu, the keyboard and the joysticks. Also the unit the simulation runs.

 Loading (all of it through the firmware, no loader in the core):
 - the ROM loader (the roms of core.json, at core start): rom_addr is the SRAM byte address (the
   system ROMs from 000000 as msx2_slots lays them out: C-BIOS main 020000, sub 030000, MSX-MUSIC
   02C000, logo 03C000), the machine is held in reset while rom_active;
 - the file loader (FL items, ioctl, one write per byte): file_slot 4 = cartridge A (slot 1 of the
   MSX; not 0: the firmware keeps the F and FL items in one array of file slots, and slot 0 is the
   disk of the F item), 1 = cartridge B (slot 2), 2 = the system ROM image of 512 KB (OCM-BIOS.DAT
   of OCM-PLD, from 000000; it switches the logo ROM of C-BIOS in slot 0-0 page 2 off),
   3 = a .cas file of the cassette (msx_tape, in the SRAM from 3E0000, 128 KB; no reset), 5 = the
   Nextor ROM of 128 KB (the SD interface of MSX1FPGA, in the SRAM from 000000).
   The machine is in reset while a cartridge or a BIOS file loads, as MiSTer has it. A cartridge is on from its load
   until eject.
 The disk drive (fdd: slot 1 is the Philips VY-0010 with its WD1793 and disk ROM in place of
 cartridge A): the .dsk image of the F item, slot 0 of the file mounter, through img_sdc; a copy of
 it in the SRAM from 300000 (msx_fdd_cache: filled in the background, write-through), so a sector
 is in the FDC in about 100 us instead of the 5-15 ms of the firmware.
 The physical floppy drives (FDD_PHYS = 1, Karabas Go): the F item of drive A (slot 0) or of drive B
 (slot 7, physical drives only) set to [ Physical A ] / [ Physical B ] of the firmware (CMD_IMG_PHYS:
 DS0 / DS1 of the floppy connector); such a drive is on the VG93 model at the pins (vy0010,
 msx_fdc_phys), the image of drive A on the wd1793 of MiSTer. Write protected images (IMG_WP of the
 firmware): the wd1793 of drive A and the SD interface of Nextor show them so.
 The mapper of a cartridge: mapper_a / mapper_b, the values of MiSTer (0 auto, 1 none,
 2 Game Master 2, 3 Konami, 4 Konami SCC, 5 ASCII 8, 6 ASCII 16, 7 linear 64K, 8 R-Type; the OSD offers 0-7, eight options at most); a change
 resets the machine.

 clk is 42.857 MHz (12 x 3.57 MHz): ce_10m7 is every fourth clock, as in MiSTer (42.95 MHz there).
 clk21 is clk / 2 from the same PLL (rising edges together): the clock of the VDP.
*/

module msx_system #(
	parameter FDD_PHYS = 0,         // the physical floppy drives (Karabas Go)
	parameter TAPE_SILENT = 1000,   // the CAS player (msx_tape): shorter in the simulation
	parameter TAPE_SYNC = 1454,
	parameter [25:0] RTC_TIME_DELAY = 26'd32000000   // msx2_rtc: the time ~0.75 s after the start
) (
	input wire clk,
	input wire clk21,          // the VDP: clk / 2, rising edges with those of clk
	input wire reset,          // the reset switch, the mcu busy
	input wire rtc_start,      // a pulse: the mcu is done with its start, the clock registers of kg_mcu are set
	output wire [7:0] rtc_a,   // the clock registers of kg_mcu (rtc_mode 0, eeprom_bank 4): the address, the data a clock later
	input wire [7:0] rtc_do,
	output wire [7:0] rtc_di,  // a CMOS nibble the CPU wrote: to the .eep of the core
	output wire rtc_cs,
	output wire rtc_wr_n,
	output wire [15:0] rtc_dbg,

	// the ROM loader of the mcu
	input wire rom_active,
	input wire [31:0] rom_addr,
	input wire [7:0] rom_data,
	input wire rom_wr,

	// the file loader of the mcu (FL items)
	input wire file_reset,     // one clock with a new file_slot (IOCTL_SLOT)
	input wire file_active,
	input wire [7:0] file_slot,
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,

	// settings (soft switches)
	input wire [3:0] mapper_a,
	input wire [3:0] mapper_b,
	input wire pal,            // 50 Hz when not pal_auto
	input wire pal_auto,       // 50 / 60 Hz from R9 of the VDP (the BIOS)
	input wire v9958,          // the VDP is a V9958 (MSX2+), else a V9938 (MSX2)
	input wire joy_swap,
	input wire tape_rewind,    // the OSD item, the CAS file from its start
	input wire tape_line,      // the cassette input is TAPE_IN (a tape recorder), not the CAS file
	input wire tape_in,        // TAPE_IN of the board (asynchronous)
	output wire tape_out,      // TAPE_OUT: the cassette write data of the PPI (CSAVE)
	input wire eject,          // the cartridges off (a reset as well)
	input wire fdd,            // slot 1 is the disk drive (Philips VY-0010) instead of cartridge A
	input wire ram_mapper,     // the RAM of slot 3 is 512 KB with the memory mapper (ports FC-FF), else 64 KB
	input wire opll,           // the OPLL (MSX-MUSIC) at the ports 7C-7D, its ROM signature in slot 2 without cartridge B
	input wire nextor,         // slot 1 is the SD interface for Nextor on the hard disk image (F slot 6) instead
	input wire fdd_rom_en,     // its disk ROM answers (0: the FDC registers only: C-BIOS hangs in the
	                           // INIT of the Philips disk ROM, which needs a real BIOS with BASIC)

	// the file mounter of kg_mcu (IMG_*), slot 0 = the disk of the drive
	input wire [7:0] img_mounted,
	input wire [63:0] img_size,
	input wire img_data_wr,
	input wire [8:0] img_data_addr,
	input wire [7:0] img_data,
	input wire img_result_wr,
	input wire [7:0] img_result,
	input wire [15:0] img_sum,
	output wire img_q_wr,
	output wire [23:0] img_q_di,
	input wire img_q_ack,
	input wire img_phys_wr,    // IMG_PHYS of kg_mcu: { slot, drive } (drive 1 DS0, 2 DS1), one clock
	input wire [15:0] img_phys,
	input wire [7:0] img_wp,   // IMG_WP of kg_mcu: the image of slot n is write protected
	input wire [3:0] fdd_in,   // the floppy connector (FDD_PHYS), high = active: { rdata, wprt, tr00, index }
	output wire [7:0] fdd_out, // { wdata, wgate, side1, step, dir, motor, ds1, ds0 }
	output wire fdd_active,    // a sector is being transferred (a LED)
	output wire fdd_filling,   // the copy of the image in the SRAM is not complete yet
	output wire [10:0] fdd_filled,

	// input
	input wire [7:0] kb_scancode,
	input wire kb_scancode_upd,
	input wire [12:0] joy_l,   // kg_mcu: 1 up, 2 down, 3 left, 4 right, 6 A, 7 B
	input wire [12:0] joy_r,

	// the picture of the VDP at 15 kHz (clk21): R / G / B, the syncs, the pixel enables (dhclk
	// 10.7 MHz: a pixel of the 512 modes; dlclk 5.37 MHz), the blanking, interlace
	output wire [7:0] vdp_r,
	output wire [7:0] vdp_g,
	output wire [7:0] vdp_b,
	output wire vdp_hs_n,
	output wire vdp_vs_n,
	output wire vdp_dhclk,
	output wire vdp_dlclk,
	output wire vdp_blank,
	output wire vdp_interlace,

	output reg [15:0] audio = 16'd0,  // two's complement, registered (the path through the mixer of msx1 is long)

	// SRAM
	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

// ------------------------------------------------------------------ clock enable

reg [2:0] div = 3'd0;
reg ce_10m7 = 1'b0;
reg ce_5m3 = 1'b0;        // the clock of the CAS player, as MiSTer has it
always @(posedge clk) begin
	div <= div + 3'd1;
	ce_10m7 <= div[1:0] == 2'd0;
	ce_5m3 <= div == 3'd0;
end

// ------------------------------------------------------------------ loads

// the firmware turns file_active on before it sends the slot (core_ioctl_send: IOCTL_STATE 1, then
// IOCTL_SLOT): until file_reset file_slot is the one of the file before (a cartridge after a CAS file
// started as a CAS load and emptied it). A load counts from its file_reset.
reg slot_ok = 1'b0;
always @(posedge clk)
	if (!file_active)
		slot_ok <= 1'b0;
	else if (file_reset)
		slot_ok <= 1'b1;
wire file_on = file_active && slot_ok;
wire ioctl_isROMA = file_on && file_slot == 8'd4;
wire ioctl_isROMB = file_on && file_slot == 8'd1;
wire ioctl_isBIOS = file_on && file_slot == 8'd2;
wire ioctl_isCAS = file_on && file_slot == 8'd3;
wire ioctl_isNEXTOR = file_on && file_slot == 8'd5;
wire ioctl_download = ioctl_isROMA || ioctl_isROMB || ioctl_isBIOS || ioctl_isNEXTOR;

reg [1:0] rom_enabled = 2'b00;
reg logo_en = 1'b1;        // C-BIOS (the roms of core.json) until a system ROM image is loaded
// the ROM loader does not write the system ROMs (000000-07FFFF) over a system ROM image: the firmware may
// send the roms of core.json after the autoload of the BIOS item (seen on 26111002: C-BIOS over the main
// ROM of OCM-BIOS.DAT in the slot layout of OCM, a black screen)
wire rom_keep = logo_en || rom_addr[21:19] != 3'd0;
always @(posedge clk) begin
	if (ioctl_isROMA)
		rom_enabled[0] <= 1'b1;
	if (ioctl_isROMB)
		rom_enabled[1] <= 1'b1;
	if (eject)
		rom_enabled <= 2'b00;
	if (ioctl_isBIOS)
		logo_en <= 1'b0;
end

// slot A of MiSTer: 9 is the disk drive
wire [3:0] slot_a = fdd ? 4'd9 : mapper_a;

// a change of the mappers or of the RAM resets the machine
reg [10:0] mappers_d = 11'd0;
reg mapper_reset = 1'b0;
always @(posedge clk) begin
	mappers_d <= { nextor, opll, ram_mapper, mapper_b, slot_a };
	mapper_reset <= mappers_d != { nextor, opll, ram_mapper, mapper_b, slot_a };
end

// img_sdc (see below): the mounts by slot
wire [7:0] sdc_img_mounted;
wire [63:0] sdc_img_size;

// Nextor: the first mount of a hard disk image (none before) resets the machine, so Nextor finds it: at
// the start of the core the firmware mounts the image after the machine started (Nextor had found no
// drive, a blank screen); another image later is a disk change, no reset
reg hd_present = 1'b0;
reg [3:0] hd_reset = 4'd0;
always @(posedge clk) begin
	if (hd_reset != 4'd0) hd_reset <= hd_reset - 4'd1;
	if (sdc_img_mounted[6]) begin
		hd_present <= sdc_img_size[31:0] != 32'd0 || sdc_img_size[63:32] != 32'd0;
		if (!hd_present && nextor && (sdc_img_size != 64'd0)) hd_reset <= 4'd15;
	end
end

wire msx_reset = reset || rom_active || ioctl_download || mapper_reset || eject || hd_reset != 4'd0;

wire [3:0] rtc_pb;          // the OCM-BIOS copy of the CMOS: its byte (below)
wire [7:0] rtc_pbyte;

// the RTC: the CMOS from the .eep of the core and the time of the board at the start, the CMOS
// the CPU writes back to the .eep
wire rtc_init_wr, rtc_init_adr0;
wire [7:0] rtc_init_data;
wire rtc_s_wr, rtc_s_adr0;
wire [7:0] rtc_s_dbo;
msx2_rtc #(.TIME_DELAY(RTC_TIME_DELAY)) u_rtc (
	.clk(clk),
	.start(rtc_start),
	.rtc_a(rtc_a),
	.rtc_do(rtc_do),
	.rtc_di(rtc_di),
	.rtc_cs(rtc_cs),
	.rtc_wr_n(rtc_wr_n),
	.wr(rtc_init_wr),
	.adr0(rtc_init_adr0),
	.data(rtc_init_data),
	.busy(),
	.s_wr(rtc_s_wr),
	.s_adr0(rtc_s_adr0),
	.s_dbo(rtc_s_dbo),
	.pb(rtc_pb),
	.pbyte(rtc_pbyte),
	.dbg(rtc_dbg)
);

// ------------------------------------------------------------------ input

wire [10:0] ps2_key;
msx_ps2_key ps2_key_conv (
	.clk(clk),
	.reset(reset),
	.scancode(kb_scancode),
	.scancode_upd(kb_scancode_upd),
	.ps2_key(ps2_key)
);

// the joysticks of MiSTer: 0 right, 1 left, 2 down, 3 up, 4 A, 5 B
wire [5:0] joy_a = { joy_l[7], joy_l[6], joy_l[1], joy_l[2], joy_l[3], joy_l[4] };
wire [5:0] joy_b = { joy_r[7], joy_r[6], joy_r[1], joy_r[2], joy_r[3], joy_r[4] };

// ------------------------------------------------------------------ the machine

// the disk drive (see below)
wire [31:0] sd_lba;
wire sd_rd, sd_wr, sd_ack, sd_buff_wr;
wire [8:0] sd_buff_addr;
wire [7:0] sd_buff_dout, sd_buff_din;

// img_sdc (see below), declared here for msx1
wire fdd_sdc_rd, fdd_sdc_wr, hd_sdc_rd, hd_sdc_wr;
wire [31:0] fdd_sector, hd_sector;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, fdd_byte_out_data, hd_byte_out_data;

// the physical drives: drive A (F slot 0) / B (F slot 7) on DS0 (1) / DS1 (2) or not (0). The size
// frames of a slot (an image, an eject) end it; CMD_IMG_PHYS comes after them.
reg [1:0] phys_a = 2'd0, phys_b = 2'd0;
always @(posedge clk) begin
	if (img_mounted[0])
		phys_a <= 2'd0;
	if (img_mounted[7])
		phys_b <= 2'd0;
	if (img_phys_wr && img_phys[15:8] == 8'd0)
		phys_a <= img_phys[1:0];
	if (img_phys_wr && img_phys[15:8] == 8'd7)
		phys_b <= img_phys[1:0];
end

wire [21:0] mem_addr;
wire [16:0] vram_addr;
wire vram_we_n;
wire [7:0] vram_dout;
wire [15:0] vram_din;
wire [15:0] msx_audio;
wire mem_we;
wire [7:0] mem_din, mem_dout, sram_dout;
assign mem_dout = rtc_patch ? rtc_pbyte : sram_dout;

// the OCM-BIOS sets the CMOS at its start from 21 bytes at 033FC6 of its image (its "RTC CODE" at
// 033F9C, the string at 033FE0): the reads of the bytes of banks 2 and 3 (033FCD..033FDA) get those of
// msx2_rtc, the CMOS of the .eep. Only for an image with that string (seen while it is loaded).
reg [7:0] ocm_rtc_sig = 8'd0;
wire [7:0] ocm_rtc_chr = file_addr[2:0] == 3'd0 ? "R" : file_addr[2:0] == 3'd1 ? "T" : file_addr[2:0] == 3'd2 ? "C" :
                         file_addr[2:0] == 3'd3 ? " " : file_addr[2:0] == 3'd4 ? "C" : file_addr[2:0] == 3'd5 ? "O" :
                         file_addr[2:0] == 3'd6 ? "D" : "E";
always @(posedge clk)
	if (ioctl_isBIOS && file_wr && file_addr[24:3] == 22'h033FE0 >> 3)
		ocm_rtc_sig[file_addr[2:0]] <= file_data == ocm_rtc_chr;
wire ocm_rtc = !logo_en && &ocm_rtc_sig;
assign rtc_pb = mem_addr[3:0] - 4'hD;              // 033FCD -> 0
wire rtc_patch = ocm_rtc && mem_addr >= 22'h033FCD && mem_addr <= 22'h033FDA;

wire cas_motor, cas_audio, cas_write;
wire tape_in_s;
kg_sync tape_in_sync (.clk(clk), .d(tape_in), .q(tape_in_s));
assign tape_out = cas_write;

msx2 #(.FDD_PHYS(FDD_PHYS)) msx2 (
	.clk(clk),
	.clk21(clk21),
	.ce_10m7(ce_10m7),
	.reset(msx_reset),
	.R(vdp_r), .G(vdp_g), .B(vdp_b),
	.hsync_n(vdp_hs_n), .vsync_n(vdp_vs_n),
	.vdp_blank(vdp_blank),
	.vdp_dhclk(vdp_dhclk),
	.vdp_dlclk(vdp_dlclk),
	.vdp_interlace(vdp_interlace),
	.vdp_pal(pal),
	.vdp_pal_auto(pal_auto),
	.vdp_v9958(v9958),
	.vram_addr(vram_addr),
	.vram_we_n(vram_we_n),
	.vram_dout(vram_dout),
	.vram_din(vram_din),
	.rtc_init_wr(rtc_init_wr),
	.rtc_init_adr0(rtc_init_adr0),
	.rtc_init_data(rtc_init_data),
	.rtc_s_wr(rtc_s_wr),
	.rtc_s_adr0(rtc_s_adr0),
	.rtc_s_dbo(rtc_s_dbo),
	.audio(msx_audio),
	.ps2_key(ps2_key),
	.joy0(joy_swap ? joy_b : joy_a),
	.joy1(joy_swap ? joy_a : joy_b),
	.ioctl_download(ioctl_download),
	.ioctl_index(8'd0),
	.ioctl_wr(file_wr),
	.ioctl_addr(file_addr[24:0]),
	.ioctl_dout(file_data),
	.ioctl_isROMA(ioctl_isROMA),
	.ioctl_isROMB(ioctl_isROMB),
	.ioctl_isBIOS(ioctl_isBIOS),
	.ioctl_wait(),
	.rom_enabled(rom_enabled),
	.cas_motor(cas_motor),
	.cas_out(cas_write),
	.cas_audio_in(tape_line ? tape_in_s : cas_audio),
	.slot_A(slot_a),
	.slot_B(mapper_b),
	.fdd_rom_en(fdd_rom_en),
	.mapper_info(),
	.mem_addr(mem_addr),
	.mem_we(mem_we),
	.mem_din(mem_din),
	.mem_dout(mem_dout),
	.logo_en(logo_en),
	.ram_mapper_en(ram_mapper),
	.opll_en(opll),
	// Nextor: the hard disk image is slot 6 of img_sdc (the firmware shares the slot numbers of the F and
	// FL items: 0 the floppy, 1..5 the FL items)
	.nextor_en(nextor),
	.ioctl_isNEXTOR(ioctl_isNEXTOR),
	.hd_mounted(sdc_img_mounted[6]),
	.hd_size(|sdc_img_size[63:32] ? 32'hFFFFFE00 : sdc_img_size[31:0]),
	.hd_wp(img_wp[6]),
	.hd_rd(hd_sdc_rd),
	.hd_wr(hd_sdc_wr),
	.hd_lba(hd_sector),
	.hd_busy(sdc_busy && sdc_slot == 3'd6),
	.hd_done(sdc_done && sdc_slot == 3'd6),
	.hd_byte_in_strobe(sdc_byte_in_strobe && sdc_slot == 3'd6),
	.hd_byte_addr(sdc_byte_addr),
	.hd_byte_in_data(sdc_byte_in_data),
	.hd_byte_out_data(hd_byte_out_data),
	// the disk drive: img_sdc and the copy of the image in the SRAM (msx_fdd_cache); a write protected
	// image (the readonly item or a read only file: IMG_WP) is so for the wd1793, which then does not write
	.img_mounted(sdc_img_mounted[0]),
	.img_size(sdc_img_size[31:0]),
	.img_wp(img_wp[0]),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.sd_din_strobe(1'b0),
	.fdd_phys_a(phys_a),
	.fdd_phys_b(phys_b),
	.fdd_in(fdd_in),
	.fdd_out(fdd_out)
);

// ------------------------------------------------------------------ the disk drive

wire fdd_aux_req, fdd_aux_we, fdd_aux_ack;
wire [21:0] fdd_aux_addr;
wire [7:0] fdd_aux_din;
wire tape_loading;
wire aux_ack;
wire [7:0] aux_dout;
// one request at a time, the lowest slot first (img_sdc takes the sector with the request): the
// floppy, then the hard disk
wire [31:0] sdc_sector = (fdd_sdc_rd || fdd_sdc_wr) ? fdd_sector : hd_sector;
wire [7:0] sdc_byte_out_data = sdc_slot == 3'd6 ? hd_byte_out_data : fdd_byte_out_data;

// no reset: a reset of the machine during a request leaves img_sdc to finish it (msx_fdd_cache
// waits for its end); a request that gets no answer ends after the timeout
img_sdc #(
	.OUT_LATENCY(3),
	.TIMEOUT(24'd8571429)   // 200 ms at 42.857 MHz
) sdc (
	.clk(clk),
	.reset(1'b0),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_data_wr(img_data_wr),
	.img_data_addr(img_data_addr),
	.img_data(img_data),
	.img_result_wr(img_result_wr),
	.img_result(img_result),
	.img_sum(img_sum),
	.img_q_wr(img_q_wr),
	.img_q_di(img_q_di),
	.img_q_ack(img_q_ack),
	.sdc_img_mounted(sdc_img_mounted),
	.sdc_img_size(sdc_img_size),
	.sdc_rd({ 1'b0, hd_sdc_rd, 5'd0, fdd_sdc_rd }),
	.sdc_wr({ 1'b0, hd_sdc_wr, 5'd0, fdd_sdc_wr }),
	.sdc_sector(sdc_sector),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_error(sdc_error),
	.sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(sdc_byte_out_data),
	.active(fdd_active)
);

msx_fdd_cache #(.BASE(22'h300000), .MAXSEC(1536)) fdd_cache (
	.clk(clk),
	.img_mounted(sdc_img_mounted[0]),
	.img_size(sdc_img_size[31:0]),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_lba(sd_lba),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_wr(sd_buff_wr),
	.sd_buff_din(sd_buff_din),
	.sdc_rd(fdd_sdc_rd),
	.sdc_wr(fdd_sdc_wr),
	.sdc_sector(fdd_sector),
	.sdc_busy(sdc_busy),
	.sdc_done(sdc_done),
	.sdc_error(sdc_error),
	.sdc_slot(sdc_slot),
	.sdc_byte_in_strobe(sdc_byte_in_strobe),
	.sdc_byte_addr(sdc_byte_addr),
	.sdc_byte_in_data(sdc_byte_in_data),
	.sdc_byte_out_data(fdd_byte_out_data),
	.pause(tape_loading),
	.aux_req(fdd_aux_req),
	.aux_we(fdd_aux_we),
	.aux_addr(fdd_aux_addr),
	.aux_din(fdd_aux_din),
	.aux_ack(fdd_aux_ack),
	.aux_dout(aux_dout),
	.filling(fdd_filling),
	.filled(fdd_filled)
);

// ------------------------------------------------------------------ the cassette

wire tape_aux_req, tape_aux_we, tape_aux_ack;
wire [21:0] tape_aux_addr;
wire [7:0] tape_aux_din;

msx_tape #(.BASE(22'h3E0000), .TAPE_SILENT(TAPE_SILENT), .TAPE_SYNC(TAPE_SYNC)) tape (
	.clk(clk),
	.ce_5m3(ce_5m3),
	.motor(cas_motor),
	.rewind(tape_rewind || ioctl_isCAS || reset || rom_active),
	.load(ioctl_isCAS),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.cas_out(cas_audio),
	.loading(tape_loading),
	.aux_req(tape_aux_req),
	.aux_we(tape_aux_we),
	.aux_addr(tape_aux_addr),
	.aux_din(tape_aux_din),
	.aux_ack(tape_aux_ack),
	.aux_dout(aux_dout)
);

// ------------------------------------------------------------------ the aux port: disk cache and cassette in turn

// a request is held until its ack; the owner is taken for one request, the other one first when both wait
reg aux_own = 1'b0;      // 0 the disk cache, 1 the cassette
reg aux_grant = 1'b0;
always @(posedge clk) begin
	if (!aux_grant) begin
		if (tape_aux_req && (!aux_own || !fdd_aux_req)) begin
			aux_own <= 1'b1;
			aux_grant <= 1'b1;
		end
		else if (fdd_aux_req) begin
			aux_own <= 1'b0;
			aux_grant <= 1'b1;
		end
	end
	else if (aux_ack)
		aux_grant <= 1'b0;
end
wire aux_req = aux_grant && (aux_own ? tape_aux_req : fdd_aux_req);
wire aux_we = aux_own ? tape_aux_we : fdd_aux_we;
wire [21:0] aux_addr = aux_own ? tape_aux_addr : fdd_aux_addr;
wire [7:0] aux_din = aux_own ? tape_aux_din : fdd_aux_din;
assign fdd_aux_ack = aux_ack && aux_grant && !aux_own;
assign tape_aux_ack = aux_ack && aux_grant && aux_own;

always @(posedge clk)
	audio <= msx_audio;

// ------------------------------------------------------------------ SRAM

msx_sram sram (
	.clk(clk),
	.addr(rom_active ? rom_addr[21:0] : mem_addr),
	.we(rom_active ? rom_wr && rom_keep : mem_we),
	.din(rom_active ? rom_data : mem_din),
	.dout(sram_dout),
	.aux_req(aux_req),
	.aux_we(aux_we),
	.aux_addr(aux_addr),
	.aux_din(aux_din),
	.aux_ack(aux_ack),
	.aux_dout(aux_dout),
	.vdp_dlclk(vdp_dlclk),
	.vdp_addr(vram_addr),
	.vdp_we_n(vram_we_n),
	.vdp_dout(vram_dout),
	.vdp_din(vram_din),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

endmodule
