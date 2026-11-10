`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_tape.v

 The cassette of the MSX: a .cas file of the FL item "Tape" (file slot 3) in the SRAM from BASE (up
 to 2^AW bytes, 128 KB in the MSX2 core; the rest of a bigger file is dropped), played by tape (the CAS player of MiSTer MSX1,
 rtl/msx/tape.v) while the motor of the PPI is on.
 - The load does not reset the machine (as MiSTer: a CAS is loaded at the prompt of BASIC). Its bytes
   go to the SRAM through the aux port of msx_sram, which the disk image cache shares (one request
   in four to twelve clocks); the bursts of the mcu bring a byte every 11 clocks at 32 MHz, so they
   wait in a fifo, and pause stops the background fill of msx_fdd_cache during the load.
 - tape reads one byte with ram_rd (a pulse while buff_mem_ready) and takes it when buff_mem_ready
   is back, as from the DDR3 buffer of MiSTer. A byte past the end of the file reads as 0 (no CAS
   header there, the player stops searching at nothing).
 - rewind: a load, the OSD item "Tape rewind", the reset of the machine.
*/

module msx_tape #(
	parameter [21:0] BASE = 22'h3C0000,
	parameter AW = 17,              // the size of the tape in the SRAM: 2^AW bytes (at most 18)
	parameter TAPE_SILENT = 1000,   // of tape: shorter in the simulation
	parameter TAPE_SYNC = 1454
) (
	input wire clk,
	input wire ce_5m3,
	input wire motor,           // cas_motor of msx1: the PPI port C bit 4, 0 = the motor is on
	input wire rewind,

	// the file loader, file slot 3
	input wire load,            // a CAS file is being loaded
	input wire [31:0] file_addr,
	input wire [7:0] file_data,
	input wire file_wr,

	output wire cas_out,        // to cas_audio_in of msx1
	output wire loading,        // the file is not in the SRAM yet (fifo not empty): pause of the fdd fill

	// SRAM, aux port of msx_sram (through the arbiter of msx_system)
	output reg aux_req = 1'b0,
	output reg aux_we = 1'b0,
	output reg [21:0] aux_addr = 22'd0,
	output reg [7:0] aux_din = 8'd0,
	input wire aux_ack,
	input wire [7:0] aux_dout
);

// ---------------- the load

reg [18:0] len = 19'd0;   // the bytes of the file in the SRAM (2^AW at most)
reg load_d = 1'b0;
wire load_byte = load && file_wr && file_addr[31:AW] == 0;
always @(posedge clk) begin
	load_d <= load;
	if (load && !load_d)
		len <= 19'd0;
	else if (load_byte && { 1'b0, file_addr[17:0] } >= len)
		len <= { 1'b0, file_addr[17:0] } + 19'd1;
end

// a burst (512 bytes) fits in the fifo whole
wire fifo_empty;
wire [25:0] fifo_q;
reg fifo_rd = 1'b0;
reg fifo_q_valid = 1'b0;  // fifo_q holds a byte to write
kg_fifo #(.DW(26), .AW(9)) fifo (
	.clk(clk), .reset(1'b0),
	.wr(load_byte), .din({ file_addr[17:0], file_data }), .full(),
	.rd(fifo_rd), .dout(fifo_q), .empty(fifo_empty), .count()
);
assign loading = load || !fifo_empty || fifo_rd || fifo_q_valid || (aux_req && aux_we);

// ---------------- the player

wire [26:0] ram_a;
wire ram_rd;
reg [7:0] ram_di = 8'd0;
reg ready = 1'b1;
reg rd_pending = 1'b0;    // a read of the player waits for the aux port

tape #(.SILENT(TAPE_SILENT), .SYNC(TAPE_SYNC)) cass (
	.clk(clk),
	.ce_5m3(ce_5m3),
	.play(~motor),
	.rewind(rewind),
	.ram_a(ram_a),
	.ram_di(ram_di),
	.ram_rd(ram_rd),
	.buff_mem_ready(ready),
	.cas_out(cas_out)
);

wire past_end = ram_a[26:AW] != 0 || { 1'b0, ram_a[17:0] } >= len;

// ---------------- aux port: the writes of the load first, then the reads of the player

always @(posedge clk) begin
	// the next byte of the fifo comes while the write before it is in the aux port
	fifo_rd <= !fifo_empty && !fifo_rd && !fifo_q_valid;
	if (fifo_rd)
		fifo_q_valid <= 1'b1;

	if (ram_rd && ready) begin
		ready <= 1'b0;
		if (past_end)
			ram_di <= 8'd0;
		else
			rd_pending <= 1'b1;
	end
	else if (!ready && !rd_pending)
		ready <= 1'b1;    // past the end: the 0 is there one clock later

	if (aux_req) begin
		if (aux_ack) begin
			aux_req <= 1'b0;
			if (!aux_we) begin
				ram_di <= aux_dout;
				rd_pending <= 1'b0;
				ready <= 1'b1;
			end
		end
	end
	else if (fifo_q_valid) begin
		aux_req <= 1'b1;
		aux_we <= 1'b1;
		aux_addr <= BASE + { 4'd0, fifo_q[25:8] };
		aux_din <= fifo_q[7:0];
		fifo_q_valid <= 1'b0;
	end
	else if (rd_pending) begin
		aux_req <= 1'b1;
		aux_we <= 1'b0;
		aux_addr <= BASE + { 4'd0, ram_a[17:0] };
	end
end

endmodule
