`timescale 1ns / 1ps
`default_nettype none

// The frame buffer (rtl/fb/msx2_fb.v + msx2_fb_sdram.v) with a model of the SDRAM (CAS latency 2,
// tAC 6 ns, tOH 3 ns, 2 ns of traces each way). The source is a VDP at 15 kHz: 1368 clocks of clk21 a
// line, a dot at every other clock (dhclk), hs low for 100 clocks at the line start and, in the 9
// lines of the vertical sync, a second hs pulse in the middle of the line (as vdp_ntsc_pal does),
// vs low in lines 3..5; R / G / B a pattern of the dot and the line. Source frames 0..3 are NTSC
// (262 lines), from frame 4 on PAL (313). The output must be 800 x 525 clocks in every line and frame
// with 640 active pixels, and show the window (H_START, V_START of NTSC / PAL, 640 x 240, each line
// twice, dots 620..639 black) once frames are complete; the frames at the change to PAL may be wrong.

module tb_msx2_fb;

reg clk21 = 1'b0, clk_sys = 1'b0, clk_vga = 1'b0;
always #23.333 clk21 = ~clk21;       // 21.43 MHz
always #11.667 clk_sys = ~clk_sys;   // 42.857 MHz
always #20 clk_vga = ~clk_vga;       // 25.0 MHz

reg reset = 1'b1;
initial #1000 reset = 1'b0;

localparam H_START = 64, V_NTSC = 19, V_PAL = 49;
// the window counts lines from the rise of vs (line VS_LINE of the source) and dots from the line
// start (dot 0 of the source)
localparam VS_LINE = 3;

// the source
reg [10:0] gh = 11'd0;
reg [9:0] gl = 10'd0;
reg [4:0] frame_no = 5'd0;
wire pal_src = frame_no >= 5'd4;
wire [9:0] lines = pal_src ? 10'd313 : 10'd262;
wire hs_n = !((gh < 11'd100) || (gl < 10'd9 && gh >= 11'd684 && gh < 11'd734));
wire vs_n = !(gl >= 10'd3 && gl < 10'd6);
// +ph1: dhclk one clock later, a dot in the clock of the line start (the capture does not count it:
// 683 dots a line then, the window shows the source dots one later)
reg ph = 1'b0;
initial ph = $test$plusargs("ph1");
wire [11:0] ghp = gh + ph;
wire dhclk = ghp[0];
wire [9:0] sdot = ghp[10:1];
function [17:0] pat(input [9:0] d, input [9:0] l);
	pat = { d[5:0] ^ l[5:0], d[6:1] + l[5:0], l[5:0] ^ { d[2:0], d[5:3] } };
endfunction
wire [17:0] src = pat(sdot, gl);
always @(posedge clk21) begin
	if (gh == 11'd1367) begin
		gh <= 11'd0;
		if (gl == lines - 1'd1) begin
			gl <= 10'd0;
			frame_no <= frame_no + 1'd1;
		end else
			gl <= gl + 1'd1;
	end else
		gh <= gh + 1'd1;
end

wire [23:0] rgb;
wire hs, vs, de;
wire sdr_clk, sdr_ras_n, sdr_cas_n, sdr_we_n;
wire [12:0] sdr_a;
wire [1:0] sdr_ba, sdr_dqm;
wire [15:0] sdr_dq;

msx2_fb #(.H_START(H_START), .V_NTSC(V_NTSC), .V_PAL(V_PAL)) dut(
	.clk21(clk21), .clk_sys(clk_sys), .clk_vga(clk_vga), .reset(reset),
	.r_i(src[17:12]), .g_i(src[11:6]), .b_i(src[5:0]), .hs_n_i(hs_n), .vs_n_i(vs_n), .dhclk(dhclk),
	.rgb(rgb), .hs(hs), .vs(vs), .de(de),
	.sdr_clk(sdr_clk), .sdr_a(sdr_a), .sdr_ba(sdr_ba), .sdr_dq(sdr_dq), .sdr_dqm(sdr_dqm),
	.sdr_ras_n(sdr_ras_n), .sdr_cas_n(sdr_cas_n), .sdr_we_n(sdr_we_n)
);

// the SDRAM: bank 0, rows of 512 words
reg [15:0] mem [0:(1<<21)-1];
reg [12:0] row = 13'd0;
reg [15:0] dq_drv = 16'd0;
reg dq_en = 1'b0;
assign #2 sdr_dq = dq_en ? dq_drv : 16'bz;
wire #2 clk_d = sdr_clk;
wire [2:0] c;
assign #2 c = { sdr_ras_n, sdr_cas_n, sdr_we_n };
wire [12:0] a_d;
assign #2 a_d = sdr_a;
wire [15:0] dq_in = sdr_dq;
reg [8:0] rd_col1 = 9'd0;
reg rd1 = 1'b0;
integer errors = 0, rds = 0, wrs = 0, refs = 0;
always @(posedge clk_d) begin
	// a READ of the edge before: its data from tAC after this edge to tOH after the next one
	if (rd1) begin
		dq_drv <= #6 mem[{ row[11:0], rd_col1 }];
		dq_en <= #6 1'b1;
	end else
		dq_en <= #3 1'b0;
	rd1 <= 1'b0;
	case (c)
		3'b011: row <= a_d;                              // ACTIVE
		3'b100: begin mem[{ row[11:0], a_d[8:0] }] <= dq_in; wrs = wrs + 1; end  // WRITE
		3'b101: begin rd1 <= 1'b1; rd_col1 <= a_d[8:0]; rds = rds + 1; end  // READ
		3'b001: refs = refs + 1;                         // REFRESH
		default: ;
	endcase
end

// the expected pixel of the output: RGB565 of the source, widened as msx2_fb does
function [23:0] expect(input integer x, input integer y, input pal);
	reg [17:0] q;
	begin
		q = pat(H_START + ph + x, VS_LINE + (pal ? V_PAL : V_NTSC) + y / 2);
		if (x >= 620 - ph) expect = 24'd0;
		else expect = { q[17:13], q[17:15], q[11:6], q[11:10], q[5:1], q[5:3] };
	end
endfunction

integer x = 0, y = 0, hcnt = 0, vcnt = 0, oframe = 0, bad = 0, frame_bad = 0, checked = 0;
integer bad_ntsc = 0, bad_pal = 0;
reg hs_d = 1'b0, vs_d = 1'b0, de_d = 1'b0;
reg check_on = 1'b0;
reg shown_pal = 1'b0;     // the frames shown are PAL ones (set when the source has been PAL a while)
always @(posedge clk_vga) begin
	hs_d <= hs;
	vs_d <= vs;
	de_d <= de;
	hcnt = hcnt + 1;
	if (hs && !hs_d) begin
		if (oframe > 0 && hcnt != 800) begin
			$display("ERROR: output line of %0d clocks", hcnt);
			errors = errors + 1;
		end
		hcnt = 0;
		vcnt = vcnt + 1;
	end
	if (vs && !vs_d) begin
		if (oframe > 1 && vcnt != 525) begin
			$display("ERROR: output frame of %0d lines", vcnt);
			errors = errors + 1;
		end
		if (check_on) begin
			checked = checked + 1;
			if (frame_bad != 0) begin
				bad = bad + 1;
				if (shown_pal) bad_pal = bad_pal + 1; else bad_ntsc = bad_ntsc + 1;
			end
			$display("output frame %0d: %0d wrong pixels (source frame %0d, checked as %s)", oframe, frame_bad,
				frame_no, shown_pal ? "PAL" : "NTSC");
		end
		vcnt = 0;
		oframe = oframe + 1;
		frame_bad = 0;
		y = 0;
		shown_pal = frame_no >= 5'd6;
	end
	if (de) begin
		if (rgb !== expect(x, y, shown_pal)) begin
			if (check_on && frame_bad < 4 && $test$plusargs("dbg"))
				$display("  x %0d y %0d: %h, expected %h", x, y, rgb, expect(x, y, shown_pal));
			frame_bad = frame_bad + 1;
		end
		x = x + 1;
	end
	if (!de && de_d) begin
		if (x != 640) begin $display("ERROR: %0d active pixels", x); errors = errors + 1; end
		x = 0;
		y = y + 1;
	end
end

initial begin
	// frames 0, 1 of the source fill the buffer; check the output frames shown from source frame 2 on
	wait (frame_no == 5'd2);
	check_on = 1'b1;
	wait (frame_no == (($test$plusargs("dbg")) ? 5'd4 : 5'd10));
	check_on = 1'b0;
	$display("%0d output frames checked, %0d with wrong pixels (%0d NTSC, %0d PAL); SDRAM %0d writes, %0d reads, %0d refreshes",
		checked, bad, bad_ntsc, bad_pal, wrs, rds, refs);
	// the frames at the change to PAL (source frames 4, 5) may be wrong: the window of the first PAL
	// frame is still the NTSC one, and the output shows each frame once or twice
	if (bad > 4) begin
		$display("ERROR: too many wrong frames");
		errors = errors + 1;
	end
	if (checked < 8) begin
		$display("ERROR: too few frames");
		errors = errors + 1;
	end
	// 8192 rows in 64 ms: a refresh per 7.8 us at least
	if (refs * 7800 < $time - 300000) begin
		$display("ERROR: %0d refreshes in %0d us", refs, $time / 1000);
		errors = errors + 1;
	end
	$display("tb_msx2_fb: %0d errors", errors);
	$finish;
end

endmodule
