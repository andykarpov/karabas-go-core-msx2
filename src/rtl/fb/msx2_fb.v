`timescale 1ns / 1ps
`default_nettype none
/*
 msx2_fb.v
 The frame buffer of the MSX2 core, after pcxt_fb.v of karabas-go-core-pcxt: the 15 kHz picture of
 the VDP into the SDRAM, out again as 640 x 480 at 60 Hz (VESA, 800 x 525 on 25.0 MHz), whatever the
 VDP does (NTSC 60 Hz, PAL 50 Hz, a change of R9 by a program).
 - Capture (clk21, the clock of the VDP; a dot of the VDP is a clk21 with dhclk, 684 a line): a line
   starts at a rise of hs 1300 clocks or more after the line before (in the vertical sync the VDP
   gives hs at twice the line rate), a frame at a rise of vs. The window: W = 640 dots from dot
   H_START (64: the 512 dots of the wide modes in the middle) of the lines V_START (NTSC 19, PAL 49:
   a frame over 287 lines is PAL) to V_START + 239. Dots 620..639 of the window are past the end of
   the line of the VDP (684 dots): the output shows them black. A pixel is RGB565 of the 6-bit R / G / B
   of the VDP; a line of 640 words in a capture buffer of two lines; the start of the next line sends
   the request of a window line to the SDRAM side (a toggle), whatever the number of its dots (a dot
   in the clock of a line start is not counted: 683 or 684 a line, by the phase of dhclk).
   Interlace (il, R9 of the VDP, latched at each vs): the two fields are woven into one frame of
   480 lines. The lower field (its vs in the middle of a line: 500..900 clocks after the line start;
   the VDP gives 262 and 261 lines) counts one line more from vs to its picture, so its line l is
   window line l - 1; line y of the upper field is frame line 2y, of the lower one 2y + 1. A new
   frame starts with line 0 of the upper field.
 - SDRAM (clk_sys, msx2_fb_sdram.v): a line in two rows, row = { 0, frame, line (9 bits), half }
   (line: the window line, or the frame line 0..479 in interlace), three frames:
   the line 0 of a new frame ends the frame before (done) and moves the writer to the frame that is
   neither done nor being shown. The output takes done at its frame start: whole frames only, no
   tearing; a frame of the VDP is repeated or dropped when the rates differ.
 - Output (clk_vga): 800 x 525, 640 x 480 active (hsync at 656..751, vsync at lines 490..491), each
   captured line twice (in interlace each frame line once); the output buffer holds four lines: the
   line s + 1 is read while s shows (interlace: the line vc + 2 while vc shows, 63 us for the SDRAM;
   the first ones in the last lines of the frame). Black until a frame is complete.
   hs / vs / de high active (kg_osd_overlay takes them so; the top inverts the syncs), three clocks
   after the counters as in msx_video.
*/
module msx2_fb #(
	parameter H_START = 10'd64,       // dots from the start of a line to the window
	parameter V_NTSC = 9'd19,         // lines from vsync to the window
	parameter V_PAL = 9'd49
) (
	input wire clk21,
	input wire clk_sys,
	input wire clk_vga,
	input wire reset,                 // in clk_sys

	// the picture of the VDP (clk21)
	input wire [5:0] r_i,
	input wire [5:0] g_i,
	input wire [5:0] b_i,
	input wire hs_n_i,
	input wire vs_n_i,
	input wire dhclk,
	input wire il,                    // interlace (R9 IL of the VDP)

	// the output (clk_vga)
	output reg [23:0] rgb = 24'd0,
	output reg hs = 1'b0,
	output reg vs = 1'b0,
	output reg de = 1'b0,

	// debug (clk_sys): { valid, the SDRAM ready, 0, 0, 0, the lines of the last frame of the VDP (9 bits) }
	output wire [13:0] dbg,

	// SDRAM
	output wire sdr_clk,
	output wire [12:0] sdr_a,
	output wire [1:0] sdr_ba,
	inout wire [15:0] sdr_dq,
	output wire [1:0] sdr_dqm,
	output wire sdr_ras_n,
	output wire sdr_cas_n,
	output wire sdr_we_n
);

localparam W = 10'd640;
localparam W_LINE = 10'd620;          // the dots of the window in a line of the VDP (684 - H_START)
localparam H = 9'd240;

//---------- Capture (clk21) ----------

reg hs_d = 1'b0, vs_d = 1'b0;
reg [10:0] since = 11'd0;             // clocks since the line started
reg [9:0] dot = 10'd0;                // dots since the line started
reg [8:0] vline = 9'd0;               // lines since the frame started
reg [8:0] lines = 9'd262;             // the lines of the frame before
reg cbuf = 1'b0;
reg cap_tgl = 1'b0;
reg [8:0] cap_line = 9'd0;            // the window line, or the frame line (interlace)
reg il_f = 1'b0;                      // this frame: interlace
reg fld = 1'b0;                       // this frame: the lower field
reg cap_buf = 1'b0;
reg cb_we = 1'b0;
reg [10:0] cb_waddr = 11'd0;
reg [15:0] cb_wdata = 16'd0;

wire hs_rise = !hs_n_i && hs_d;       // hs_d holds the last hs_n_i
wire vs_rise = !vs_n_i && vs_d;
wire line_start = hs_rise && since >= 11'd1300;
wire [8:0] v_start = ((lines > 9'd287) ? V_PAL : V_NTSC) + (il_f && fld ? 9'd1 : 9'd0);
wire [9:0] p = dot - H_START;
wire [8:0] l = vline - v_start;
wire in_win = dot >= H_START && p < W_LINE && vline >= v_start && l < H;

always @(posedge clk21) begin
	hs_d <= hs_n_i;
	vs_d <= vs_n_i;
	cb_we <= 1'b0;
	if (since != 11'h7FF) since <= since + 1'd1;
	if (vs_rise) begin
		lines <= vline;
		vline <= 9'd0;
		il_f <= il;
		fld <= since >= 11'd500 && since < 11'd900;
	end
	if (line_start) begin
		since <= 11'd0;
		dot <= 10'd0;
		if (!vs_rise && vline != 9'h1FF) vline <= vline + 1'd1;
		// the line that ends here, if it is a line of the window, to the SDRAM side
		if (vline >= v_start && l < H) begin
			cap_line <= il_f ? { l[7:0], fld } : { 1'b0, l[7:0] };
			cap_buf <= cbuf;
			cap_tgl <= ~cap_tgl;
			cbuf <= ~cbuf;
		end
	end
	else if (dhclk) begin
		if (dot != 10'h3FF) dot <= dot + 1'd1;
		if (in_win) begin
			cb_we <= 1'b1;
			// { buf, half, word }: words 0..319, 320..639
			cb_waddr <= (p < 10'd320) ? { cbuf, 1'b0, p[8:0] } : { cbuf, 1'b1, p[8:0] - 9'd320 };
			cb_wdata <= { r_i[5:1], g_i, b_i[5:1] };
		end
	end
end

//---------- SDRAM side (clk_sys) ----------

wire [10:0] cb_raddr;
wire [15:0] cb_rdata;
kg_sdpram #(.DW(16), .AW(11)) u_cbuf(
	.clka(clk21), .wea(cb_we), .addra(cb_waddr), .dina(cb_wdata),
	.clkb(clk_sys), .enb(1'b1), .addrb(cb_raddr), .doutb(cb_rdata)
);

reg [2:0] cap_s = 3'd0, out_s = 3'd0;
reg out_tgl = 1'b0;
reg [8:0] out_line = 9'd0;
reg out_fs = 1'b0;
always @(posedge clk_sys) begin
	cap_s <= { cap_s[1:0], cap_tgl };
	out_s <= { out_s[1:0], out_tgl };
end
wire cap_ev = cap_s[2] != cap_s[1];
wire out_ev = out_s[2] != out_s[1];

// the frames: wf written, df the last complete one, rf shown; three different ones but at the start
reg [1:0] wf = 2'd0, df = 2'd1, rf = 2'd2;
reg valid = 1'b0;
reg wr_req = 1'b0, rd_req = 1'b0;
reg [11:0] wr_row = 12'd0, rd_row = 12'd0;
reg wr_buf = 1'b0;
reg [1:0] rd_buf = 2'd0;

function [1:0] other(input [1:0] a, input [1:0] b);   // the frame that is neither a nor b
	other = (a != 2'd0 && b != 2'd0) ? 2'd0 : (a != 2'd1 && b != 2'd1) ? 2'd1 : 2'd2;
endfunction

// a frame start of the output takes df; a new frame of the capture (its line 0) completes wf and
// moves to the frame that is neither the new df nor the frame shown from now on (both may come in
// the same clock: the output still takes the old df then)
wire out_new = out_ev && out_fs;
wire cap_new = cap_ev && (cap_line == 9'd0);
wire [1:0] rf_n = out_new ? df : rf;
wire [1:0] wf_n = cap_new ? other(wf, rf_n) : wf;

always @(posedge clk_sys) begin
	wr_req <= 1'b0;
	rd_req <= 1'b0;
	rf <= rf_n;
	wf <= wf_n;
	if (cap_new) begin
		df <= wf;
		valid <= 1'b1;
	end
	if (cap_ev) begin
		wr_req <= 1'b1;
		wr_buf <= cap_buf;
		wr_row <= { 1'b0, wf_n, cap_line };
	end
	if (out_ev) begin
		rd_req <= 1'b1;
		rd_buf <= out_line[1:0];
		rd_row <= { 1'b0, rf_n, out_line };
	end
	if (reset) valid <= 1'b0;
end

wire sdr_ready;
reg [8:0] lines_s = 9'd0;
always @(posedge clk_sys) lines_s <= lines;   // a debug value: a torn sample does no harm
assign dbg = { valid, sdr_ready, 3'd0, lines_s };
wire lb_we;
wire [11:0] lb_addr;
wire [15:0] lb_data;
msx2_fb_sdram u_sdram(
	.clk(clk_sys),
	.reset(reset),
	.wr_req(wr_req), .wr_row(wr_row), .wr_buf(wr_buf),
	.cb_addr(cb_raddr), .cb_data(cb_rdata),
	.rd_req(rd_req), .rd_row(rd_row), .rd_buf(rd_buf),
	.lb_we(lb_we), .lb_addr(lb_addr), .lb_data(lb_data),
	.ready(sdr_ready),
	.sdr_a(sdr_a), .sdr_ba(sdr_ba), .sdr_dq(sdr_dq), .sdr_dqm(sdr_dqm),
	.sdr_ras_n(sdr_ras_n), .sdr_cas_n(sdr_cas_n), .sdr_we_n(sdr_we_n)
);

// SDR_CLK: clk_sys at 180 degrees
ODDR2 u_sdr_clk(.Q(sdr_clk), .C0(clk_sys), .C1(~clk_sys), .CE(1'b1), .D0(1'b0), .D1(1'b1),
	.R(1'b0), .S(1'b0));

//---------- Output (clk_vga) ----------

localparam H_ACTIVE = 10'd640, H_FP = 10'd16, H_SYNC = 10'd96, H_TOTAL = 10'd800;
localparam V_ACTIVE = 10'd480, V_FP = 10'd10, V_SYNC = 10'd2, V_TOTAL = 10'd525;

reg [9:0] hc = 10'd0;
reg [9:0] vc = 10'd0;
wire il_v;
kg_sync #(.W(1)) u_sync_il(.clk(clk_vga), .d(il), .q(il_v));
wire [8:0] s = il_v ? vc[8:0] : { 1'b0, vc[8:1] };   // the stored line of output line vc

always @(posedge clk_vga) begin
	if (hc == H_TOTAL - 1'd1) begin
		hc <= 10'd0;
		vc <= (vc == V_TOTAL - 1'd1) ? 10'd0 : vc + 1'd1;
	end else
		hc <= hc + 1'd1;
	// the line reads: s + 1 at the start of the first of the two lines of s, line 0 in the last
	// line of the frame
	if (hc == 10'd0) begin
		if (il_v) begin
			// interlace: line vc + 2 while vc shows; 0 and 1 in the last two lines of the frame
			if (vc == V_TOTAL - 2'd2) begin
				out_line <= 9'd0;
				out_fs <= 1'b1;
				out_tgl <= ~out_tgl;
			end else if (vc == V_TOTAL - 1'd1) begin
				out_line <= 9'd1;
				out_fs <= 1'b0;
				out_tgl <= ~out_tgl;
			end else if (vc < V_ACTIVE - 2'd2) begin
				out_line <= vc[8:0] + 9'd2;
				out_fs <= 1'b0;
				out_tgl <= ~out_tgl;
			end
		end else if (vc == V_TOTAL - 1'd1) begin
			out_line <= 9'd0;
			out_fs <= 1'b1;
			out_tgl <= ~out_tgl;
		end else if (vc < V_ACTIVE - 2'd2 && !vc[0]) begin
			out_line <= s + 1'd1;
			out_fs <= 1'b0;
			out_tgl <= ~out_tgl;
		end
	end
end

// the output buffer: { the line s[1:0], half, word }
wire [15:0] ob_rdata;
wire ob_half = hc >= 10'd320;
wire [8:0] ob_word = ob_half ? hc[8:0] - 9'd320 : hc[8:0];
kg_sdpram #(.DW(16), .AW(12)) u_obuf(
	.clka(clk_sys), .wea(lb_we), .addra(lb_addr), .dina(lb_data),
	.clkb(clk_vga), .enb(1'b1), .addrb({ s[1:0], ob_half, ob_word }), .doutb(ob_rdata)
);

wire valid_v;
kg_sync #(.W(1)) u_sync_valid(.clk(clk_vga), .d(valid), .q(valid_v));

// the pipeline: hc / vc (clock 0) -> the buffer word (1) -> the colour (2) -> out (3)
reg de1 = 1'b0, hs1 = 1'b0, vs1 = 1'b0, past1 = 1'b0;
reg de2 = 1'b0, hs2 = 1'b0, vs2 = 1'b0;
reg [23:0] rgb2 = 24'd0;

always @(posedge clk_vga) begin
	de1 <= hc < H_ACTIVE && vc < V_ACTIVE;
	hs1 <= hc >= H_ACTIVE + H_FP && hc < H_ACTIVE + H_FP + H_SYNC;
	vs1 <= vc >= V_ACTIVE + V_FP && vc < V_ACTIVE + V_FP + V_SYNC;
	past1 <= hc >= W_LINE;
	// clock 1: the word is there
	de2 <= de1;
	hs2 <= hs1;
	vs2 <= vs1;
	rgb2 <= (!de1 || !valid_v || past1) ? 24'd0 :
	        { ob_rdata[15:11], ob_rdata[15:13], ob_rdata[10:5], ob_rdata[10:9], ob_rdata[4:0], ob_rdata[4:2] };
	// clock 2
	de <= de2;
	hs <= hs2;
	vs <= vs2;
	rgb <= rgb2;
end

endmodule
