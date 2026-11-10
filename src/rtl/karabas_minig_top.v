`timescale 1ns / 1ps
`default_nettype wire

/*
 MSX2 core for Karabas Mini rev.G (HDMI, PCM5102, PCM1808).

 The machine is msx2 (MiSTer MSX1 with the ESE-VDP of OCM-PLD, rtl/msx, see docs/UPSTREAM.md) in
 msx_system; all file work goes through the firmware: the ROMs of core.json (C-BIOS) by the ROM
 loader, the cartridges and a BIOS file by the FL items of the OSD (the file loader of kg_mcu,
 FILELOAD_SLOT), see msx_system.v.

 Clocks: one PLL, VCO 600 MHz (50 * 12): clk_sys 42.857 MHz (/14, 12 x 3.57 MHz: the machine, the
 SRAM, the MCU link, audio, the SDRAM of the frame buffer), clk21 21.43 MHz (/28, the VDP: its rising
 edges with every other one of clk_sys), clk_vga 25.0 MHz (/24, 640 x 480: msx2_fb reads its frame
 buffer, the OSD, HDMI), clk_8 8.0 MHz (/75, FT_CLK_OUT: the FT812 must always have its clock, see
 karabas-go-notes ft-clk-out-required). HDMI: kg_dcm 5 x clk_vga and its inverse.
 Video: the 15 kHz picture of the VDP through the frame buffer in the SDRAM (msx2_fb) to 640 x 480 at
 60 Hz. FLASH_CS_N (T3) is the /CS of the SDRAM on Mini G2 (on rev G the pin goes to the config flash,
 never populated): 0.

 Soft switches (the index of the item in the osd of core_minig.json, file items included; the
 pages of the menu do not change it; separators and the page entry are not registers):
   main page: 0 Cart A (FL 4)   1 Disk A (F 0)   2 HDD (F 6, Nextor)   3 Cart B (FL 1)
   4 Tape (FL 3, .cas)   5 Tape rewind   6 -   7 Video (PAL / NTSC)   8 Joysticks (swap)   9 -
   10 Machine (page 1)   11 Reset   12 Eject carts
   page Machine: 13 Slot 1 (cartridge A / disk drive / Nextor)   14 Slot 1 ROM (on / off: the disk
   ROM or the Nextor ROM reads FF, for tests under C-BIOS)   15 Mapper A   16 Mapper B   17 -
   18 RAM (512K mapper / 64K)   19 FM (MSX-MUSIC on / off)   20 Tape input (CAS file / TAPE_IN)
   21 VDP (V9958, MSX2+ / V9938, MSX2), pinned by "index" in core.json; BIOS (FL 2), Nextor ROM (FL 5)
   7 Video: 0 Auto (R9 of the VDP: the BIOS), 1 PAL 50 Hz, 2 NTSC 60 Hz
*/

module karabas_minig_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,

	output wire [20:0] MA,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N,
	output wire [1:0] MRD_N,

	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

	output wire SD_CS_N,
	output wire SD_CLK,
	output wire SD_DI,
	input wire SD_DO,
	input wire SD_DET_N,

	input wire [7:0] VGA_R,
	input wire [7:0] VGA_G,
	input wire [7:0] VGA_B,
	input wire VGA_HS,
	input wire VGA_VS,

	output wire [3:0] TMDS_P,
	output wire [3:0] TMDS_N,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_DE,
	output wire FT_CLK_OUT,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	output wire TAPE_OUT,
	input wire TAPE_IN,

	output wire DAC_BCK,
	output wire DAC_WS,
	output wire DAC_DAT,

	output wire ADC_CLK,
	inout wire ADC_BCK,
	inout wire ADC_LRCK,
	input wire ADC_DOUT,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	inout wire [5:0] MCU_IO, // [0] burst cs_n, [1] burst ready, [2] sd2 cs_n, [3] ft cs_n

	output wire MIDI_TX,

	output wire ESP32_SPI_CS_N,
	input wire ESP32_PCM_BCK,
	input wire ESP32_PCM_RLCK,
	input wire ESP32_PCM_DAT,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP32_SPI_CS_N = 1'b1;
assign MIDI_TX = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign FLASH_CS_N = 1'b0;  // the SDRAM /CS of Mini G2, see above
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign MRD_N = 2'b00;  // SRAM /OE: always on, msx_sram drives MD only with /WE

// ------------------------------------------------------------------ clocks

wire clk_sys, clk_vga, clk_8, clk21;
wire locked, lockedx5, areset;
wire clk_hdmi, clk_hdmi_n;

wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(12),
	.CLKOUT0_DIVIDE(14),
	.CLKOUT1_DIVIDE(24),
	.CLKOUT2_DIVIDE(75),
	.CLKOUT3_DIVIDE(28),
	.BUFG_MASK(6'b001111)
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_sys = pll_clk[0];
assign clk_vga = pll_clk[1];
assign clk_8 = pll_clk[2];
assign clk21 = pll_clk[3];
assign areset = ~locked;

kg_dcm #(
	.CLKIN_PERIOD(40.0),
	.CLKFX_MULTIPLY(5),
	.CLKFX_DIVIDE(1)
) pllx5 (
	.clk_in(clk_vga),
	.rst(areset),
	.clk_fx(clk_hdmi),
	.clk_fx180(clk_hdmi_n),
	.clk_0(),
	.locked(lockedx5)
);

// the clock of the FT812
ODDR2 oddr_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8), .C1(~clk_8), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

// MCU_SCK on a global buffer (as tsconf and the menu: on local routing the flip-flops of the SPI
// receiver had several ns of clock skew); the FT812 and SD2 get the IBUFG output (a BUFG drives no pad)
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck (.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck (.I(mcu_sck_ibufg), .O(mcu_sck));

wire mcu_burst_ready;
assign MCU_IO[1] = mcu_burst_ready;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

wire [7:0] kb_scancode;
wire kb_scancode_upd;
wire [12:0] joy_l, joy_r;
wire rom_active, rom_wr;
wire [31:0] rom_addr;
wire [7:0] rom_data;
wire file_reset, file_active, file_wr;
wire [7:0] file_slot, file_data;
wire [31:0] file_addr;
wire [15:0] softsw_command, osd_command;
wire mcu_busy;
wire dvi_only;
wire ft_cs_n, ft_mosi, ft_spi_on, sd2_cs_n, sd2_mosi;
wire [7:0] img_mounted, img_data, img_result;
wire [63:0] img_size;
wire img_data_wr, img_result_wr, img_q_wr, img_q_ack, img_phys_wr;
wire [15:0] img_phys;
wire [7:0] img_wp;
wire [8:0] img_data_addr;
wire [15:0] img_sum;
wire [23:0] img_q_di;

kg_mcu #(
	.BURST_MAX_MHZ(32),  // Rev.G has MCU_SCK on a global clock pin
	.CS_FILTER(3),
	.ENABLE_RTC(0),
	.ENABLE_UART(0),
	.ENABLE_MATRIX(0),
	.ENABLE_DEBUG(0),
	.ENABLE_IMG(1),      // the disk drive: the .dsk image of the F item
	.ENABLE_IMG_WP(1),   // write protected images (caps bit 5, IMG_WP)
	.ENABLE_FILE(1),
	.FILE_CMDS(0),       // the ioctl commands of the FL items
	.FILE_WR_EACH(1),
	.FILE_TO_ROM(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(1)
) mcu (
	.CLK(clk_sys),
	.N_RESET(~areset),

	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(mcu_sck),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),
	.MCU_BURST_CS_N(MCU_IO[0]),
	.MCU_BURST_READY(mcu_burst_ready),

	.KB_SCANCODE(kb_scancode),
	.KB_SCANCODE_UPD(kb_scancode_upd),
	.JOY_L(joy_l),
	.JOY_R(joy_r),

	.ROMLOADER_ACTIVE(rom_active),
	.ROMLOAD_ADDR(rom_addr),
	.ROMLOAD_DATA(rom_data),
	.ROMLOAD_WR(rom_wr),

	.FILELOAD_RESET(file_reset),
	.FILELOAD_ACTIVE(file_active),
	.FILELOAD_ADDR(file_addr),
	.FILELOAD_DATA(file_data),
	.FILELOAD_WR(file_wr),
	.FILELOAD_SLOT(file_slot),

	.SOFTSW_COMMAND(softsw_command),
	.OSD_COMMAND(osd_command),
	.BUSY(mcu_busy),

	.FT_SPI_ON(ft_spi_on),
	.FT_CS_N(ft_cs_n),
	.FT_MOSI(ft_mosi),
	.FT_MISO(FT_SPI_MISO),
	.FT_SCK(),
	.SD2_CS_N(sd2_cs_n),
	.SD2_MOSI(sd2_mosi),
	.SD2_MISO(SD_DO),
	.SD2_SCK(),

	.DVI_ONLY(dvi_only),

	// not used by this core
	.PS2_COMMAND(16'h0000),
	.PS2_COMMAND_WR(1'b0),
	.RTC_A(8'h00),
	.RTC_DI(8'h00),
	.RTC_CS(1'b0),
	.RTC_WR_N(1'b1),
	.UART_TX_DATA(8'h00),
	.UART_TX_WR(1'b0),
	.UART_TX_MODE(1'b0),
	.UART_DLM(8'h00),
	.UART_DLL(8'h00),
	.UART_DLM_WR(1'b0),
	.UART_DLL_WR(1'b0),
	.MATRIX_CMD(24'h000000),
	.MATRIX_CMD_WR(1'b0),
	.DEBUG_ADDR(16'h0000),
	.DEBUG_DATA(16'h0000),
	.IMG_MOUNTED(img_mounted),
	.IMG_SIZE(img_size),
	.IMG_DATA_WR(img_data_wr),
	.IMG_DATA_ADDR(img_data_addr),
	.IMG_DATA(img_data),
	.IMG_RESULT_WR(img_result_wr),
	.IMG_RESULT(img_result),
	.IMG_SUM(img_sum),
	.IMG_Q_WR(img_q_wr),
	.IMG_Q_DI(img_q_di),
	.IMG_Q_ACK(img_q_ack),
	.IMG_PHYS_WR(img_phys_wr),
	.IMG_PHYS(img_phys),
	.IMG_WP(img_wp),
	.ESP_UART_RX_DATA(8'h00),
	.ESP_UART_RX_WR(1'b0),
	.FLASHBOOT_START(1'b0),
	.FLASHBOOT_COREID(5'd0),
	.FDD_CHNG_REQ(1'b0),   // no DSKCHG: the disk ROM finds a disk change itself
	.FDD_CHNG_DS(2'b00),
	.PRN_DATA(8'h00),
	.PRN_WR(1'b0)
);

assign FT_SPI_CS_N = ft_spi_on ? ft_cs_n : 1'b1;
assign FT_SPI_SCK = ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = mcu_sck_ibufg;

// ------------------------------------------------------------------ soft switches

wire [22*8-1:0] sw;
kg_soft_switches #(.N(22)) soft_switches (
	.clk(clk_sys),
	.command(softsw_command),
	.regs(sw),
	.upd()
);
wire sw_tape_rewind = sw[5*8];
wire [1:0] sw_video = sw[7*8 +: 2];   // 0 Auto, 1 PAL, 2 NTSC
wire sw_joy_swap = sw[8*8];
wire sw_reset = sw[11*8];
wire sw_eject = sw[12*8];
wire sw_fdd = sw[13*8 +: 2] == 2'd1;
wire sw_nextor = sw[13*8 +: 2] == 2'd2;
wire sw_slot1_rom = ~sw[14*8];
wire [3:0] sw_mapper_a = sw[15*8 +: 4];
wire [3:0] sw_mapper_b = sw[16*8 +: 4];
wire sw_ram64 = sw[18*8];
wire sw_no_fm = sw[19*8];
wire sw_tape_line = sw[20*8];
wire sw_v9938 = sw[21*8];

// ------------------------------------------------------------------ the machine

wire [7:0] vdp_r, vdp_g, vdp_b;
wire vdp_hs_n, vdp_vs_n, vdp_dhclk;
wire [15:0] msx_audio;

msx_system msx (
	.clk(clk_sys),
	.clk21(clk21),
	.reset(areset || sw_reset || mcu_busy),
	.rom_active(rom_active),
	.rom_addr(rom_addr),
	.rom_data(rom_data),
	.rom_wr(rom_wr),
	.file_reset(file_reset),
	.file_active(file_active),
	.file_slot(file_slot),
	.file_addr(file_addr),
	.file_data(file_data),
	.file_wr(file_wr),
	.mapper_a(sw_mapper_a),
	.mapper_b(sw_mapper_b),
	.pal(sw_video == 2'd1),
	.pal_auto(sw_video == 2'd0),
	.v9958(~sw_v9938),
	.joy_swap(sw_joy_swap),
	.tape_rewind(sw_tape_rewind),
	.tape_line(sw_tape_line),
	.tape_in(TAPE_IN),
	.tape_out(TAPE_OUT),
	.eject(sw_eject),
	.fdd(sw_fdd),
	.fdd_rom_en(sw_slot1_rom),
	.nextor(sw_nextor),
	.ram_mapper(~sw_ram64),
	.opll(~sw_no_fm),
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
	.img_phys_wr(img_phys_wr),
	.img_phys(img_phys),
	.img_wp(img_wp),
	.fdd_in(4'h0),
	.fdd_out(),
	.fdd_active(),
	.kb_scancode(kb_scancode),
	.kb_scancode_upd(kb_scancode_upd),
	.joy_l(joy_l),
	.joy_r(joy_r),
	.vdp_r(vdp_r),
	.vdp_g(vdp_g),
	.vdp_b(vdp_b),
	.vdp_hs_n(vdp_hs_n),
	.vdp_vs_n(vdp_vs_n),
	.vdp_dhclk(vdp_dhclk),
	.vdp_dlclk(),
	.vdp_blank(),
	.vdp_interlace(),
	.audio(msx_audio),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

// ------------------------------------------------------------------ video, OSD

wire [23:0] video_rgb;
wire video_hs, video_vs, video_de;
msx2_fb video (
	.clk21(clk21),
	.clk_sys(clk_sys),
	.clk_vga(clk_vga),
	.reset(areset),
	.r_i(vdp_r[7:2]),
	.g_i(vdp_g[7:2]),
	.b_i(vdp_b[7:2]),
	.hs_n_i(vdp_hs_n),
	.vs_n_i(vdp_vs_n),
	.dhclk(vdp_dhclk),
	.rgb(video_rgb),
	.hs(video_hs),
	.vs(video_vs),
	.de(video_de),
	.sdr_clk(SDR_CLK),
	.sdr_a(SDR_A),
	.sdr_ba(SDR_BA),
	.sdr_dq(SDR_DQ),
	.sdr_dqm(SDR_DQM),
	.sdr_ras_n(SDR_RAS_N),
	.sdr_cas_n(SDR_CAS_N),
	.sdr_we_n(SDR_WE_N)
);

// the OSD commands of kg_mcu (clk_sys) into clk_vga: a word that changes is a command, it crosses
// through a fifo and comes out as a change again (kg_osd_overlay takes a command when it changes)
reg [15:0] osd_cmd_d = 16'd0;
always @(posedge clk_sys)
	osd_cmd_d <= osd_command;
wire osd_fifo_empty;
wire [15:0] osd_cmd_vga;
kg_async_fifo #(.DW(16), .AW(4)) osd_fifo (
	.wclk(clk_sys), .wreset(areset), .wr(osd_command != osd_cmd_d), .din(osd_command), .full(),
	.rclk(clk_vga), .rreset(areset), .rd(!osd_fifo_empty), .dout(osd_cmd_vga), .empty(osd_fifo_empty),
	.rcount()
);

// the OSD in the middle of 640 x 480: the counters start at the leading edge of the syncs, a step is
// two pixels / lines: the picture starts 144 pixels (72 steps) and 35 lines (17 steps) after them,
// the OSD (32 x 26 characters, 512 x 416) 64 pixels and 32 lines into it
wire [23:0] osd_rgb;
kg_osd_overlay #(.H_OFFSET(104), .V_OFFSET(33)) osd (
	.clk(clk_vga),
	.rgb_i(video_rgb),
	.rgb_o(osd_rgb),
	.hsync_i(video_hs),
	.vsync_i(video_vs),
	.osd_command(osd_cmd_vga)
);

// ------------------------------------------------------------------ audio

// PCM1808 (the FT812 and the MIDI synth of the board): 512 fs of clk_sys, 83.7 kHz
wire signed [23:0] adc_l, adc_r;
i2s_transceiver #(.mclk_sclk_ratio(8)) adc (
	.reset_n(~areset),
	.mclk(clk_sys),
	.sclk(ADC_BCK),
	.ws(ADC_LRCK),
	.sd_tx(),
	.sd_rx(ADC_DOUT),
	.l_data_tx(24'b0),
	.r_data_tx(24'b0),
	.l_data_rx(adc_l),
	.r_data_rx(adc_r)
);
ODDR2 oddr_adc (.Q(ADC_CLK), .C0(clk_sys), .C1(~clk_sys), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// the MSX and the ADC, halved each (no clipping)
wire [15:0] audio_l = { msx_audio[15], msx_audio[15:1] } + { adc_l[23], adc_l[23:9] };
wire [15:0] audio_r = { msx_audio[15], msx_audio[15:1] } + { adc_r[23], adc_r[23:9] };

kg_pcm5102 #(.DIV_BITS(2)) dac (  // bck 5.36 MHz, 167 kHz
	.clk(clk_sys),
	.reset(areset),
	.left(audio_l),
	.right(audio_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_WS)
);

// ------------------------------------------------------------------ HDMI

// the audio sample into clk_vga: held on clk_sys at 48 kHz (a toggle tells), taken on clk_vga at
// the change of the synchronised toggle (the sample is stable then: it changes 20 us later)
reg [15:0] smp_l = 16'd0, smp_r = 16'd0;
reg smp_tog = 1'b0;
reg [15:0] smp_acc = 16'd0;  // 48 kHz from 42.857 MHz: + 48 per clock, modulo 42857
always @(posedge clk_sys) begin
	if (smp_acc >= 16'd42857 - 16'd48) begin
		smp_acc <= smp_acc + 16'd48 - 16'd42857;
		smp_l <= audio_l;
		smp_r <= audio_r;
		smp_tog <= ~smp_tog;
	end
	else
		smp_acc <= smp_acc + 16'd48;
end

wire smp_tog_vga;
kg_sync smp_sync (.clk(clk_vga), .d(smp_tog), .q(smp_tog_vga));
reg smp_tog_vga_d = 1'b0;
reg [23:0] hdmi_l = 24'd0, hdmi_r = 24'd0;
always @(posedge clk_vga) begin
	smp_tog_vga_d <= smp_tog_vga;
	if (smp_tog_vga != smp_tog_vga_d) begin
		hdmi_l <= { smp_l, 8'd0 };
		hdmi_r <= { smp_r, 8'd0 };
	end
end

// the audio sample clock of hdmi_tx: 48 kHz of clk_vga (+ 48 per clock, modulo 25000)
reg [15:0] aud_acc = 16'd0;
reg aud_stb = 1'b0;
always @(posedge clk_vga) begin
	aud_stb <= 1'b0;
	if (aud_acc >= 16'd25000 - 16'd48) begin
		aud_acc <= aud_acc + 16'd48 - 16'd25000;
		aud_stb <= 1'b1;
	end
	else
		aud_acc <= aud_acc + 16'd48;
end

// dvi_only (kg_mcu, clk_sys) gates the data islands, which reach the serialisers: from a clk_vga register
wire dvi_only_vga;
kg_sync dvi_sync (.clk(clk_vga), .d(dvi_only), .q(dvi_only_vga));

// 640 x 480: negative syncs
hdmi_tx #(.SAMPLE_FREQ(48000)) hdmi (
	.clk(clk_vga),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(areset || ~lockedx5),
	.rgb(osd_rgb),
	.vsync(~video_vs),
	.hsync(~video_hs),
	.de(video_de),
	.audio_en(~dvi_only_vga),
	.audio_l(hdmi_l),
	.audio_r(hdmi_r),
	.audio_clk(aud_stb),
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0])
);

endmodule
