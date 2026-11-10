`timescale 1ns / 1ps
`default_nettype wire

/*
 msx2_slots.v (karabas, own)

 The slots 0 and 3 of the MSX2 machine in two layouts, the ROMs at the same places of the SRAM in
 both (the system ROM image of OCM, OCM-BIOS.DAT of 512 KB, fits from 000000 as it is):

 cbios = 1, C-BIOS (the roms of core.json), as its openMSX configuration (C-BIOS_MSX2+_EU.xml):
 slot 0 is not expanded (C-BIOS switches page 0 of slot 0 while it runs there when slot 0 is
 expanded: it stops), slot 3 is:
   slot  pages  what                             SRAM (byte)
   0     0, 1   main BIOS 32 KB                  020000 + a[14:0]
   0     2      the logo ROM 16 KB               03C000 + a[13:0]
   3-0   0      sub ROM 16 KB                    030000 + a[13:0]
   3-1   1      MSX-MUSIC ROM 16 KB              02C000 + a[13:0]
   3-2   0..3   the RAM (memory mapper)          ram_sel: the mapper of msx2.v

 cbios = 0, a real BIOS (OCM-BIOS.DAT), the slots of OCM-PLD (emsx_top.vhd, "Slot/Page Decode"):
   0-0   0, 1   main BIOS 32 KB                  020000 + a[14:0]
   0-2   1      MSX-MUSIC ROM 16 KB              02C000 + a[13:0]
   0-3   1      "free" ROM 16 KB                 03C000 + a[13:0]
   3-0   0..3   the RAM (memory mapper)          ram_sel
   3-1   0..2   sub ROM 16 KB + kanji BASIC 32K  030000 + a[15:0]
   3-2   1, 2   ESE-RAM of OCM (MegaSD): erm_sel, not used yet (reads FF)
   3-3   1      XBASIC 16 KB                     028000 + a[13:0]

 The expansion register of an expanded slot is at FFFF while the slot is the primary slot of
 page 3: a write sets it, a read gives it inverted (exp_rd, exp_q); FFFF is not RAM then. A change
 of cbios needs a reset (the expansion registers are 0 then). ppi_a is the primary slot register
 (port A8 of the PPI), sltsl_n the primary slot selects of memory_mapper (low while a memory cycle
 of that slot runs).
*/

module msx2_slots (
	input wire clk,
	input wire reset,
	input wire [15:0] addr,
	input wire [7:0] din,
	input wire wr_n,
	input wire [7:0] ppi_a,
	input wire [3:0] sltsl_n,
	input wire cbios,
	input wire music_en,         // the MSX-MUSIC ROM (with the OPLL)

	output wire exp_rd,          // a read of FFFF in an expanded slot: d_to_cpu = exp_q
	output wire [7:0] exp_q,
	output wire rom_sel,         // a ROM of slot 0 or 3: d_to_cpu = mem_dout, mem_addr = rom_addr
	output wire [21:0] rom_addr,
	output wire ram_sel,         // the RAM of slot 3 (mapper)
	output wire erm_sel          // OCM 3-2 pages 1, 2
);

reg [7:0] exp0 = 8'd0, exp3 = 8'd0;

wire [1:0] page = addr[15:14];
wire [1:0] pri3 = ppi_a[7:6];        // the primary slot of page 3, where FFFF is
wire ffff = addr == 16'hFFFF;
wire exp0_acc = ffff && !sltsl_n[0] && pri3 == 2'd0 && !cbios;
wire exp3_acc = ffff && !sltsl_n[3] && pri3 == 2'd3;

reg wr_d = 1'b1;
always @(posedge clk) begin
	wr_d <= wr_n;
	if (reset) begin
		exp0 <= 8'd0;
		exp3 <= 8'd0;
	end
	else if (!wr_n && wr_d) begin      // at the start of the write (the Z80 holds the data)
		if (exp0_acc) exp0 <= din;
		if (exp3_acc) exp3 <= din;
	end
end

assign exp_rd = (exp0_acc || exp3_acc) && wr_n;
assign exp_q = exp0_acc ? ~exp0 : ~exp3;

reg [1:0] sub0, sub3;
always @* begin
	case (page)
		2'd0: begin sub0 = exp0[1:0]; sub3 = exp3[1:0]; end
		2'd1: begin sub0 = exp0[3:2]; sub3 = exp3[3:2]; end
		2'd2: begin sub0 = exp0[5:4]; sub3 = exp3[5:4]; end
		default: begin sub0 = exp0[7:6]; sub3 = exp3[7:6]; end
	endcase
end

wire s0 = !sltsl_n[0] && !exp0_acc;
wire s3 = !sltsl_n[3] && !exp3_acc;
wire [1:0] s0sub = cbios ? 2'd0 : sub0;   // C-BIOS: slot 0 is not expanded

wire main_sel = s0 && s0sub == 2'd0 && page[1] == 1'b0;
wire logo_sel = s0 && cbios && page == 2'd2;
wire music_sel = music_en && page == 2'd1 && (cbios ? s3 && sub3 == 2'd1 : s0 && sub0 == 2'd2);
wire free_sel = s0 && !cbios && sub0 == 2'd3 && page == 2'd1;
wire sub_sel = s3 && cbios && sub3 == 2'd0 && page == 2'd0;          // C-BIOS: the sub ROM alone
wire ext_sel = s3 && !cbios && sub3 == 2'd1 && page != 2'd3;         // OCM: sub ROM + kanji BASIC
wire xbas_sel = s3 && !cbios && sub3 == 2'd3 && page == 2'd1;

assign ram_sel = s3 && sub3 == (cbios ? 2'd2 : 2'd0);
assign erm_sel = s3 && !cbios && sub3 == 2'd2 && (page == 2'd1 || page == 2'd2);
assign rom_sel = main_sel || logo_sel || music_sel || free_sel || sub_sel || ext_sel || xbas_sel;
// the bases have zeros under the offsets: an OR is the sum
assign rom_addr = main_sel ? (22'h020000 | { 7'd0, addr[14:0] }) :
                  music_sel ? (22'h02C000 | { 8'd0, addr[13:0] }) :
                  xbas_sel ? (22'h028000 | { 8'd0, addr[13:0] }) :
                  sub_sel ? (22'h030000 | { 8'd0, addr[13:0] }) :
                  ext_sel ? (22'h030000 | { 6'd0, addr[15:0] }) :     // pages 0..2: 030000-03BFFF
                            (22'h03C000 | { 8'd0, addr[13:0] });      // logo / free

endmodule
