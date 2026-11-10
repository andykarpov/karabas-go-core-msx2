`timescale 1ns / 1ps
`default_nettype wire

/*
 MSX1 core for Karabas Go (VGA through the video DAC, PCM5102).
 The same as karabas_minig_top.v except the board: VGA 8:8:8 + V_CLK instead of HDMI (no DCM, no
 audio over the video), no PCM1808 and no FT_CLK_OUT, MCU_SCK not on a clock pin (bursts at the link
 clock), the chip selects of the FT812 / SD2 on their own pins, the floppy connector for the
 physical drives A / B (msx_fdc_phys).

 The machine is MiSTer MSX1 (rtl/msx, see docs/UPSTREAM.md) in msx_system; all file work goes
 through the firmware: the ROMs of core.json (C-BIOS) by the ROM loader, the cartridges and a BIOS
 file by the FL items of the OSD (the file loader of kg_mcu, FILELOAD_SLOT), see msx_system.v.

 Clocks: one PLL, VCO 600 MHz (50 * 12): clk_sys 42.857 MHz (/14, 12 x 3.57 MHz: the machine, the
 SRAM, the MCU link, audio), clk_vga 25.0 MHz (/24, 640 x 480: msx_video reads its frame buffer,
 the OSD, HDMI), clk_8 8.0 MHz (/75, FT_CLK_OUT: the FT812 must always have its clock, see
 karabas-go-notes ft-clk-out-required). HDMI: kg_dcm 5 x clk_vga and its inverse.

 Soft switches (the index of the item in the osd of core.json, file items included; the
 pages of the menu do not change it; separators and the page entry are not registers):
   main page: 0 Cart A (FL 4)   1 Disk A (F 0)   2 HDD (F 6, Nextor)   3 Cart B (FL 1)
   4 Tape (FL 3, .cas)   5 Tape rewind   6 -   7 Video (PAL / NTSC)   8 Joysticks (swap)   9 -
   10 Machine (page 1)   11 Reset   12 Eject carts
   page Machine: 13 Slot 1 (cartridge A / disk drive / Nextor)   14 Slot 1 ROM (on / off: the disk
   ROM or the Nextor ROM reads FF, for tests under C-BIOS)   15 Mapper A   16 Mapper B   17 -
   18 RAM (512K mapper / 64K)   19 FM (MSX-MUSIC on / off)   20 Tape input (CAS file / TAPE_IN)
   21 -   22 BIOS (FL 2)   23 Nextor ROM (FL 5)
 On the Go only: Disk B (F 7, physical drives only) after Disk A; the switches keep the numbers
 above by the "index" of their items in core.json. Disk A / B set to [ Physical A ] / [ Physical B ]
 of the firmware are the drives DS0 / DS1 of the floppy connector (CMD_IMG_PHYS, msx_system).
*/

module karabas_go_top (
	input wire CLK_50MHZ,

	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,

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

	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire VGA_HS,
	output wire VGA_VS,
	output wire V_CLK,

	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,

	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,

	output wire DAC_LRCK,
	output wire DAC_DAT,
	output wire DAC_BCK,
	output wire DAC_MUTE,

	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,
	inout wire [1:0] MCU_SPI_IO, // [0] burst ready (firmware IO1, GPIO2), [1] burst cs_n (IO0, GPIO14)

	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,

	output wire FLASH_CS_N,
	input wire FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N
);

// ------------------------------------------------------------------ unused

assign SDR_BA = 2'b11;
assign SDR_A = 13'h1FFF;
assign SDR_CLK = 1'b1;
assign SDR_DQM = 2'b11;
assign SDR_WE_N = 1'b1;
assign SDR_CAS_N = 1'b1;
assign SDR_RAS_N = 1'b1;
assign SDR_DQ = 16'bz;

assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'bz;

assign ESP_RESET_N = 1'bz;
assign ESP_BOOT_N = 1'bz;
assign MIDI_TX = 1'b1;
assign MIDI_CLK = 1'b1;
assign MIDI_RESET_N = 1'b1;
assign FT_OE_N = 1'b1;     // the FT812 does not drive the video DAC
assign BEEPER = 1'b0;

// the floppy connector (high = active at the pins, the board has inverters; FDC_SIDE_N is side 1 when
// high): msx_fdc_phys through msx_system, registered there, all 0 without a physical drive
wire [7:0] fdd_out;
assign FDC_DRIVE = fdd_out[1:0];
assign FDC_MOTOR = fdd_out[2];
assign FDC_DIR = fdd_out[3];
assign FDC_STEP = fdd_out[4];
assign FDC_SIDE_N = fdd_out[5];
assign FDC_WGATE = fdd_out[6];
assign FDC_WDATA = fdd_out[7];
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;

assign FLASH_CS_N = 1'b1;
assign FLASH_DI = 1'b1;
assign FLASH_SCK = 1'b0;
assign FLASH_WP_N = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign MRD_N = 2'b00;  // SRAM /OE: always on, msx_sram drives MD only with /WE

// ------------------------------------------------------------------ clocks

wire clk_sys, clk_vga;
wire locked, areset;

wire [5:0] pll_clk;
kg_pll #(
	.CLKIN_PERIOD(20.0),
	.DIVCLK_DIVIDE(1),
	.CLKFBOUT_MULT(12),
	.CLKOUT0_DIVIDE(14),
	.CLKOUT1_DIVIDE(24),
	.CLKOUT2_DIVIDE(75),
	.BUFG_MASK(6'b000011)  // clk_8 (the FT812 clock of the Mini boards) is not used on the Go
) pll (
	.clk_in(CLK_50MHZ),
	.rst(1'b0),
	.clk_out(pll_clk),
	.locked(locked)
);
assign clk_sys = pll_clk[0];
assign clk_vga = pll_clk[1];
assign areset = ~locked;

// the pixel clock of the video DAC
ODDR2 oddr_v_clk (.Q(V_CLK), .C0(clk_vga), .C1(~clk_vga), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------------------------------------------------------------------ MCU

wire mcu_burst_ready;
assign MCU_SPI_IO[0] = mcu_burst_ready;
assign MCU_SPI_IO[1] = 1'bz;

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
	.BURST_MAX_MHZ(0),   // MCU_SCK is not on a clock pin: bursts at the link clock
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
	.MCU_SCK(MCU_SCK),
	.MCU_SS(MCU_CS_N),
	.MCU_SPI_FT_SS(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(MCU_SPI_SD2_CS_N),
	.MCU_BURST_CS_N(MCU_SPI_IO[1]),
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
assign FT_SPI_SCK = ft_spi_on ? MCU_SCK : 1'b1;
assign FT_SPI_MOSI = ft_spi_on ? ft_mosi : 1'b1;
assign SD_CS_N = sd2_cs_n;
assign SD_DI = sd2_mosi;
assign SD_CLK = MCU_SCK;

// ------------------------------------------------------------------ soft switches

wire [21*8-1:0] sw;
kg_soft_switches #(.N(21)) soft_switches (
	.clk(clk_sys),
	.command(softsw_command),
	.regs(sw),
	.upd()
);
wire sw_tape_rewind = sw[5*8];
wire sw_ntsc = sw[7*8];
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

// ------------------------------------------------------------------ the machine

wire [3:0] vdp_col;
wire vdp_ce_pix, vdp_hor_active, vdp_vert_active;
wire [15:0] msx_audio;

msx_system #(.FDD_PHYS(1)) msx (
	.clk(clk_sys),
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
	.pal(~sw_ntsc),
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
	.fdd_in({ FDC_RDATA, FDC_WPRT, FDC_TR00, FDC_INDEX }),
	.fdd_out(fdd_out),
	.fdd_active(),
	.kb_scancode(kb_scancode),
	.kb_scancode_upd(kb_scancode_upd),
	.joy_l(joy_l),
	.joy_r(joy_r),
	.vdp_col(vdp_col),
	.vdp_ce_pix(vdp_ce_pix),
	.vdp_hor_active(vdp_hor_active),
	.vdp_vert_active(vdp_vert_active),
	.audio(msx_audio),
	.MA(MA),
	.MD(MD),
	.MWR_N(MWR_N)
);

// ------------------------------------------------------------------ video, OSD

wire [23:0] video_rgb;
wire video_hs, video_vs, video_de;
msx_video video (
	.clk(clk_sys),
	.ce_pix(vdp_ce_pix),
	.hor_active(vdp_hor_active),
	.vert_active(vdp_vert_active),
	.col(vdp_col),
	.clk_vga(clk_vga),
	.rgb(video_rgb),
	.hs(video_hs),
	.vs(video_vs),
	.de(video_de)
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

wire [15:0] audio_l = msx_audio;
wire [15:0] audio_r = msx_audio;

kg_pcm5102 #(.DIV_BITS(2)) dac (  // bck 5.36 MHz, 167 kHz
	.clk(clk_sys),
	.reset(areset),
	.left(audio_l),
	.right(audio_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_LRCK)
);
assign DAC_MUTE = 1'b1;  // soft mute of the PCM5102: 1 = sound on

// ------------------------------------------------------------------ VGA

assign VGA_R = osd_rgb[23:16];
assign VGA_G = osd_rgb[15:8];
assign VGA_B = osd_rgb[7:0];
// 640 x 480: negative syncs (msx_video gives 1 in the pulse)
assign VGA_HS = ~video_hs;
assign VGA_VS = ~video_vs;

endmodule
