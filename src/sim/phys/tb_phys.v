`timescale 1ns / 1ps

/*
 tb_phys.v

 The physical floppy drives of the Karabas Go: vy0010 (PHYS 1: wd1793 for the image, msx_fdc_phys with
 the VG93 model for the physical drives) on clk_sys 42.857 MHz, with two drive models at the pins
 (fdd_model.v of the PCXT core: high = active, an IBM track at 250 kbit/s, jitter, STEP / DIR timing
 checked, the written data decoded back into the image). The CPU side is the bus of the MSX slot as
 the Z80 at 3.58 MHz drives it (memory accesses to 7FF8..7FFF), the commands as the disk ROM gives them:
 - drive A = DS0 (2 heads, the disk turning at SPEED): Restore from cylinder 5, Seek 2, Read Sector of
   side 1, Write Sector of side 0 and its read back, Write Track (a format of cylinder 3 as FORMAT of
   MSX-DOS writes it: E5 in the data fields) and a read of a formatted sector, Read Address;
 - drive B = DS1 (1 head, write protected): Restore from cylinder 2, Read Sector, Write Sector
   refused (status WP, nothing written);
 - routing: drive A on the image (phys_a 0) goes to wd1793, the VG93 keeps its track register; a
   Force Interrupt with no drive selected ends a command of the VG93; the pins with no drive selected.
 Runs in verilator (--timing, sim/phys/run_phys.sh), about 10 s. Ends with "tb_phys: N errors".
*/

module tb_phys;

// drive A: the disk turns SPEED times slower (+speed=F at run time: the cell time of the model is set
// before its first cell)
real speed = 1.0;
initial begin
	if ($value$plusargs("speed=%f", speed)) ;
	#1 drv_a.cell_ns = 100 * 20.0 * speed;
	$display("tb_phys: drive A speed %0.3f", speed);
end

reg clk = 1'b0;
always #11.667 clk = ~clk;           // 42.857 MHz
reg [3:0] cediv = 4'd0;
reg clk_en = 1'b0;
always @(posedge clk) begin
	cediv <= (cediv == 4'd11) ? 4'd0 : cediv + 4'd1;
	clk_en <= cediv == 4'd0;
end

reg reset = 1'b1;
reg [15:0] addr = 16'h0000;
reg [7:0] dout = 8'hFF;
wire [7:0] din;
reg stlsl_n = 1'b1, wr_n = 1'b1, rd_n = 1'b1;
reg [1:0] phys_a = 2'd0, phys_b = 2'd0;
wire [3:0] fdd_in, in_a, in_b;
wire [7:0] fdd_out;
assign fdd_in = in_a | in_b;

vy0010 #(.PHYS(1)) dut (
	.clk(clk), .clk_en(clk_en), .reset(reset),
	.addr(addr), .d_from_cpu(dout), .d_to_cpu(din),
	.stlsl_n(stlsl_n), .wr_n(wr_n), .rd_n(rd_n), .CS1_n(1'b1), .rom_en(1'b1),
	.img_mounted(1'b0), .img_size(32'd0), .img_wp(1'b0),
	.sd_lba(), .sd_rd(), .sd_wr(), .sd_ack(1'b0), .sd_buff_addr(9'd0), .sd_buff_dout(8'd0),
	.sd_buff_din(), .sd_buff_wr(1'b0), .sd_din_strobe(1'b0),
	.phys_a(phys_a), .phys_b(phys_b), .fdd_in(fdd_in), .fdd_out(fdd_out)
);

localparam integer SPT = 3, GAP3 = 40, TRK = 2100;   // a short track: 67 ms a revolution
fdd_model #(.DS(0), .CELL(100), .SPT(SPT), .HEADS(2), .CYLS(80), .GAP3(GAP3), .TRK_BYTES(TRK),
	.SPEED(1.0), .CYL0(5)) drv_a (.fdd_out(fdd_out), .fdd_in(in_a));
fdd_model #(.DS(1), .CELL(100), .SPT(SPT), .HEADS(1), .CYLS(80), .GAP3(GAP3), .TRK_BYTES(TRK),
	.SPEED(0.99), .CYL0(2)) drv_b (.fdd_out(fdd_out), .fdd_in(in_b));

integer errors = 0;
task check;
	input ok;
	input [8*64-1:0] what;
	begin
		if (!ok) begin
			errors = errors + 1;
			$display("%t ERROR: %0s", $realtime, what);
		end
	end
endtask

// ---- the bus of the Z80 at 3.58 MHz (a T state 280 ns): a memory write / read of the slot ----
task wr;
	input [15:0] a;
	input [7:0] v;
	begin
		addr = a; dout = v; stlsl_n = 1'b0;
		#280 wr_n = 1'b0;
		#420 wr_n = 1'b1;
		#140 stlsl_n = 1'b1;
		#280;
	end
endtask
reg [7:0] q;
task rd;
	input [15:0] a;
	begin
		addr = a; stlsl_n = 1'b0;
		#140 rd_n = 1'b0;
		#560 q = din;
		rd_n = 1'b1;
		#140 stlsl_n = 1'b1;
		#140;
	end
endtask

// the time between two register writes of the disk ROM (its EX (SP),HL delays)
task pause;
	begin
		#15000;
	end
endtask

// wait for INTRQ (7FFF bit 6 low), then the status
reg [7:0] st;
integer n;
task wait_int;
	input integer ms;
	begin
		n = 0;
		rd(16'h7FFF);
		while (q[6] && n < ms * 1000) begin
			rd(16'h7FFF);
			n = n + 1;
		end
		check(!q[6], "INTRQ timeout");
		rd(16'h7FF8);
		st = q;
	end
endtask

// a command
task cmd;
	input [7:0] c;
	begin
		wr(16'h7FF8, c);
		#30000;
	end
endtask

// Type II / III data: DRQ (7FFF bit 7 low) moves a byte, INTRQ ends
reg [7:0] dbuf [0:8191];
integer cnt;
task xfer;
	input wr_dir;          // 1: the CPU writes
	input integer ms;
	begin
		cnt = 0;
		n = 0;
		rd(16'h7FFF);
		while (q[6] && n < ms * 1000) begin
			if (!q[7]) begin
				if (wr_dir) wr(16'h7FFB, dbuf[cnt]);
				else begin rd(16'h7FFB); dbuf[cnt] = q; end
				cnt = cnt + 1;
			end
			rd(16'h7FFF);
			n = n + 1;
		end
		check(!q[6], "INTRQ timeout in a transfer");
		rd(16'h7FF8);
		st = q;
	end
endtask

function [7:0] pat;               // the data of the drive model
	input integer c, h, r, i;
	pat = (c * 7 + h * 13 + r * 3 + i) & 255;
endfunction

integer i, s, bad, p, wr0;
initial begin
	#200000 reset = 1'b0;            // long, as at the start of the core (the model gives a WG pulse after a short one)
	#2000;

	// ---------------- drive A on DS0 ----------------
	phys_a = 2'd1;
	phys_b = 2'd2;
	wr(16'h7FFD, 8'hC4);              // motor on, drive A
	#100000;
	check(fdd_out[0] && !fdd_out[1] && fdd_out[2], "A: DS0 and the motor");

	cmd(8'h00);                        // Restore, 6 ms
	wait_int(400);
	check(drv_a.cyl == 0, "A: Restore, the head not on cylinder 0");
	check(st[2], "A: Restore, no TR00 in the status");
	check(drv_a.short_steps == 0, "A: Restore, steps lost (STEP / DIR timing)");
	rd(16'h7FF9);
	check(q == 8'd0, "A: Restore, track register");

	wr(16'h7FFB, 8'd2); pause;         // Seek 2
	cmd(8'h10);
	wait_int(200);
	check(drv_a.cyl == 2, "A: Seek, the head not on cylinder 2");
	rd(16'h7FF9);
	check(q == 8'd2, "A: Seek, track register");

	wr(16'h7FFC, 8'h01); pause;        // side 1, sector 2
	wr(16'h7FFA, 8'd2); pause;
	cmd(8'h80);                        // Read Sector
	xfer(1'b0, 400);
	check(st == 8'h00, "A: Read Sector, status");
	check(cnt == 512, "A: Read Sector, not 512 bytes");
	bad = 0;
	for (i = 0; i < 512; i = i + 1)
		if (dbuf[i] != pat(2, 1, 2, i)) bad = bad + 1;
	check(bad == 0, "A: Read Sector, wrong data (side 1)");
	$display("%t A read C2 H1 R2: status %02x, %0d bytes, %0d wrong", $realtime, st, cnt, bad);

	wr(16'h7FFC, 8'h00); pause;        // side 0, sector 3: Write Sector
	wr(16'h7FFA, 8'd3); pause;
	for (i = 0; i < 512; i = i + 1) dbuf[i] = (i * 5 + 1) & 255;
	wr0 = drv_a.data_writes;
	cmd(8'hA0);
	xfer(1'b1, 400);
	check(st == 8'h00, "A: Write Sector, status");
	check(cnt == 512, "A: Write Sector, not 512 bytes");
	check(drv_a.data_writes == wr0 + 1, "A: Write Sector, the drive got no data field");
	check(drv_a.crc_errs == 0, "A: Write Sector, a CRC error at the drive");
	bad = 0;
	for (i = 0; i < 512; i = i + 1)
		if (drv_a.img[((2 * 2 + 0) * SPT + 3 - 1) * 512 + i] != ((i * 5 + 1) & 255)) bad = bad + 1;
	check(bad == 0, "A: Write Sector, the image of the drive differs");
	for (i = 0; i < 512; i = i + 1) dbuf[i] = 8'h00;
	cmd(8'h80);                        // and read it back
	xfer(1'b0, 400);
	bad = 0;
	for (i = 0; i < 512; i = i + 1)
		if (dbuf[i] != ((i * 5 + 1) & 255)) bad = bad + 1;
	check(st == 8'h00 && cnt == 512 && bad == 0, "A: read back of the written sector");
	$display("%t A write + read C2 H0 R3: status %02x, %0d bytes, %0d wrong", $realtime, st, cnt, bad);

	// Write Track of cylinder 3, side 0: the track of the format of MSX-DOS (E5 in the data fields)
	wr(16'h7FFB, 8'd3); pause;
	cmd(8'h10);
	wait_int(200);
	p = 0;
	for (i = 0; i < 80; i = i + 1) begin dbuf[p] = 8'h4E; p = p + 1; end
	for (i = 0; i < 12; i = i + 1) begin dbuf[p] = 8'h00; p = p + 1; end
	for (i = 0; i < 3; i = i + 1) begin dbuf[p] = 8'hF6; p = p + 1; end
	dbuf[p] = 8'hFC; p = p + 1;
	for (i = 0; i < 50; i = i + 1) begin dbuf[p] = 8'h4E; p = p + 1; end
	for (s = 1; s <= SPT; s = s + 1) begin
		for (i = 0; i < 12; i = i + 1) begin dbuf[p] = 8'h00; p = p + 1; end
		for (i = 0; i < 3; i = i + 1) begin dbuf[p] = 8'hF5; p = p + 1; end
		dbuf[p] = 8'hFE; dbuf[p + 1] = 8'd3; dbuf[p + 2] = 8'd0; dbuf[p + 3] = s; dbuf[p + 4] = 8'd2;
		dbuf[p + 5] = 8'hF7; p = p + 6;
		for (i = 0; i < 22; i = i + 1) begin dbuf[p] = 8'h4E; p = p + 1; end
		for (i = 0; i < 12; i = i + 1) begin dbuf[p] = 8'h00; p = p + 1; end
		for (i = 0; i < 3; i = i + 1) begin dbuf[p] = 8'hF5; p = p + 1; end
		dbuf[p] = 8'hFB; p = p + 1;
		for (i = 0; i < 512; i = i + 1) begin dbuf[p] = 8'hE5; p = p + 1; end
		dbuf[p] = 8'hF7; p = p + 1;
		for (i = 0; i < GAP3; i = i + 1) begin dbuf[p] = 8'h4E; p = p + 1; end
	end
	for (i = p; i < 8192; i = i + 1) dbuf[i] = 8'h4E;
	wr0 = drv_a.data_writes;
	cmd(8'hF0);
	xfer(1'b1, 400);
	wait (!fdd_out[6]);                // WG ends a microword after INTRQ
	#1000;
	check(st == 8'h00, "A: Write Track, status");
	check(drv_a.fmt_ids == SPT, "A: Write Track, the drive did not get the IDs from the index");
	check(drv_a.data_writes == wr0 + SPT, "A: Write Track, the drive did not get the data fields");
	check(drv_a.crc_errs == 0, "A: Write Track, a CRC error at the drive");
	$display("%t A write track C3 H0: status %02x, %0d bytes, %0d IDs, %0d data fields", $realtime, st, cnt,
		drv_a.fmt_ids, drv_a.data_writes - wr0);
	wr(16'h7FFA, 8'd2); pause;
	cmd(8'h80);
	xfer(1'b0, 400);
	bad = 0;
	for (i = 0; i < 512; i = i + 1)
		if (dbuf[i] != 8'hE5) bad = bad + 1;
	check(st == 8'h00 && cnt == 512 && bad == 0, "A: read of a formatted sector");

	cmd(8'hC0);                        // Read Address: C H R N CRC
	xfer(1'b0, 400);
	check(st == 8'h00 && cnt == 6 && dbuf[0] == 8'd3 && dbuf[1] == 8'd0 && dbuf[3] == 8'd2,
		"A: Read Address");
	$display("%t A read address: status %02x, %02x %02x %02x %02x", $realtime, st, dbuf[0], dbuf[1], dbuf[2], dbuf[3]);

	// ---------------- drive B on DS1: one head, write protected ----------------
	drv_b.wprot = 1'b1;
	wr(16'h7FFD, 8'hC5);              // motor on, drive B
	#100000;
	check(!fdd_out[0] && fdd_out[1], "B: DS1");
	cmd(8'h00);
	wait_int(400);
	check(drv_b.cyl == 0 && st[2], "B: Restore");
	check(st[6], "B: write protect not in the status");
	wr(16'h7FFA, 8'd1); pause;
	cmd(8'h80);
	xfer(1'b0, 400);
	bad = 0;
	for (i = 0; i < 512; i = i + 1)
		if (dbuf[i] != pat(0, 0, 1, i)) bad = bad + 1;
	check(st == 8'h00 && cnt == 512 && bad == 0, "B: Read Sector");
	$display("%t B read C0 H0 R1: status %02x, %0d bytes, %0d wrong", $realtime, st, cnt, bad);
	wr0 = drv_b.data_writes;
	cmd(8'hA0);
	xfer(1'b1, 400);
	check(st[6] && cnt == 0, "B: Write Sector on a protected disk not refused");
	check(drv_b.data_writes == wr0, "B: a protected disk was written");

	// ---------------- routing ----------------
	// drive A on the image: wd1793 takes the accesses, the VG93 keeps its track register (0: the last
	// command of the VG93 was the Restore of drive B; one controller for both physical drives, as on the
	// VY-0010, the disk ROM keeps the track of each drive)
	phys_a = 2'd0;
	wr(16'h7FFD, 8'hC4);
	#2000;
	check(fdd_out[1:0] == 2'b00, "image A: a physical drive selected");
	wr(16'h7FF9, 8'h55); pause;
	rd(16'h7FF9);
	check(q == 8'h55, "image A: the track register of wd1793");
	phys_a = 2'd1;
	#2000;
	rd(16'h7FF9);
	check(q == 8'd0, "physical A: the VG93 saw an access of the image drive");

	// a Force Interrupt with no drive selected ends the search of the VG93 for a sector it does not find
	wr(16'h7FFA, 8'd9); pause;
	cmd(8'h80);
	rd(16'h7FF8);
	check(q[0], "A: Read Sector of a missing sector not busy");
	wr(16'h7FFD, 8'h03);              // no drive, the motor off
	#2000;
	check(fdd_out[1:0] == 2'b00 && !fdd_out[2], "no drive: the pins not idle");
	cmd(8'hD0);
	wr(16'h7FFD, 8'hC4);
	// the VG93 ends the command some 70 us after the Force Interrupt; without it the search would go on
	// for five revolutions (335 ms)
	n = 0;
	rd(16'h7FF8);
	while (q[0] && n < 2000) begin rd(16'h7FF8); n = n + 1; end
	check(!q[0], "Force Interrupt with no drive selected did not reach the VG93");

	$display("tb_phys: %0d errors", errors);
	$finish;
end

initial begin
	#(3.0e9);
	$display("tb_phys: time out");
	$display("tb_phys: %0d errors", errors + 1);
	$finish;
end

endmodule
