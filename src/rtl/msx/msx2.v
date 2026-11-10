// karabas: msx1 of MSX1_MiSTer, renamed (the MSX2 machine of karabas-go-core-msx2); the VDP is
// the ESE-VDP (V9938 / V9958) of OCM-PLD instead of vdp18, its VRAM of 128 KB in the SRAM
// karabas: FDD_PHYS = 1: the physical floppy drives of the Karabas Go (see vy0010)
module msx2 #(parameter FDD_PHYS = 0)
(
	input         clk,
	input         clk21,         // karabas: the clock of the VDP, clk / 2 from the same PLL, rising edges together
	input         ce_10m7,
	input         reset,
	// karabas: the picture of the VDP at 15 kHz (DISPRESO 0), on clk21: R / G / B of 6 bits
	// widened to 8, the pixel enables of the VDP (dhclk 10.7 MHz, dlclk 5.37 MHz), the blanking
	output  [7:0] R,
	output  [7:0] G,
	output  [7:0] B,
	output        hsync_n,
	output        vsync_n,
	output        vdp_blank,
	output        vdp_dhclk,
	output        vdp_dlclk,
	output        vdp_interlace,
	input         vdp_pal,       // karabas: 50 Hz when vdp_pal_auto = 0
	input         vdp_pal_auto,  // karabas: 50 / 60 Hz from R9 (the BIOS, programs)
	input         vdp_v9958,     // karabas: the ID of the VDP in S#1: V9958 (MSX2+), else V9938 (MSX2)
	input   [1:0] turbo,         // karabas: the CPU at 3.58 (0), 5.37 (1) or 7.16 MHz (2, 3)
	// karabas: the VRAM port (clk21): the word address (bit 16 = the byte of a write), its write,
	// the 16-bit word read (both bytes: GRAPHIC 6 / 7 read two at once)
	output [16:0] vram_addr,
	output        vram_we_n,
	output  [7:0] vram_dout,
	input  [15:0] vram_din,
	// karabas: writes to the RTC from msx2_rtc (the CMOS and the time of the board at the start), one clock each
	input         rtc_init_wr,
	input         rtc_init_adr0,
	input   [7:0] rtc_init_data,
	// karabas: the writes rtc.v takes (msx2_rtc watches them: the CMOS to the mcu)
	output        rtc_s_wr,
	output        rtc_s_adr0,
	output  [7:0] rtc_s_dbo,
	output [15:0] audio,
	input  [10:0] ps2_key,
	input   [5:0] joy0,
	input   [5:0] joy1,
	input         ioctl_download,
	input   [7:0] ioctl_index,
	input         ioctl_wr,
	input  [24:0] ioctl_addr,
	input   [7:0] ioctl_dout,
	input         ioctl_isROMA,
	input         ioctl_isROMB,
	input         ioctl_isBIOS,  // karabas: the system ROM image of 512 KB (OCM-BIOS.DAT) to 000000
	output        ioctl_wait,
	input   [1:0] rom_enabled,
	output        cas_motor,
	output        cas_out,      // karabas: the cassette write data (PPI port C bit 5) for TAPE_OUT
	input         cas_audio_in,
	input   [3:0] slot_A,
	input   [3:0] slot_B,
	input         fdd_rom_en,   // karabas: the disk ROM of the VY-0010 on (0 for C-BIOS)
	output  [2:0] mapper_info,
	// karabas: the system ROMs, the RAM of slot 3 and the cartridges are in the SRAM of the board
	// (msx_sram), not in the block RAM and SDRAM of MiSTer; see the map at the end
	output [21:0] mem_addr,
	output        mem_we,
	output  [7:0] mem_din,
	input   [7:0] mem_dout,
	input         logo_en,       // karabas: C-BIOS (its slot layout, the logo ROM in slot 0 page 2), see msx2_slots
	input         ram_mapper_en, // karabas: the RAM of slot 3 is 512 KB with a memory mapper (ram_mapper.v)
	input         opll_en,       // karabas: the OPLL (MSX-MUSIC, jt2413) at the ports 7C-7D
	// karabas: slot 1 is the SD interface of MSX1FPGA for Nextor (nextor_sd.v) instead of cartridge A
	// and the disk drive; its ROM (fdd_rom_en = 0: FF) and the hard disk image of img_sdc
	input         nextor_en,
	input         ioctl_isNEXTOR,
	input         hd_mounted,
	input  [31:0] hd_size,
	input         hd_wp,         // karabas: the hard disk image is write protected (status bit 2 of nextor_sd)
	output        hd_rd,
	output        hd_wr,
	output [31:0] hd_lba,
	input         hd_busy,
	input         hd_done,
	input         hd_byte_in_strobe,
	input   [8:0] hd_byte_addr,
	input   [7:0] hd_byte_in_data,
	output  [7:0] hd_byte_out_data,
   
	input         img_mounted,
	input  [31:0] img_size,
	input         img_wp,
	output [31:0] sd_lba,
	output        sd_rd,
	output        sd_wr,
	input         sd_ack,
	input   [8:0] sd_buff_addr,
	input   [7:0] sd_buff_dout,
	output  [7:0] sd_buff_din,
	input         sd_buff_wr,
	input         sd_din_strobe,
	// karabas: the physical floppy drives (FDD_PHYS): drive A / B on DS0 (1) / DS1 (2) or not (0), the pins
	input   [1:0] fdd_phys_a,
	input   [1:0] fdd_phys_b,
	input   [3:0] fdd_in,
	output  [7:0] fdd_out
);

// karabas: the wires used before their declaration below (Quartus takes it, XST does not)
wire u1_2_q;
wire vdp_int_n;
wire vdp_n, psg_n, ppi_n, cen_n;
wire [7:0] d_from_kb;
wire [7:0] d_from_psg, psg_ioa, psg_iob;
wire [7:0] d_from_slots;
wire [15:0] sound_slots; 
wire [9:0] ay_ch_mix;
wire [7:0] d_from_vdp;
wire [7:0] d_from_8255;
wire [7:0] ppi_out_a, ppi_out_c;
wire CS1_n, CS01_n, CS12_n, CS2_n;
wire [3:0] SLTSL_n;
// karabas: slot 1 off for Nextor; slot 3 of slots.v is the RAM of 3-0 only (msx2_slots)
wire ram_sel;
wire [3:0] slots_sltsl_n = { ~ram_sel, SLTSL_n[2], SLTSL_n[1] | nextor_en, SLTSL_n[0] };
// karabas: the memory of the slots goes to the SRAM (see the map below)
wire [24:0] sdram_addr;
wire        sdram_rd;
wire        ram_we;

//  -----------------------------------------------------------------------------
//  -- Audio MIX
//  -----------------------------------------------------------------------------
wire  [9:0] audioPSG = ay_ch_mix + {keybeep,5'b00000} + {(cas_audio_in & ~cas_motor),4'b0000};                                        
wire [15:0] fm       = {2'b0, audioPSG, 4'b0000};
// karabas: the OPLL is a third term (a note of jt2413 is +-1.4K, a tone of the PSG 0..4K here): one
// bit more, the same clipping at +-2^14 (the case of the array literal of SystemVerilog was on 3
// bits, element 0 of '{...} is the last one)
wire signed [15:0] opll_snd;
wire [17:0] audio_mix = {{2{sound_slots[15]}}, sound_slots} + {{2{fm[15]}}, fm} +
                        (opll_en ? {{2{opll_snd[15]}}, opll_snd} : 18'd0);
reg [15:0] compr;
always @* begin
	case (audio_mix[17:14])
		4'b0000: compr = {1'b0, audio_mix[13:0], 1'b0};
		4'b1111: compr = {1'b1, audio_mix[13:0], 1'b0};
		default: compr = audio_mix[17] ? 16'h8000 : 16'h7FFF;
	endcase
end
assign audio = compr;

//  -----------------------------------------------------------------------------
//  -- Clock generation
//  -----------------------------------------------------------------------------
wire clk_en_3m58_p, clk_en_3m58_n;
cv_clock clock
(
	.clk_i(clk),
	.clk_en_10m7_i(ce_10m7),
	.reset_n_i(~reset),
	.clk_en_3m58_p_o(clk_en_3m58_p),
	.clk_en_3m58_n_o(clk_en_3m58_n)
);

// karabas: the clock of the CPU. turbo 0: the 3.58 MHz of cv_clock, as before. Turbo: a half period
// of 4 (5.37 MHz) or 3 clocks (7.16 MHz), the rising (p) and falling (n) enables in turn; an I/O cycle
// and an access to slot 1 or 2 (cartridges, the disk drive, Nextor) run at 3.58 MHz (a half period
// of 6): the devices there take their strobes on the enables of 3.58 MHz (the PSG, the mappers, SCC).
// The other users of clk_en_3m58 (the PSG, the RTC, the OPLL, the slots) stay on it.
reg  [2:0] cpu_cnt = 3'd0;
reg        cpu_ph = 1'b0;     // 0: a p next, 1: an n next
reg        cpu_gp = 1'b0, cpu_gn = 1'b0;
wire       cpu_slow;
wire [2:0] cpu_half = cpu_slow ? 3'd5 : turbo == 2'd1 ? 3'd3 : 3'd2;
always @(posedge clk) begin
	cpu_gp <= 1'b0;
	cpu_gn <= 1'b0;
	if (cpu_cnt >= cpu_half) begin
		cpu_cnt <= 3'd0;
		cpu_ph <= ~cpu_ph;
		if (cpu_ph) cpu_gn <= 1'b1; else cpu_gp <= 1'b1;
	end
	else
		cpu_cnt <= cpu_cnt + 3'd1;
end
wire       cpu_p = turbo == 2'd0 ? clk_en_3m58_p : cpu_gp;
wire       cpu_n = turbo == 2'd0 ? clk_en_3m58_n : cpu_gn;

//  -----------------------------------------------------------------------------
//  -- T80 CPU
//  -----------------------------------------------------------------------------
wire [15:0] a;
wire [7:0] d_to_cpu, d_from_cpu;
wire mreq_n, wr_n, m1_n, iorq_n, rd_n, rfrsh_n, wait_n; 
t80pa #(.Mode(0)) T80
(
	.RESET_n(~reset),
	.CLK(clk),
	.CEN_p(cpu_p), // karabas: turbo
	.CEN_n(cpu_n),
	.WAIT_n(wait_n),
	.INT_n(vdp_int_n),
	.NMI_n(1),
	.BUSRQ_n(1),
	.M1_n(m1_n),
	.MREQ_n(mreq_n),
	.IORQ_n(iorq_n),
	.RD_n(rd_n),
	.WR_n(wr_n),
	.RFSH_n(rfrsh_n),
	.HALT_n(), // karabas: an output of t80pa, upstream tied it to 1
	.BUSAK_n(),
	.A(a),
	.DI(d_to_cpu),
	.DO(d_from_cpu)
);

//  -----------------------------------------------------------------------------
//  -- WAIT
//  -----------------------------------------------------------------------------
wire exwait_n = 1;
reg wait_n2;
ls74 u1_1
(
   .clr(exwait_n),
   .pre(u1_2_q),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(cpu_p),        // karabas: the clock of the CPU (turbo)
   .d(m1_n),
   .q(wait_n)
);

ls74 u1_2
(
   .clr(1),
   .pre(exwait_n),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(cpu_p),        // karabas: the clock of the CPU (turbo)
   .d(wait_n),
   .q(u1_2_q)
);
//  -----------------------------------------------------------------------------
//  -- ROM
//  -----------------------------------------------------------------------------
// karabas: the ROMs of the expanded slots 0 and 3 (MSX2, the layout of OCM) are in the SRAM,
// msx2_slots finds them; the expansion registers at FFFF are there too
wire        exp_rd, rom_sel, erm_sel;
wire  [7:0] exp_q;
wire [21:0] rom_addr;
msx2_slots msx2_slots
(
	.clk(clk),
	.reset(reset),
	.addr(a),
	.din(d_from_cpu),
	.wr_n(wr_n),
	.ppi_a(ppi_out_a),
	.sltsl_n(SLTSL_n),
	.cbios(logo_en),
	.music_en(opll_en),
	.exp_rd(exp_rd),
	.exp_q(exp_q),
	.rom_sel(rom_sel),
	.rom_addr(rom_addr),
	.ram_sel(ram_sel),
	.erm_sel(erm_sel)
);

//  -----------------------------------------------------------------------------
//  -- karabas: the RTC (RP5C01) at the ports B4 (register) and B5 (data), rtc.v of OCM-PLD
//  -----------------------------------------------------------------------------
// its request is a pulse of one clock at the start of the I/O cycle, as for the VDP
wire       rtc_cs = ~iorq_n & m1_n & (a[7:1] == 7'b1011010) & (~rd_n | ~wr_n);
reg        rtc_cs_d = 1'b0;
always @(posedge clk) rtc_cs_d <= rtc_cs;
wire       rtc_sel = ~iorq_n & m1_n & (a[7:1] == 7'b1011010);
wire [7:0] d_from_rtc;
wire       rtc_req = (rtc_cs & ~rtc_cs_d) | rtc_init_wr;
wire       rtc_wrt = rtc_init_wr | ~wr_n;
assign rtc_s_wr   = rtc_req & rtc_wrt;
assign rtc_s_adr0 = rtc_init_wr ? rtc_init_adr0 : a[0];
assign rtc_s_dbo  = rtc_init_wr ? rtc_init_data : d_from_cpu;
rtc rtc
(
	.clk21m(clk),
	.reset(reset),
	.clkena(clk_en_3m58_p),
	.req(rtc_req),
	.ack(),
	.wrt(rtc_wrt),
	.adr(rtc_init_wr ? { 15'd0, rtc_init_adr0 } : a),
	.dbi(d_from_rtc),
	.dbo(rtc_s_dbo)
);

//  -----------------------------------------------------------------------------
//  -- karabas: the ESE-VDP (V9938 / V9958 of OCM-PLD) at the ports 98-9B, on clk21
//  -----------------------------------------------------------------------------
// The VDP takes a request as a pulse of one clk21 (OCM: req of its bus): the start of an I/O read
// or write of 98-9B, found on clk21. The Z80 holds the address, the data and RD / WR for many
// clocks of clk21 (a T-state is 6), so they are sampled there as they are.
wire       vdp_cs = ~iorq_n & m1_n & (a[7:2] == 6'b100110) & (~rd_n | ~wr_n);
reg        vdp_cs_q = 1'b0, vdp_cs_d = 1'b0;
reg        vdp_wrt = 1'b0;
reg [15:0] vdp_adr = 16'd0;
reg  [7:0] vdp_dbo = 8'd0;
always @(posedge clk21) begin
	vdp_cs_q <= vdp_cs;
	vdp_cs_d <= vdp_cs_q;
	vdp_wrt <= ~wr_n;
	vdp_adr <= a;
	vdp_dbo <= d_from_cpu;
end
wire       vdp_req = vdp_cs_q & ~vdp_cs_d;
wire       vdp_sel = ~iorq_n & m1_n & (a[7:2] == 6'b100110);
wire [5:0] vdp_r, vdp_g, vdp_b;
wire       vdp_oe_n;

vdp vdp
(
	.clk21m(clk21),
	.reset(reset),
	.req(vdp_req),
	.ack(),
	.wrt(vdp_wrt),
	.adr(vdp_adr),
	.dbi(d_from_vdp),
	.dbo(vdp_dbo),
	.int_n(vdp_int_n),
	.pramoe_n(vdp_oe_n),
	.pramwe_n(vram_we_n),
	.pramadr(vram_addr),
	.pramdbi(vram_din),
	.pramdbo(vram_dout),
	.vdpspeedmode(1'b0),
	.ratiomode(3'b000),
	.centeryjk_r25_n(1'b1),
	.pvideor(vdp_r),
	.pvideog(vdp_g),
	.pvideob(vdp_b),
	.pvideohs_n(hsync_n),
	.pvideovs_n(vsync_n),
	.pvideocs_n(),
	.pvideodhclk(vdp_dhclk),
	.pvideodlclk(vdp_dlclk),
	.blank_o(vdp_blank),
	.interlacemode(vdp_interlace),
	.dispreso(1'b0),                 // 15 kHz: the frame buffer takes the lines as the VDP makes them
	.ntsc_pal_type(vdp_pal_auto),
	.forced_v_mode(vdp_pal),
	.legacy_vga(1'b0),
	.vga_int_field(1'b0),
	.spmaxspr(1'b0),                 // 8 sprites on a line, as the real VDP
	.vdp_id(vdp_v9958 ? 5'b00010 : 5'b00000),
	.offset_y(7'b0010011)            // the default of OCM (swioports)
);
assign R = {vdp_r, vdp_r[5:4]};
assign G = {vdp_g, vdp_g[5:4]};
assign B = {vdp_b, vdp_b[5:4]};

//  -----------------------------------------------------------------------------
//  -- IO Decoder
//  -----------------------------------------------------------------------------
io_decoder io_decoder
(
	.addr(a),
	.iorq_n(iorq_n),
	.m1_n(m1_n),
	.vdp_n(vdp_n),
	.psg_n(psg_n),
	.ppi_n(ppi_n),
	.cen_n(cen_n)
);

//  -----------------------------------------------------------------------------
//  -- 82C55 PPI
//  -----------------------------------------------------------------------------
wire keybeep = ppi_out_c[7];
assign cas_motor =  ppi_out_c[4];
assign cas_out = ppi_out_c[5];  // karabas: see the port
jt8255 PPI
(
	.rst(reset),
	.clk(clk),
	.addr(a[1:0]),
	.din(d_from_cpu),
	.dout(d_from_8255),
	.rdn(rd_n),
	.wrn(wr_n),
	.csn(ppi_n),
	
	.porta_din(8'h0),
	.portb_din(d_from_kb),
	.portc_din(8'h0),

	.porta_dout(ppi_out_a),
	.portb_dout(),
   .portc_dout(ppi_out_c)
 );

//  -----------------------------------------------------------------------------
//  -- Memory mapper
//  -----------------------------------------------------------------------------
memory_mapper memory_mapper
(
	.clk(clk), // karabas
	.reset(reset),
	.addr(a),
	.ppi_n(ppi_n),
	.RAM_CS(ppi_out_a),
	.mreq_n(mreq_n),
	.rfrsh_n(rfrsh_n),
	.rd_n(rd_n),
	.SLTSL_n(SLTSL_n),
	.CS1_n(CS1_n),
	.CS01_n(CS01_n),
	.CS12_n(CS12_n),
	.CS2_n(CS2_n)
); 

//  -----------------------------------------------------------------------------
//  -- karabas: the memory mapper of the RAM of slot 3 (ports FC-FF)
//  -----------------------------------------------------------------------------
wire [4:0] ram_segment;
wire       ram_mapper_n;
wire [7:0] d_from_ram_mapper;
ram_mapper ram_mapper
(
	.clk(clk),
	.reset(reset),
	.en(ram_mapper_en),
	.io_addr(a[7:0]),
	.iorq_n(iorq_n),
	.m1_n(m1_n),
	.wr_n(wr_n),
	.din(d_from_cpu),
	.page(a[15:14]),
	.segment(ram_segment),
	.sel_n(ram_mapper_n),
	.dout(d_from_ram_mapper)
);

//  -----------------------------------------------------------------------------
//  -- karabas: Nextor in slot 1 (the SD interface of MSX1FPGA on a hard disk image)
//  -----------------------------------------------------------------------------
wire       nextor_sel, nextor_mem, nextor_we;
wire [2:0] nextor_bank;
wire [7:0] nextor_q;
nextor_sd nextor
(
	.clk(clk),
	.reset(reset),
	.rom_en(fdd_rom_en),
	.sltsl_n(SLTSL_n[1] | ~nextor_en),
	.addr(a),
	.din(d_from_cpu),
	.rd_n(rd_n),
	.wr_n(wr_n),
	.sel(nextor_sel),
	.dout(nextor_q),
	.mem_sel(nextor_mem),
	.mem_bank(nextor_bank),
	.mem_we(nextor_we),
	.mem_dout(mem_dout),
	.img_mounted(hd_mounted),
	.img_size(hd_size),
	.img_wp(hd_wp),
	.hd_rd(hd_rd),
	.hd_wr(hd_wr),
	.hd_lba(hd_lba),
	.hd_busy(hd_busy),
	.hd_done(hd_done),
	.hd_byte_in_strobe(hd_byte_in_strobe),
	.hd_byte_addr(hd_byte_addr),
	.hd_byte_in_data(hd_byte_in_data),
	.hd_byte_out_data(hd_byte_out_data)
);

//  -----------------------------------------------------------------------------
//  -- karabas: the OPLL (YM2413, MSX-MUSIC) at the ports 7C (register) and 7D (data), write only
//  -----------------------------------------------------------------------------
wire opll_cs_n = ~(opll_en & ~iorq_n & m1_n & a[7:1] == 7'b0111110);
jt2413 opll
(
	.rst(reset),
	.clk(clk),
	.cen(clk_en_3m58_p),
	.din(d_from_cpu),
	.addr(a[0]),
	.cs_n(opll_cs_n),
	.wr_n(wr_n),
	.snd(opll_snd),
	.sample()
);

// karabas: the MSX-MUSIC ROM is in slot 0-2 now (msx2_slots), the fake header of the MSX1 core
// (APRLOPLL in slot 2) is gone

// karabas: the kanji ROM, JIS level 1 at the ports D8 (address bits 10..5) / D9 (bits 16..11, the
// reads of the font), level 2 at DA / DB: a write sets the character and clears the counter, a read
// of D9 / DB gives byte <counter> (0..31) of the character and steps the counter. The font is 256 KB
// at 040000 of the SRAM (OCM-BIOS.DAT; level 2 from 060000), read through the memory port in the
// I/O cycle. D8 / DA read FF.
wire        kanji_sel = ~iorq_n & m1_n & (a[7:2] == 6'b110110);
wire        kanji_rd  = kanji_sel & ~rd_n & a[0];
reg  [11:0] kanji_c1 = 12'd0, kanji_c2 = 12'd0;    // the characters of level 1 / 2
reg   [4:0] kanji_n1 = 5'd0, kanji_n2 = 5'd0;      // their counters
reg         kanji_wr_d = 1'b0, kanji_rd_d = 1'b0, kanji_l2 = 1'b0;
always @(posedge clk) begin
	kanji_wr_d <= kanji_sel & ~wr_n;
	kanji_rd_d <= kanji_rd;
	if (kanji_rd) kanji_l2 <= a[1];
	if (reset) begin
		kanji_c1 <= 12'd0; kanji_c2 <= 12'd0; kanji_n1 <= 5'd0; kanji_n2 <= 5'd0;
	end
	else if (kanji_sel & ~wr_n & ~kanji_wr_d) begin
		case (a[1:0])
			2'd0: begin kanji_c1[5:0]  <= d_from_cpu[5:0]; kanji_n1 <= 5'd0; end
			2'd1: begin kanji_c1[11:6] <= d_from_cpu[5:0]; kanji_n1 <= 5'd0; end
			2'd2: begin kanji_c2[5:0]  <= d_from_cpu[5:0]; kanji_n2 <= 5'd0; end
			default: begin kanji_c2[11:6] <= d_from_cpu[5:0]; kanji_n2 <= 5'd0; end
		endcase
	end
	else if (kanji_rd_d & ~kanji_rd) begin    // the end of a read
		if (kanji_l2) kanji_n2 <= kanji_n2 + 5'd1;
		else kanji_n1 <= kanji_n1 + 5'd1;
	end
end
wire [21:0] kanji_addr = a[1] ? { 4'b0001, 1'b1, kanji_c2, kanji_n2 } : { 4'b0001, 1'b0, kanji_c1, kanji_n1 };

// karabas: turbo: the cycles at 3.58 MHz (see the clock of the CPU)
assign cpu_slow = ~iorq_n | ~SLTSL_n[1] | ~SLTSL_n[2];

//  -----------------------------------------------------------------------------
//  -- CPU data multiplex
//  -----------------------------------------------------------------------------
// karabas: the expansion registers, the ROMs of slots 0 and 3 (msx2_slots), slot 0 and 3 read FF
// where nothing is; the RAM of 3-0 through slots.v (its slot 3)
assign d_to_cpu = kanji_rd               ? mem_dout : // karabas
                  (kanji_sel & ~rd_n)    ? 8'hFF :    // karabas
                  exp_rd                 ? exp_q :
                  rom_sel                ? mem_dout :
                  ~(SLTSL_n[0])          ? 8'hFF :
                  nextor_sel             ? nextor_q : // karabas
                  ~(SLTSL_n[1])          ? d_from_slots:
                  ~(SLTSL_n[2])          ? d_from_slots:
                  ram_sel                ? d_from_slots:
                  ~(SLTSL_n[3])          ? 8'hFF :
                  (vdp_sel & ~rd_n)      ? d_from_vdp : // karabas: the ports 98-9B of the ESE-VDP
                  ~(psg_n | rd_n)        ? d_from_psg :
                  ~(ppi_n | rd_n)        ? d_from_8255 :
                  ~(ram_mapper_n | rd_n) ? d_from_ram_mapper : // karabas
                  (rtc_sel & ~rd_n)      ? d_from_rtc : // karabas
                                           8'hFF;

//  -----------------------------------------------------------------------------
//  -- Keyboard decoder
//  -----------------------------------------------------------------------------
keyboard msx_key
(
	.reset_n_i(~reset),
	.clk_i(clk),
	.ps2_code_i(ps2_key),
	.kb_addr_i(ppi_out_c[3:0]),
	.kb_data_o(d_from_kb)
);

//  -----------------------------------------------------------------------------
//  -- Sound AY-3-8910
//  -----------------------------------------------------------------------------
wire [5:0] joy_a = psg_iob[4] ? 6'b111111 : {~joy0[5], ~joy0[4], ~joy0[0], ~joy0[1], ~joy0[2], ~joy0[3]};
wire [5:0] joy_b = psg_iob[5] ? 6'b111111 : {~joy1[5], ~joy1[4], ~joy1[0], ~joy1[1], ~joy1[2], ~joy1[3]};
wire [5:0] joyA = joy_a & {psg_iob[0], psg_iob[1], 4'b1111};
wire [5:0] joyB = joy_b & {psg_iob[2], psg_iob[3], 4'b1111};
assign psg_ioa = {cas_audio_in,1'b0, psg_iob[6] ? joyB : joyA};

wire u21_1_q;
ls74 u21_1
(
   .clr(!psg_n),
   .pre(1),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(clk_en_3m58_p),
   .d(!psg_n),
   .q(u21_1_q)
);

wire u21_2_q;
ls74 u21_2
(
   .clr(!psg_n),
   .pre(1),
   .clk(clk), // karabas: clk_en_3m58_p was the clock, see ls74.v
   .ce(clk_en_3m58_p),
   .d(u21_1_q),
   .q(u21_2_q)
);

wire psg_e = !(!u21_2_q | clk_en_3m58_p) | psg_n;
wire psg_bc   = !(a[0] | psg_e);
wire psg_bdir = !(a[1] | psg_e);
jt49_bus PSG
(
	.rst_n(~reset),
	.clk(clk),
	.clk_en(clk_en_3m58_n),
	.bdir(psg_bdir),
	.bc1(psg_bc),
	.din(d_from_cpu),
	.sel(0),
	.dout(d_from_psg),
	.sound(ay_ch_mix),
	.A(),
	.B(),
	.C(),
	.IOA_in(psg_ioa),
	.IOA_out(),
	.IOB_in(8'hFF),
	.IOB_out(psg_iob)
);

//  -----------------------------------------------------------------------------
//  -- SLOTS
//  -----------------------------------------------------------------------------
slots #(.FDD_PHYS(FDD_PHYS)) slots // karabas: FDD_PHYS
(
	.clk(clk),
	.clk_en(clk_en_3m58_p),
	.reset(reset),
	.addr(a),
	.wr_n(wr_n),
	.rd_n(rd_n),
	.CS1_n(CS1_n),    
	.CS2_n(CS2_n),
	.CS12_n(CS12_n),
	.SLTSL_n(slots_sltsl_n), // karabas
	.d_from_cpu(d_from_cpu),
	.d_to_cpu(d_from_slots),
	.sound(sound_slots),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_isROMA(ioctl_isROMA),
	.ioctl_isROMB(ioctl_isROMB),
	.ioctl_wait(ioctl_wait),
	.sdram_dout(mem_dout),
	.sdram_din(),
	.sdram_addr(sdram_addr),
	.sdram_we(),
	.sdram_rd(sdram_rd),
	.sdram_ready(1'b1),
	.sdram_size(2'b01),
	.ram_we(ram_we),
	.slot_A(slot_A),
	.slot_B(slot_B),
	.fdd_rom_en(fdd_rom_en),
	.mapper_info(mapper_info),
	.rom_enabled(rom_enabled),
	.img_mounted(img_mounted),
	.img_size(img_size),
	.img_wp(img_wp),
	.sd_lba(sd_lba),
	.sd_rd(sd_rd),
	.sd_wr(sd_wr),
	.sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr),
	.sd_buff_dout(sd_buff_dout),
	.sd_buff_din(sd_buff_din),
	.sd_buff_wr(sd_buff_wr),
	.sd_din_strobe(sd_din_strobe),
	.fdd_phys_a(fdd_phys_a),     // karabas: the physical floppy drives
	.fdd_phys_b(fdd_phys_b),
	.fdd_in(fdd_in),
	.fdd_out(fdd_out)
);

//  -----------------------------------------------------------------------------
//  -- karabas: the SRAM map (byte addresses)
//  -----------------------------------------------------------------------------
// 000000-07FFFF the system ROMs, laid out as OCM-BIOS.DAT (msx2_slots): 000000 the ESE-RAM of OCM
//               (128 KB; here the Nextor ROM of nextor_sd: bank n at 000000 + n * 16 KB, RAM in
//               7000-7AFF of bank 7), 020000 main, 028000 XBASIC, 02C000 MSX-MUSIC, 030000 sub +
//               kanji BASIC, 03C000 free / the logo of C-BIOS, 040000 the kanji font (256 KB)
// 080000 RAM 512 KB of slot 3-0 (ram_mapper, segment n at 080000 + n * 16 KB; without the mapper
//        64 KB, segments 0-3)
// 100000 cartridge B, 200000 cartridge A, 1 MB each
// 300000 the disk image (msx_fdd_cache, 768 KB), 3C0000 the VRAM 128 KB (msx_sram, the VDP port),
// 3E0000 the tape (msx_tape, 128 KB)
// The cartridges are at the addresses of the MiSTer SDRAM, bit 22 = slot A; a ROM file over 1 MB
// is cut (the rest is not written). The SRAM is read all the time (msx_sram); a write is a level
// here, msx_sram writes once at its rising edge.
wire [21:0] cart_addr = {sdram_addr[22] ? 2'b10 : 2'b01, sdram_addr[19:0]};
wire        ioctl_cart = ioctl_isROMA | ioctl_isROMB;
// the BIOS file: the image of 512 KB (OCM-BIOS.DAT), from 000000
wire        ioctl_mem = (ioctl_isBIOS & ioctl_addr[24:19] == 6'd0) | (ioctl_cart & ioctl_addr[24:20] == 5'd0) |
                        (ioctl_isNEXTOR & ioctl_addr[24:17] == 8'd0);

assign mem_addr = ioctl_isBIOS            ? {3'b000, ioctl_addr[18:0]} :
                  ioctl_isNEXTOR          ? {5'b00000, ioctl_addr[16:0]} :
                  ioctl_isROMA            ? {2'b10, ioctl_addr[19:0]} :
                  ioctl_isROMB            ? {2'b01, ioctl_addr[19:0]} :
                  kanji_rd                ? kanji_addr : // karabas
                  rom_sel                 ? rom_addr :
                  ram_sel                 ? {3'b001, ram_segment, a[13:0]} :
                  nextor_mem              ? {5'b00000, nextor_bank, a[13:0]} :
                                            cart_addr;
assign mem_we  = ioctl_download ? ioctl_wr & ioctl_mem : ram_we | nextor_we;
assign mem_din = ioctl_download ? ioctl_dout : d_from_cpu;

endmodule
