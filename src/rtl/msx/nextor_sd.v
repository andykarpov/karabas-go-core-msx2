// karabas: not from the upstream. The SD interface of MSX1FPGA (msxsd.vhd, its Nextor driver
// SW/nextor/driver.asm unchanged) in slot 1, with an SD card emulated on a hard disk image of the
// file mounter (img_sdc) instead of an SPI master and a card.
//
// Page 1 of the slot (4000-7FFF) is a 16 KB bank of the Nextor ROM (128 KB in the SRAM, mem_*),
// the bank register is written at 6000. In bank 7: 7000-7AFF is RAM (written to the SRAM, the
// kernel keeps its data there), 7B00-7EFF the SPI data port, 7FF0 the status (read: bit 0 the
// image changed, 1 no image, 2 write protect) and the card select (write: bit 0, 0 = selected).
// rom_en = 0: the ROM reads FF (the registers stay), for test programs under C-BIOS.
//
// Each access of the data port is a byte exchange with the card, as the SPI master of msxsd:
// a write sends the byte, a read returns the byte of the exchange before and sends FF. The card
// is a state machine on bytes: the 6-byte commands CMD0/1/8/9/10/12/16/17/18/24/25/55/58 and
// ACMD23/41, an SDHC card (block addresses, OCR with CCS) of the size of the image. A sector comes
// from img_sdc (hd_rd / hd_wr, 5-40 ms through the mcu): the card answers FF (no data token yet)
// or 00 (busy after a write) meanwhile; the driver waits up to ~270 ms for a token and ~350 ms
// for the end of a write. The exchange is made at the end of a read (the CPU reads the byte of
// the exchange before) and at the start of a write.
module nextor_sd (
	input wire clk,
	input wire reset,
	input wire rom_en,
	// the CPU in slot 1
	input wire sltsl_n,           // slot 1 selected (a memory access) and the interface on
	input wire [15:0] addr,
	input wire [7:0] din,
	input wire rd_n,
	input wire wr_n,
	output wire sel,              // the interface answers (the data mux of msx1)
	output wire [7:0] dout,
	// the ROM and the RAM area in the SRAM
	output wire mem_sel,          // mem_addr = {4'b0000, 1'b1, mem_bank, addr[13:0]}
	output wire [2:0] mem_bank,
	output wire mem_we,
	input wire [7:0] mem_dout,
	// the image (img_sdc)
	input wire img_mounted,       // a pulse: img_size is the new size (0 = none)
	input wire [31:0] img_size,
	input wire img_wp,            // the image is write protected (the firmware does not write it)
	output reg hd_rd = 1'b0,
	output reg hd_wr = 1'b0,
	output reg [31:0] hd_lba = 32'd0,
	input wire hd_busy,           // img_sdc took the request (of this slot)
	input wire hd_done,           // its end (of this slot)
	input wire hd_byte_in_strobe, // a byte of a read sector (of this slot)
	input wire [8:0] hd_byte_addr,
	input wire [7:0] hd_byte_in_data,
	output wire [7:0] hd_byte_out_data
);

// ------------------------------------------------------------------ the bus

reg [2:0] bank = 3'd0;
wire page1 = ~sltsl_n & addr[15:14] == 2'b01;
wire b7 = bank == 3'd7;
wire spi_area = page1 & b7 & addr[13:0] >= 14'h3B00 & addr[13:0] <= 14'h3EFF;
wire ctl_area = page1 & b7 & addr[13:0] == 14'h3FF0;
wire ram_area = page1 & b7 & addr[13:0] >= 14'h3000 & addr[13:0] <= 14'h3AFF;

assign mem_bank = bank;
assign mem_sel = page1 & ~spi_area & ~ctl_area;
assign mem_we = ram_area & ~wr_n;

reg [7:0] rx = 8'hFF;         // the byte of the last exchange
reg changed = 1'b0;
reg mounted = 1'b0;
wire [7:0] status = { 5'd0, img_wp & mounted, ~mounted, changed };

assign sel = page1 & ~rd_n;
assign dout = spi_area ? rx : ctl_area ? status : rom_en ? mem_dout : 8'hFF;

reg rd_d = 1'b0, wr_d = 1'b0;
wire spi_rd = spi_area & ~rd_n;
wire spi_wr = spi_area & ~wr_n;
reg spi_rd_d = 1'b0;
reg cs_n = 1'b1;
reg xfer = 1'b0;              // one clock: an exchange of tx
reg [7:0] tx = 8'hFF;
reg ctl_rd_d = 1'b0;

always @(posedge clk) begin
	xfer <= 1'b0;
	spi_rd_d <= spi_rd;
	wr_d <= ~wr_n & page1;
	ctl_rd_d <= ctl_area & ~rd_n;
	if (reset) begin
		bank <= 3'd0;
		cs_n <= 1'b1;
	end else begin
		if (page1 & ~wr_n & ~wr_d) begin
			if (addr == 16'h6000)
				bank <= din[2:0];
			if (ctl_area)
				cs_n <= din[0];
			if (spi_area) begin
				tx <= din;
				xfer <= 1'b1;
			end
		end
		// a read: the exchange (FF) after it, the CPU has the byte of the one before
		if (spi_rd_d & ~spi_rd) begin
			tx <= 8'hFF;
			xfer <= 1'b1;
		end
	end
	// the image changed: up at a mount, down after a read of the status (as msxsd)
	if (img_mounted) begin
		mounted <= img_size != 32'd0;
		changed <= 1'b1;
	end else if (ctl_rd_d & ~(ctl_area & ~rd_n))
		changed <= 1'b0;
end

// ------------------------------------------------------------------ the sector buffer

// the request to img_sdc: pending until its end; a request whose block nobody wants any more
// (CMD12, a deselect, a reset) is stale: its end is not taken as the data of a new one
reg pending = 1'b0;
reg stale = 1'b0;

// port a: the card (buf_addr), port b: img_sdc (a read sector in, a written one out). The bytes of
// a stale read are not taken: they would come over a block the CPU is writing (CMD12 after CMD18,
// then CMD24: the block read ahead arrives while the new one is written)
reg [8:0] buf_addr = 9'd0;    // the byte of the card (read: the next one out, write: the next one in)
wire [7:0] buf_q;
reg buf_we = 1'b0;
reg [7:0] buf_wd = 8'h00;
kg_tdpram #(.DW(8), .AW(9)) sector (
	.clka(clk), .ena(1'b1), .wea(buf_we), .addra(buf_addr), .dina(buf_wd), .douta(buf_q),
	.clkb(clk), .enb(1'b1), .web(hd_byte_in_strobe & ~stale), .addrb(hd_byte_addr), .dinb(hd_byte_in_data),
	.doutb(hd_byte_out_data)
);

// ------------------------------------------------------------------ the card

localparam S_IDLE = 4'd0, S_CMD = 4'd1, S_RESP = 4'd2, S_RD_WAIT = 4'd3, S_RD_DATA = 4'd4,
	S_RD_CRC = 4'd5, S_WR_TOKEN = 4'd6, S_WR_DATA = 4'd7, S_WR_CRC = 4'd8, S_WR_RESP = 4'd9,
	S_WR_BUSY = 4'd10;

reg [3:0] state = S_IDLE;
reg [5:0] cmd = 6'd0;
reg [31:0] arg = 32'd0;
reg [2:0] cnt = 3'd0;         // the bytes of a command
reg [4:0] ridx = 5'd0;        // the byte of a response
reg idle = 1'b1;              // the idle bit of R1 (until ACMD41 / CMD1)
reg app = 1'b0;               // CMD55 before: an ACMD
reg acmd = 1'b0;              // the command is an ACMD
reg multi = 1'b0;             // CMD18 / CMD25
reg crc1 = 1'b0;              // the first CRC byte of a block was there

reg ready = 1'b0;             // the block of the read is in the buffer / the write is done
reg want = 1'b0;              // a request to make when img_sdc is free of the stale one
reg want_wr = 1'b0;

// C_SIZE of the CSD (version 2): (size / 512 KB) - 1
reg [31:0] size = 32'd0;
always @(posedge clk)
	if (img_mounted)
		size <= img_size;
wire [21:0] c_size = size[31:19] == 13'd0 ? 22'd0 : { 9'd0, size[31:19] } - 22'd1;

reg cmd_bad;
always @* begin
	case (cmd)
		6'd0, 6'd1, 6'd8, 6'd9, 6'd10, 6'd12, 6'd16, 6'd17, 6'd18, 6'd24, 6'd25, 6'd55, 6'd58: cmd_bad = 1'b0;
		default: cmd_bad = 1'b1;
	endcase
end
wire [7:0] r1 = { 5'd0, (acmd ? 1'b0 : cmd_bad), 1'b0, idle };

// the bytes of a response after R1 (ridx 1..): R7, OCR, the CSD / CID with their token and CRC
reg [7:0] resp;
reg [4:0] resp_len;           // the bytes of the response, R1 included
always @* begin
	resp = 8'hFF;
	resp_len = 5'd1;
	if (!acmd) case (cmd)
		6'd8: begin
			resp_len = 5'd5;
			case (ridx)
				5'd3: resp = { 4'd0, arg[11:8] };
				5'd4: resp = arg[7:0];
				default: resp = 8'h00;
			endcase
		end
		6'd58: begin
			resp_len = 5'd5;
			case (ridx)
				5'd1: resp = 8'hC0;   // powered up, CCS (SDHC)
				5'd2: resp = 8'hFF;
				5'd3: resp = 8'h80;
				default: resp = 8'h00;
			endcase
		end
		6'd9: begin
			resp_len = 5'd20;
			case (ridx)
				5'd1: resp = 8'hFE;
				5'd2: resp = 8'h40;   // CSD version 2
				5'd3: resp = 8'h0E;
				5'd4: resp = 8'h00;
				5'd5: resp = 8'h32;
				5'd6: resp = 8'h5B;
				5'd7: resp = 8'h59;   // READ_BL_LEN 9
				5'd8: resp = 8'h00;
				5'd9: resp = { 2'd0, c_size[21:16] };
				5'd10: resp = c_size[15:8];
				5'd11: resp = c_size[7:0];
				5'd12: resp = 8'h7F;
				5'd13: resp = 8'h80;
				5'd14: resp = 8'h0A;
				5'd15: resp = 8'h40;  // WRITE_BL_LEN 9
				5'd16: resp = 8'h00;
				5'd17: resp = 8'h01;
				default: resp = 8'hFF;
			endcase
		end
		6'd10: begin
			resp_len = 5'd20;
			case (ridx)
				5'd1: resp = 8'hFE;
				5'd2: resp = 8'h00;   // MID
				5'd3: resp = "K";     // OID
				5'd4: resp = "G";
				5'd5: resp = "M";     // PNM
				5'd6: resp = "S";
				5'd7: resp = "X";
				5'd8: resp = "H";
				5'd9: resp = "D";
				5'd10: resp = 8'h10;  // PRV 1.0
				5'd15: resp = 8'h01;  // MDT
				5'd16: resp = 8'h6A;
				5'd17: resp = 8'h01;
				5'd18, 5'd19: resp = 8'hFF;
				default: resp = 8'h00;
			endcase
		end
		default: ;
	endcase
end

// the byte the card gives in the exchange
reg [7:0] out;
always @* begin
	case (state)
		S_RESP: out = ridx == 5'd0 ? r1 : resp;
		S_RD_WAIT: out = ready ? 8'hFE : 8'hFF;
		S_RD_DATA: out = buf_q;
		S_WR_RESP: out = 8'h05;
		S_WR_BUSY: out = ready ? 8'hFF : 8'h00;
		default: out = 8'hFF;
	endcase
end

wire is_cmd = tx[7:6] == 2'b01;

always @(posedge clk) begin
	buf_we <= 1'b0;
	// img_sdc
	if (hd_busy) begin
		hd_rd <= 1'b0;
		hd_wr <= 1'b0;
	end
	if (hd_done) begin
		pending <= 1'b0;
		if (!stale)
			ready <= 1'b1;
		stale <= 1'b0;
	end
	if (want && !pending) begin
		want <= 1'b0;
		pending <= 1'b1;
		ready <= 1'b0;
		if (want_wr) hd_wr <= 1'b1; else hd_rd <= 1'b1;
	end

	if (reset) begin
		// the machine reset: the card is idle (the driver starts with CMD0 again)
		state <= S_IDLE;
		if (pending && !ready)
			stale <= 1'b1;
		want <= 1'b0;
		rx <= 8'hFF;
	end else if (xfer) begin
		rx <= cs_n ? 8'hFF : out;
		if (cs_n) begin
			// deselected: the card drops what it was doing
			state <= S_IDLE;
			if (pending && !ready)
				stale <= 1'b1;
			want <= 1'b0;
		end else case (state)
			S_IDLE, S_RD_WAIT: begin
				if (state == S_RD_WAIT && ready && !is_cmd) begin
					// the token went out: the data from byte 0 (buf_q)
					state <= S_RD_DATA;
				end else if (is_cmd) begin
					if (state == S_RD_WAIT) begin
						// CMD12 in a multiple block read: the block on its way is not wanted
						if (pending)
							stale <= 1'b1;
						want <= 1'b0;
					end
					cmd <= tx[5:0];
					acmd <= app;
					app <= 1'b0;
					cnt <= 3'd1;
					state <= S_CMD;
				end
			end
			S_CMD: begin
				if (cnt <= 3'd4)
					arg <= { arg[23:0], tx };
				if (cnt == 3'd5) begin
					// the CRC: the command is complete
					ridx <= 5'd0;
					state <= S_RESP;
					if (!acmd) case (cmd)
						6'd0: idle <= 1'b1;
						6'd1: idle <= 1'b0;
						6'd55: app <= 1'b1;
						default: ;
					endcase
					else if (cmd == 6'd41)
						idle <= 1'b0;
				end
				cnt <= cnt + 3'd1;
			end
			S_RESP: begin
				if (ridx == resp_len - 5'd1) begin
					state <= S_IDLE;
					if (!acmd && (cmd == 6'd17 || cmd == 6'd18)) begin
						hd_lba <= arg;
						multi <= cmd == 6'd18;
						want <= 1'b1;
						want_wr <= 1'b0;
						ready <= 1'b0;
						buf_addr <= 9'd0;
						state <= S_RD_WAIT;
					end
					if (!acmd && (cmd == 6'd24 || cmd == 6'd25)) begin
						hd_lba <= arg;
						multi <= cmd == 6'd25;
						state <= S_WR_TOKEN;
					end
				end
				ridx <= ridx + 5'd1;
			end
			S_RD_DATA: begin
				buf_addr <= buf_addr + 9'd1;
				if (buf_addr == 9'd511) begin
					// the last byte went out: the CRC
					crc1 <= 1'b0;
					state <= S_RD_CRC;
				end
			end
			S_RD_CRC: begin
				crc1 <= 1'b1;
				if (crc1) begin
					if (multi) begin
						hd_lba <= hd_lba + 32'd1;
						want <= 1'b1;
						want_wr <= 1'b0;
						ready <= 1'b0;
						buf_addr <= 9'd0;
						state <= S_RD_WAIT;
					end else
						state <= S_IDLE;
				end
			end
			S_WR_TOKEN: begin
				if (tx == 8'hFE || (multi && tx == 8'hFC)) begin
					buf_addr <= 9'd0;
					state <= S_WR_DATA;
				end else if (multi && tx == 8'hFD)
					state <= S_IDLE;
				else if (is_cmd) begin
					cmd <= tx[5:0];
					acmd <= app;
					app <= 1'b0;
					cnt <= 3'd1;
					state <= S_CMD;
				end
			end
			S_WR_DATA: begin
				buf_wd <= tx;
				buf_we <= 1'b1;
				if (buf_addr == 9'd511) begin
					crc1 <= 1'b0;
					state <= S_WR_CRC;
				end
			end
			S_WR_CRC: begin
				crc1 <= 1'b1;
				if (crc1) begin
					want <= 1'b1;
					want_wr <= 1'b1;
					ready <= 1'b0;
					state <= S_WR_RESP;
				end
			end
			S_WR_RESP: state <= S_WR_BUSY;
			S_WR_BUSY: begin
				if (ready) begin
					hd_lba <= hd_lba + 32'd1;
					state <= multi ? S_WR_TOKEN : S_IDLE;
				end
			end
			default: state <= S_IDLE;
		endcase
	end
	// the byte written above goes to buf_addr, then the address moves on
	if (buf_we)
		buf_addr <= buf_addr + 9'd1;
end

endmodule
