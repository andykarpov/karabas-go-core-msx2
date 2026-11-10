`timescale 1ns / 1ps
`default_nettype wire

/*
 msx2_rtc.v (karabas, own)

 The RP5C01 of the MSX2 (rtc.v of OCM-PLD) and the clock registers of kg_mcu in rtc_mode 0 of
 core.json (MC146818A) with eeprom_bank 4 (the 256 bytes of the core in /config/<id>.eep):
 - the firmware sends all 256 registers before the start of the core (busy): 0E..FF are the bytes
   of the .eep file; the time registers 0, 2, 4, 6..9 get .eep bytes too at the end of that, the
   time comes ~0.5 s after the start (and every 0.5 s), BCD or binary by DM (bit 2) of register B;
 - a register the core writes from 0E up is kept in the .eep (the firmware saves it a while later).

 Phase A, at start (the mcu is done): registers 40..4C and 50..5C (one nibble a byte) go to banks 2
 and 3 of the RP5C01, the CMOS of the MSX: the screen, the beep, the title, the password (the BIOS
 takes the block as valid by the ID nibble in register 0). Each nibble is read as it is written.
 Then bank 0.
 Phase B, TIME_DELAY clocks later: register B and the time registers are read (as BCD: one
 converter on the way in) and written to bank 0 (the year since 1980 = year mod 100 + 20:
 2000..2079; the week day 0..6 = MC146818 1..7 - 1), bank 1 gets 24 h and the leap counter (year
 mod 4), then the mode register and the register pointer the CPU had are written back (the BIOS
 may be using the chip by then).
 The writes go through the ports of rtc.v (wr: one clock, adr0: 0 the pointer B4, 1 the data B5),
 every other clock.
 After phase A the writes to rtc.v are watched (s_wr / s_adr0 / s_dbo, as rtc.v takes them): a
 nibble the CPU writes into bank 2 or 3 goes to kg_mcu (40 + register, 50 + register), so to the
 .eep. The time the CPU sets is not sent: the board keeps its own clock.
*/

module msx2_rtc #(
	parameter [25:0] TIME_DELAY = 26'd32000000   // ~0.75 s at 42.86 MHz
) (
	input wire clk,
	input wire start,            // a pulse: the mcu is done with its start
	// kg_mcu (RTC_A / RTC_DO / RTC_DI / RTC_CS / RTC_WR_N)
	output reg [7:0] rtc_a = 8'd0,
	input wire [7:0] rtc_do,
	output reg [7:0] rtc_di = 8'd0,
	output reg rtc_cs = 1'b0,
	output wire rtc_wr_n,
	// the writes to the RP5C01, one clock each
	output reg wr = 1'b0,
	output reg adr0 = 1'b0,
	output reg [7:0] data = 8'd0,
	output wire busy,
	// the writes rtc.v takes (its req & wrt, adr[0], dbo)
	input wire s_wr,
	input wire s_adr0,
	input wire [7:0] s_dbo
);

assign rtc_wr_n = !rtc_cs;

// ---------------------------------------------------------------- the time, read in phase B
// ri 0: register B, 1 sec, 2 min, 3 hour, 4 week, 5 day, 6 month, 7 year
function [7:0] t_addr(input [2:0] i);
	case (i)
		3'd0: t_addr = 8'h0B; 3'd1: t_addr = 8'h00; 3'd2: t_addr = 8'h02; 3'd3: t_addr = 8'h04;
		3'd4: t_addr = 8'h06; 3'd5: t_addr = 8'h07; 3'd6: t_addr = 8'h08; default: t_addr = 8'h09;
	endcase
endfunction

reg binary = 1'b0;           // DM of register B
reg [2:0] rd_i = 3'd0;       // the register of rtc_do (a clock after its address)
// the value 0..99 of rtc_do; the year: 0..79 + 20
wire [6:0] v_in = binary ? rtc_do[6:0] : { 3'd0, rtc_do[7:4] } * 7'd10 + { 3'd0, rtc_do[3:0] };
wire [6:0] v_yy = v_in > 7'd79 ? 7'd79 : v_in;
wire [6:0] v = rd_i == 3'd7 ? v_yy + 7'd20 : v_in;
wire [3:0] v10 = v >= 7'd90 ? 4'd9 : v >= 7'd80 ? 4'd8 : v >= 7'd70 ? 4'd7 : v >= 7'd60 ? 4'd6 : v >= 7'd50 ? 4'd5 :
                 v >= 7'd40 ? 4'd4 : v >= 7'd30 ? 4'd3 : v >= 7'd20 ? 4'd2 : v >= 7'd10 ? 4'd1 : 4'd0;
wire [6:0] v1 = v - { 3'd0, v10 } * 7'd10;

reg [7:0] tm [1:7];          // BCD; 4 the week day 0..6
reg [1:0] leap = 2'd0;

// ---------------------------------------------------------------- the register writes
// k: phase A 0..28, phase B 32..50 (50: the pointer only)
reg [5:0] k = 6'd0;
reg [3:0] sv_d = 4'd8, sv_ptr = 4'd0;    // the mode register and the pointer of the CPU
reg [3:0] w_reg;
reg [3:0] w_val;
reg [7:0] w_src;             // phase A: the kg_mcu register of the nibble
always @* begin
	w_reg = 4'd13; w_val = 4'd8; w_src = 8'h40;
	if (k == 6'd0) begin w_reg = 4'd13; w_val = 4'hA; end
	else if (k <= 6'd13) begin w_reg = k[3:0] - 4'd1; w_val = rtc_do[3:0]; w_src = 8'h3F + { 2'd0, k }; end    // 40..4C
	else if (k == 6'd14) begin w_reg = 4'd13; w_val = 4'hB; end
	else if (k <= 6'd27) begin w_reg = k[3:0] - 4'd15; w_val = rtc_do[3:0]; w_src = 8'h41 + { 2'd0, k }; end   // 50..5C
	else case (k)
		6'd33: begin w_reg = 4'd0; w_val = tm[1][3:0]; end
		6'd34: begin w_reg = 4'd1; w_val = tm[1][7:4]; end
		6'd35: begin w_reg = 4'd2; w_val = tm[2][3:0]; end
		6'd36: begin w_reg = 4'd3; w_val = tm[2][7:4]; end
		6'd37: begin w_reg = 4'd4; w_val = tm[3][3:0]; end
		6'd38: begin w_reg = 4'd5; w_val = tm[3][7:4]; end
		6'd39: begin w_reg = 4'd6; w_val = tm[4][3:0]; end
		6'd40: begin w_reg = 4'd7; w_val = tm[5][3:0]; end
		6'd41: begin w_reg = 4'd8; w_val = tm[5][7:4]; end
		6'd42: begin w_reg = 4'd9; w_val = tm[6][3:0]; end
		6'd43: begin w_reg = 4'd10; w_val = tm[6][7:4]; end
		6'd44: begin w_reg = 4'd11; w_val = tm[7][3:0]; end
		6'd45: begin w_reg = 4'd12; w_val = tm[7][7:4]; end
		6'd46: begin w_reg = 4'd13; w_val = 4'd9; end            // bank 1
		6'd47: begin w_reg = 4'd10; w_val = 4'd1; end            // 24 h
		6'd48: begin w_reg = 4'd11; w_val = { 2'd0, leap }; end
		6'd49: begin w_reg = 4'd13; w_val = sv_d; end
		6'd50: begin w_reg = sv_ptr; w_val = 4'd0; end           // the pointer only
		default: begin w_reg = 4'd13; w_val = 4'd8; end          // 28, 32: bank 0
	endcase
end

localparam [1:0] S_IDLE = 2'd0, S_READ = 2'd1, S_WRITE = 2'd2;
reg [1:0] st = S_IDLE;
reg wait_b = 1'b0;           // phase B to come
reg ready = 1'b0;            // phase A done: the CPU writes go to the mcu
reg [25:0] cnt = 26'd0;
reg [2:0] ri = 3'd0;
reg rd_v = 1'b0;
reg half = 1'b0;             // 0 the pointer, 1 the data
reg gap = 1'b0;
assign busy = st != S_IDLE;
wire go_a = st == S_IDLE && start;
wire go_b = st == S_IDLE && !start && wait_b && cnt == TIME_DELAY;

// the watch: the pointer and the mode register of rtc.v
reg [3:0] p_ptr = 4'd0;
reg [3:0] p_d = 4'd8;

always @(posedge clk) begin
	wr <= 1'b0;
	rd_v <= 1'b0;
	rtc_cs <= 1'b0;
	if (rd_v) begin
		if (rd_i == 3'd0) binary <= rtc_do[2];
		else if (rd_i == 3'd4) tm[4] <= { 5'd0, rtc_do[2:0] == 3'd0 ? 3'd0 : rtc_do[2:0] - 3'd1 };
		else tm[rd_i] <= { v10, v1[3:0] };
		if (rd_i == 3'd7) leap <= v_yy[1:0];
	end
	if (wait_b && st == S_IDLE) cnt <= cnt + 26'd1;
	case (st)
		S_IDLE:
			if (go_a) begin
				st <= S_WRITE;
				k <= 6'd0;
				wait_b <= 1'b1;
				ready <= 1'b0;
				cnt <= 26'd0;
				half <= 1'b0;
				gap <= 1'b0;
			end
			else if (go_b) begin
				st <= S_READ;
				ri <= 3'd0;
				rtc_a <= t_addr(3'd0);
			end
		S_READ: begin
			// one register a clock: rtc_do of rtc_a comes a clock later
			rd_v <= 1'b1;
			rd_i <= ri;
			if (ri == 3'd7) begin
				st <= S_WRITE;
				k <= 6'd32;
				sv_d <= p_d;
				sv_ptr <= p_ptr;
				half <= 1'b0;
				gap <= 1'b0;
			end
			else begin
				ri <= ri + 3'd1;
				rtc_a <= t_addr(ri + 3'd1);
			end
		end
		default: begin
			// a port write every other clock; phase A: the nibble of k is at rtc_do by its data write
			// (the last read of phase B lands in the first clock here)
			rtc_a <= w_src;
			gap <= ~gap;
			if (gap) begin
				wr <= 1'b1;
				adr0 <= half;
				data <= { 4'd0, half ? w_val : w_reg };
				half <= ~half;
				if (half || k == 6'd50) begin
					half <= 1'b0;
					k <= k + 6'd1;
					if (k == 6'd28 || k == 6'd50) begin
						st <= S_IDLE;
						ready <= 1'b1;
						if (k == 6'd50) wait_b <= 1'b0;
					end
				end
			end
		end
	endcase

	// the watch (of these writes too: the pointer and the mode register stay those of rtc.v)
	if (s_wr) begin
		if (!s_adr0)
			p_ptr <= s_dbo[3:0];
		else begin
			if (p_ptr == 4'd13) p_d <= s_dbo[3:0];
			if (ready && !busy && !go_a && !go_b && p_d[1] && p_ptr <= 4'd12) begin
				rtc_cs <= 1'b1;
				rtc_a <= { 3'b010, p_d[0], p_ptr };   // 40 + ptr, 50 + ptr
				rtc_di <= { 4'd0, s_dbo[3:0] };
			end
		end
	end
end

endmodule
