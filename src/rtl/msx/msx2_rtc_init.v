`timescale 1ns / 1ps
`default_nettype wire

/*
 msx2_rtc_init.v (karabas, own)

 Sets the RP5C01 of the MSX2 (rtc.v of OCM-PLD) to the time of the board once, after the start of
 the core: the firmware keeps the clock registers in kg_mcu (rtc_mode 3 of core.json, MSM6242B: 13
 BCD digits S1 S10 MI1 MI10 H1 H10 D1 D10 MO1 MO10 Y1 Y10 W, year mod 100, 24 h) and has sent them
 before its start (busy). On start this reads them (rtc_a -> rtc_do a clock later) and writes them
 to the RP5C01 through its own ports, as a program would (wr, adr0: 0 the register pointer B4, 1
 the data B5):
   D = 8 (bank 0, timer on); 0..5 the seconds, minutes, hours; 6 the day of the week; 7..10 the day
   and the month; 11, 12 the year since 1980 (the MSX BIOS adds 1980: year mod 100 + 20, the years
   2000..2079); D = 9 (bank 1); 10 = 1 (24 h); 11 = the year mod 4 (the leap year counter, 0 =
   leap); D = 8.
 The writes come before the BIOS reads the clock (the machine leaves its reset with the mcu).
*/

module msx2_rtc_init (
	input wire clk,
	input wire start,            // a pulse: the mcu is done with its start
	output reg [7:0] rtc_a = 8'd0,
	input wire [7:0] rtc_do,
	output reg wr = 1'b0,        // a write to the RP5C01, one clock
	output reg adr0 = 1'b0,
	output reg [7:0] data = 8'd0,
	output wire busy
);

reg [3:0] dig [0:12];
reg [4:0] step = 5'd0;       // 0 idle; reading 1..14; writing 15..
reg [4:0] n = 5'd0;
reg rd_v = 1'b0;
reg [3:0] rd_i = 4'd0;
assign busy = step != 5'd0;

// the year: Y10 * 10 + Y1 + 20 (BCD), the leap counter: (Y10 * 10 + Y1) mod 4 = (2 * Y10 + Y1) mod 4
wire [6:0] yy = { 3'd0, dig[11] } * 7'd10 + { 3'd0, dig[10] };   // 0..99
wire [6:0] ry = yy + 7'd20;
wire [3:0] ry10 = ry >= 7'd110 ? 4'd11 : ry >= 7'd100 ? 4'd10 : ry >= 7'd90 ? 4'd9 : ry >= 7'd80 ? 4'd8 :
                  ry >= 7'd70 ? 4'd7 : ry >= 7'd60 ? 4'd6 : ry >= 7'd50 ? 4'd5 : ry >= 7'd40 ? 4'd4 :
                  ry >= 7'd30 ? 4'd3 : 4'd2;
wire [6:0] ry1 = ry - { 3'd0, ry10 } * 7'd10;
wire [1:0] leap = yy[1:0];

// the writes: { adr0, data } in order
reg [8:0] wseq;
always @* begin
	case (n)
		5'd0: wseq = { 1'b0, 8'd13 };  5'd1: wseq = { 1'b1, 8'h08 };
		5'd2: wseq = { 1'b0, 8'd0 };   5'd3: wseq = { 1'b1, 4'd0, dig[0] };
		5'd4: wseq = { 1'b0, 8'd1 };   5'd5: wseq = { 1'b1, 4'd0, dig[1] };
		5'd6: wseq = { 1'b0, 8'd2 };   5'd7: wseq = { 1'b1, 4'd0, dig[2] };
		5'd8: wseq = { 1'b0, 8'd3 };   5'd9: wseq = { 1'b1, 4'd0, dig[3] };
		5'd10: wseq = { 1'b0, 8'd4 };  5'd11: wseq = { 1'b1, 4'd0, dig[4] };
		5'd12: wseq = { 1'b0, 8'd5 };  5'd13: wseq = { 1'b1, 4'd0, dig[5] };
		5'd14: wseq = { 1'b0, 8'd6 };  5'd15: wseq = { 1'b1, 4'd0, dig[12] };          // the week day
		5'd16: wseq = { 1'b0, 8'd7 };  5'd17: wseq = { 1'b1, 4'd0, dig[6] };
		5'd18: wseq = { 1'b0, 8'd8 };  5'd19: wseq = { 1'b1, 4'd0, dig[7] };
		5'd20: wseq = { 1'b0, 8'd9 };  5'd21: wseq = { 1'b1, 4'd0, dig[8] };
		5'd22: wseq = { 1'b0, 8'd10 }; 5'd23: wseq = { 1'b1, 4'd0, dig[9] };
		5'd24: wseq = { 1'b0, 8'd11 }; 5'd25: wseq = { 1'b1, 1'b0, ry1 };
		5'd26: wseq = { 1'b0, 8'd12 }; 5'd27: wseq = { 1'b1, 4'd0, ry10 };
		default: wseq = 9'd0;
	endcase
end
// after the time: bank 1 (24 h, the leap counter), back to bank 0
reg [8:0] wtail;
reg [2:0] t = 3'd0;
always @* begin
	case (t)
		3'd0: wtail = { 1'b0, 8'd13 }; 3'd1: wtail = { 1'b1, 8'h09 };
		3'd2: wtail = { 1'b0, 8'd10 }; 3'd3: wtail = { 1'b1, 8'h01 };
		3'd4: wtail = { 1'b0, 8'd11 }; 3'd5: wtail = { 1'b1, 6'd0, leap };
		3'd6: wtail = { 1'b0, 8'd13 }; default: wtail = { 1'b1, 8'h08 };
	endcase
end

reg [1:0] gap = 2'd0;
reg tail = 1'b0;
always @(posedge clk) begin
	wr <= 1'b0;
	rd_v <= 1'b0;
	if (rd_v)
		dig[rd_i] <= rtc_do[3:0];
	if (step == 5'd0) begin
		if (start) begin
			step <= 5'd1;
			rtc_a <= 8'd0;
		end
	end
	else if (step <= 5'd13) begin
		// one register a clock: rtc_do of rtc_a comes a clock later
		rd_v <= 1'b1;
		rd_i <= rtc_a[3:0];
		rtc_a <= rtc_a + 8'd1;
		step <= step + 5'd1;
		n <= 5'd0;
		t <= 3'd0;
		tail <= 1'b0;
		gap <= 2'd0;
	end
	else if (step == 5'd14) begin
		step <= 5'd15;    // the last digit lands now
	end
	else begin
		// a write every fourth clock (rtc.v takes a request in one clock)
		gap <= gap + 2'd1;
		if (gap == 2'd0) begin
			wr <= 1'b1;
			if (!tail) begin
				{ adr0, data } <= wseq;
				if (n == 5'd27) tail <= 1'b1;
				n <= n + 5'd1;
			end
			else begin
				{ adr0, data } <= wtail;
				if (t == 3'd7) step <= 5'd0;
				t <= t + 3'd1;
			end
		end
	end
end

endmodule
