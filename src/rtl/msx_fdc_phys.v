`timescale 1ns / 1ps
`default_nettype none

/*
 msx_fdc_phys.v

 The WD2793 of the VY-0010 for the physical floppy drives of the Karabas Go: the VG93 model (rtl/vg93,
 github.com/demyanenko-d/FD1793_1818VG93, as taken by the Profi core, see docs/UPSTREAM.md) on the
 pins of the floppy connector. vy0010.v sends here the accesses to 7FF8..7FFB while the selected drive
 is a physical one (the MiSTer wd1793 serves the image).

 Clocks: SYSCLK of the model = clk (clk_sys, 42.857 MHz, the clock of the machine: no crossing for
 the bus). CLK of the model 1 MHz: clk / 43 (0.9967 MHz, low 22 clocks, high 21; the WD pulse is the
 low phase). The separator (after fdd_glue.v of the Profi core, epm570/fdd_glue.v of the upstream:
 the DPLL of fapch_zek by ZEK): RCLK is a free running square wave of HALF clocks per half period
 (86: 2.007 us, one MFM bit cell at 250 kbit/s, 0.33 % slow as CLK: both sides of the drive at the
 same rate), every flux transition pulls its phase half way to the window centre. Write: a WD pulse
 of the model starts a counter of delay + width; WDATA is active while the counter is <= W (9 clocks,
 210 ns); the delay is 5 clocks, EARLY / LATE move it by 1 clock (23 ns) outside TG43, by 3 inside.

 The bus: cs = an access to a register of the model (A = addr 1..0), rd / wr the strobes of the CPU
 (active high, for the whole access). The model takes the byte at the end of the write within two
 microwords (4 us at CLK 1 MHz): the disk ROM leaves more between its writes (its delays around the
 command writes), the CPU of an MSX1 at 3.58 MHz needs no WAIT here.

 Drive: ds = the physical drives selected (bit 0 DS0, bit 1 DS1, from 7FFD and the mapping of
 vy0010), motor (7FFD bit 7, one line for both drives), side (7FFC bit 0). READY of the model is the
 motor of a selected drive (3.5 inch drives give no READY, pin 34 is DSKCHG; the disk ROM waits for
 the spin up itself), HLT 1 (no head load).
 fdd_in / fdd_out are at the FPGA pins, high = active (the board has inverters to the connector), in
 the order of pcxt_fdd_phys (Profi, PCXT cores): fdd_in = { rdata, wprt, tr00, index },
 fdd_out = { wdata, wgate, side1, step, dir (1: in), motor, ds1, ds0 }. All outputs are registered
 (WD and the decoders are combinational, their glitches would reach the drive).
*/

module msx_fdc_phys #(
	parameter [5:0] CLK_DIV = 6'd43,    // CLK of the model: clk / CLK_DIV (1 MHz)
	parameter [6:0] HALF = 7'd86        // RCLK half period in clocks (2 us)
) (
	input wire clk,
	input wire reset,

	input wire cs,
	input wire rd,
	input wire wr,
	input wire [1:0] a,
	input wire [7:0] din,
	output wire [7:0] dout,
	output wire drq,
	output wire intrq,

	input wire [1:0] ds,
	input wire motor,
	input wire side,

	input wire [3:0] fdd_in,
	output reg [7:0] fdd_out = 8'd0
);

wire in_rdata = fdd_in[3];
wire in_wprt = fdd_in[2];
wire in_tr00 = fdd_in[1];
wire in_index = fdd_in[0];

// ---- CLK of the model: 1 MHz, low the first 22 clocks of 43 ----
reg [5:0] cdiv = 6'd0;
reg fdc_clk = 1'b0;
always @(posedge clk) begin
	cdiv <= (cdiv == CLK_DIV - 6'd1) ? 6'd0 : cdiv + 6'd1;
	fdc_clk <= (cdiv >= CLK_DIV / 2) && (cdiv != CLK_DIV - 6'd1);
end

// ---- the model ----
wire cs_n = ~(cs & (rd | wr));
wire [7:0] dal = (cs & wr) ? din : 8'bz;   // the CPU drives DAL on a write
assign dout = dal;

wire step, dirc, early, late, hld, tg43, wg, wd, rclk, rawread_n;
wire ready = motor & |ds;

vg93_top vg93 (
	.SYSCLK(clk),
	.CLK(fdc_clk),
	.MR_n(~reset),
	.CS_n(cs_n),
	.RE_n(~rd),
	.WE_n(~wr),
	.A(a),
	.DAL(dal),
	.DRQ(drq),
	.INTRQ(intrq),
	.STEP(step),
	.DIRC(dirc),
	.EARLY(early),
	.LATE(late),
	.HLD(hld),
	.TG43(tg43),
	.WG(wg),
	.WD(wd),
	.RCLK(rclk),
	.RAWREAD_n(rawread_n),
	.READY(ready),
	.TR00_n(~in_tr00),
	.IP_n(~in_index),
	.WPRT_n(~in_wprt),
	.HLT(1'b1)
);

// ---- separator ----
localparam [6:0] HALF_END = HALF - 7'd1;
localparam [6:0] CENTRE = HALF / 7'd2 - 7'd1;
reg [2:0] rs = 3'b000;              // the synchroniser of RDATA (high = a flux transition)
reg rd_lvl = 1'b0, rd_lvl_d = 1'b0; // filtered: a level must hold two samples
always @(posedge clk) begin
	rs <= { rs[1:0], in_rdata };
	if (rs[2:1] == 2'b00 || rs[2:1] == 2'b11) rd_lvl <= rs[2];
	rd_lvl_d <= rd_lvl;
end
wire flux = rd_lvl & ~rd_lvl_d;     // the start of a pulse, one clock
assign rawread_n = ~flux;

reg [6:0] cnt = 7'd0;
reg rclk_r = 1'b0;
assign rclk = rclk_r;
wire [7:0] pull = { 1'b0, cnt } + { 1'b0, CENTRE };
always @(posedge clk) begin
	if (flux) cnt <= pull[7:1];
	else if (cnt == HALF_END) begin cnt <= 7'd0; rclk_r <= ~rclk_r; end
	else cnt <= cnt + 7'd1;
end

// ---- write precompensation: one counter, load = delay + width, WDATA while it is 1..W ----
localparam [4:0] W = 5'd9, D = 5'd5;
reg wd_d = 1'b0;
reg [4:0] pc = 5'd0;
reg wdata = 1'b0;
always @(posedge clk) begin
	wd_d <= wd & wg;
	if (wd & wg & ~wd_d)
		case ({ late, early })
		2'b10:   pc <= W + D + (tg43 ? 5'd3 : 5'd1);
		2'b01:   pc <= W + D - (tg43 ? 5'd3 : 5'd1);
		default: pc <= W + D;
		endcase
	else if (pc != 5'd0)
		pc <= pc - 5'd1;
	wdata <= (pc != 5'd0) && (pc <= W);
end

// ---- the pins ----
always @(posedge clk) begin
	fdd_out[0] <= ds[0];
	fdd_out[1] <= ds[1];
	fdd_out[2] <= motor & |ds;
	fdd_out[3] <= dirc;
	fdd_out[4] <= step;
	fdd_out[5] <= side;
	fdd_out[6] <= wg & |ds;
	fdd_out[7] <= wdata;
end

endmodule

`default_nettype wire
