module slots (
	clk,
	clk_en,
	reset,
	addr,
	wr_n,
	rd_n,
	d_from_cpu,
	d_to_cpu,
	CS1_n,
	CS01_n,
	CS12_n,
	CS2_n,
	SLTSL_n,
	sound,
	ioctl_wr,
	ioctl_addr,
	ioctl_dout,
	ioctl_isROMA,
	ioctl_isROMB,
	ioctl_wait,
	sdram_dout,
	ram_we,
	sdram_din,
	sdram_addr,
	sdram_we,
	sdram_rd,
	sdram_ready,
	sdram_size,
	img_mounted,
	img_size,
	img_wp,
	sd_lba,
	sd_rd,
	sd_wr,
	sd_ack,
	sd_buff_addr,
	sd_buff_dout,
	sd_buff_din,
	sd_buff_wr,
	sd_din_strobe,
	slot_A,
	slot_B,
	fdd_rom_en,
	rom_enabled,
	mapper_info,
	fdd_phys_a,
	fdd_phys_b,
	fdd_in,
	fdd_out
);
	// karabas: the physical floppy drives of the Karabas Go (FDD_PHYS = 1, see vy0010)
	parameter FDD_PHYS = 0;
	input clk;
	input clk_en;
	input reset;
	input [15:0] addr;
	input wr_n;
	input rd_n;
	input [7:0] d_from_cpu;
	output wire [7:0] d_to_cpu;
	input CS1_n;
	input CS01_n;
	input CS12_n;
	input CS2_n;
	input [3:0] SLTSL_n;
	output wire [15:0] sound;
	input ioctl_wr;
	input [24:0] ioctl_addr;
	input [7:0] ioctl_dout;
	input ioctl_isROMA;
	input ioctl_isROMB;
	output wire ioctl_wait;
	input [7:0] sdram_dout;
	output wire [7:0] sdram_din;
	output wire [24:0] sdram_addr;
	output wire sdram_we;
	output wire sdram_rd;
	input sdram_ready;
	input [1:0] sdram_size;
	// karabas: the write of the RAM of slot 3 (in the SRAM, see msx1)
	output wire ram_we;
	input img_mounted;
	input [31:0] img_size;
	input img_wp;
	output wire [31:0] sd_lba;
	output wire sd_rd;
	output wire sd_wr;
	input sd_ack;
	input [8:0] sd_buff_addr;
	input [7:0] sd_buff_dout;
	output wire [7:0] sd_buff_din;
	input sd_buff_wr;
	input sd_din_strobe;
	input [3:0] slot_A;
	input [3:0] slot_B;
	// karabas: the disk ROM of the VY-0010 on (see vy0010)
	input fdd_rom_en;
	input [1:0] rom_enabled;
	output wire [2:0] mapper_info;
	input [1:0] fdd_phys_a;
	input [1:0] fdd_phys_b;
	input [3:0] fdd_in;
	output wire [7:0] fdd_out;
	wire [14:0] sound_slot_A;
	wire [14:0] sound_slot_B;
	assign sound = {sound_slot_A[14], sound_slot_A} + {sound_slot_B[14], sound_slot_B};
	wire ioctl_wait_slot_A;
	wire ioctl_wait_slot_B;
	assign ioctl_wait = ioctl_wait_slot_A | ioctl_wait_slot_B;
	wire [7:0] d_from_FDD;
	wire [7:0] d_from_slot_A;
	wire [7:0] d_from_slot_B;
	wire enableFDD_n = SLTSL_n[1] | ~((|sdram_size & (slot_A == 9)) | ((sdram_size == 0) & (slot_A == 1)));
	wire [7:0] ram_q;
	assign d_to_cpu = (~SLTSL_n[1] ? (enableFDD_n ? d_from_slot_A : d_from_FDD) : (~SLTSL_n[2] ? d_from_slot_B : (~SLTSL_n[3] ? ram_q : 8'hff)));
	wire [24:0] ram_addr_A;
	wire [24:0] ram_addr_B;
	assign sdram_addr = (ioctl_isROMA ? {3'b001, ram_addr_A[21:0]} : (ioctl_isROMB ? {3'b000, ram_addr_B[21:0]} : (~SLTSL_n[1] ? (enableFDD_n ? {3'b001, ram_addr_A[21:0]} : 'd0) : (~SLTSL_n[2] ? {3'b000, ram_addr_B[21:0]} : 'd0))));
	wire [24:0] bram_addr;
	assign bram_addr = ram_addr_B;
	assign sdram_din = ioctl_dout;
	wire [7:0] bram_din;
	assign bram_din = ioctl_dout;
	wire ram_we_A;
	wire ram_we_B;
	assign sdram_we = (ioctl_isROMA ? ram_we_A : (ioctl_isROMB ? ram_we_B : 0));
	wire bram_we;
	assign bram_we = ((sdram_size == 0) & ioctl_isROMB) & ioctl_wr;
	wire ram_rd_A;
	wire ram_rd_B;
	assign sdram_rd = (~SLTSL_n[1] ? (enableFDD_n ? ram_rd_A : 0) : (~SLTSL_n[2] ? ram_rd_B : 0));
	wire [7:0] ram_dout_A;
	assign ram_dout_A = (sdram_size == 0 ? 8'hff : sdram_dout);
	wire [7:0] bram_dout;
	wire [7:0] ram_dout_B;
	assign ram_dout_B = (sdram_size == 0 ? bram_dout : sdram_dout);
	wire ram_ready_A;
	assign ram_ready_A = (sdram_size == 0 ? 1'b1 : sdram_ready);
	wire ram_ready_B;
	assign ram_ready_B = (sdram_size == 0 ? 1'b1 : sdram_ready);
	reg last_loadRom;
	// karabas: on clk (the loads were the clocks of this register)
	always @(posedge clk) begin
		if (ioctl_isROMA)
			last_loadRom <= 0;
		if (ioctl_isROMB)
			last_loadRom <= 1;
	end
	wire [2:0] detected_mapper_A;
	wire [2:0] detected_mapper_B;
	assign mapper_info = (last_loadRom ? (rom_enabled[1] ? detected_mapper_B : 3'h0) : (rom_enabled[0] ? detected_mapper_A : 3'h0));
	wire enableROM_n = SLTSL_n[1] | ~enableFDD_n;
	wire [7:0] ram_din_A;
	cart_rom ROM_slot_A(
		.clk(clk),
		.clk_en(clk_en),
		.reset(reset),
		.addr(addr),
		.wr(~wr_n),
		.rd(~rd_n),
		.CS1_n(CS1_n),
		.CS2_n(CS2_n),
		.CS12_n(CS12_n),
		.SLTSL_n(enableROM_n),
		.d_from_cpu(d_from_cpu),
		.d_to_cpu(d_from_slot_A),
		.sound(sound_slot_A),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_isROM(ioctl_isROMA),
		.ioctl_wait(ioctl_wait_slot_A),
		.ram_dout(ram_dout_A),
		.ram_din(ram_din_A),
		.ram_addr(ram_addr_A),
		.ram_we(ram_we_A),
		.ram_rd(ram_rd_A),
		.ram_ready(ram_ready_A),
		.user_mapper(slot_A),
		.detected_mapper(detected_mapper_A),
		.rom_enabled(rom_enabled[0])
	);
	vy0010 #(.PHYS(FDD_PHYS)) FDD(
		.rom_en(fdd_rom_en),
		.phys_a(fdd_phys_a),
		.phys_b(fdd_phys_b),
		.fdd_in(fdd_in),
		.fdd_out(fdd_out),
		.clk(clk),
		.clk_en(clk_en),
		.reset(reset),
		.addr(addr),
		.d_to_cpu(d_from_FDD),
		.d_from_cpu(d_from_cpu),
		.wr_n(wr_n),
		.rd_n(rd_n),
		.CS1_n(CS1_n),
		.stlsl_n(enableFDD_n),
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
		.sd_din_strobe(sd_din_strobe)
	);
	wire [7:0] ram_din_B;
	cart_rom ROM_slot_B(
		.clk(clk),
		.clk_en(clk_en),
		.reset(reset),
		.addr(addr),
		.wr(~wr_n),
		.rd(~rd_n),
		.CS1_n(CS1_n),
		.CS2_n(CS2_n),
		.CS12_n(CS12_n),
		.SLTSL_n(SLTSL_n[2]),
		.d_from_cpu(d_from_cpu),
		.d_to_cpu(d_from_slot_B),
		.sound(sound_slot_B),
		.ioctl_wr(ioctl_wr),
		.ioctl_addr(ioctl_addr),
		.ioctl_dout(ioctl_dout),
		.ioctl_isROM(ioctl_isROMB),
		.ioctl_wait(ioctl_wait_slot_B),
		.ram_dout(ram_dout_B),
		.ram_din(ram_din_B),
		.ram_addr(ram_addr_B),
		.ram_we(ram_we_B),
		.ram_rd(ram_rd_B),
		.ram_ready(ram_ready_B),
		.user_mapper(slot_B),
		.detected_mapper(detected_mapper_B),
		.rom_enabled(rom_enabled[1])
	);
	// karabas: the RAM of slot 3 is in the SRAM (msx1 puts it at 080000), the ROM of a cartridge
	// too (MiSTer without SDRAM had slot B in 256 KB of block RAM: sdram_size is 1 here)
	assign ram_q = sdram_dout;
	assign ram_we = ~(SLTSL_n[3] | wr_n);
	assign bram_dout = 8'hff;
endmodule
