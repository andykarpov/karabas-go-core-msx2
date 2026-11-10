`timescale 1ns / 1ps
`default_nettype wire

/*
 msx_sram.v

 The SRAM of the board (two byte lanes of 2M x 8, 10 ns, asynchronous) as one byte port of the
 machine: a byte address of 22 bits (MA = addr[21:1], the lane by addr[0]: MWR_N[0] / MD[7:0] for
 even bytes, as the NES core has it). /OE (MRD_N) is tied low by the top.

 Slots of two clocks (clk 42.857 MHz: one clock, 23.3 ns, is less than the address out, tAA and
 the data in; two are 46.7 ns, TS_SRAM_OUT / TS_SRAM_IN of the ucf bound the pads):
 - the first edge of a slot takes the address (and a pending write) into the address registers;
 - a read slot takes MD at the first edge of the next slot (two clocks after the address), dout
   is the byte of its lane one clock later;
 - a write slot pulls /WE low and drives MD from the falling edge of its first clock to the
   falling edge of its second clock, so the address is stable half a clock before and after /WE.
 The SRAM is read all the time at addr: dout follows a change of addr within seven clocks (the
 port goes through a register first), which is far less than the access of the Z80 (an M1 read
 takes the data two T-states, 24 clocks, after the address). The machine and the loaders hold
 addr while they read.

 we is a level or a pulse: the rising edge requests one write of din at addr (taken at that
 edge; both must hold until then). A write waits for the next slot, at most two clocks; the
 writers here write once in 10 clocks or less often (the loaders of the mcu, the Z80).

 The aux port (the disk image cache, msx_fdd_cache): aux_req held with aux_addr / aux_we /
 aux_din until aux_ack (one clock; with a read aux_dout is the byte then). The slots alternate
 between the machine and the aux port; a slot of the aux port without a request is the
 machine's. With requests all the time, the machine has every other slot: its reads take up to
 nine clocks, under a T-state of the Z80 (12); a request of the aux port takes four to six.

 The VDP port (karabas-go-core-msx2): the ESE-VDP on clk21 (clk / 2, rising edges together) has
 one VRAM access per 4 clocks of clk21 while its vdp_dlclk is 1 (DOTSTATE 00 and 01): the address
 (vdp_addr: the word address, bit 16 the byte of a write) and vdp_we_n change at the edge where
 vdp_dlclk rises, the VDP takes vdp_din at the edge 4 clocks of clk later. The first clock after
 that rise starts a slot of the VDP (the slots are aligned to it: a slot starts there whatever the
 phase was, which matters at the start only): MA = VRAM_BASE + the word, a read takes MD two clocks
 later into vdp_din (16 bits, held until the next read of the VDP), a write writes vdp_dout to the
 byte of bit 16. Every fourth slot is the VDP's, the others are shared as before: the reads of the
 machine take up to thirteen clocks then, under the two T-states (24 clocks) of an M1 read.
*/

module msx_sram #(
	parameter [20:0] VRAM_BASE = 21'h1E0000   // the word address of the VRAM: byte 3C0000
) (
	input wire clk,

	input wire [21:0] addr,
	input wire we,
	input wire [7:0] din,
	output reg [7:0] dout = 8'hFF,

	input wire aux_req,
	input wire aux_we,
	input wire [21:0] aux_addr,
	input wire [7:0] aux_din,
	output reg aux_ack = 1'b0,
	output reg [7:0] aux_dout = 8'hFF,

	input wire vdp_dlclk,
	input wire [16:0] vdp_addr,
	input wire vdp_we_n,
	input wire [7:0] vdp_dout,
	output reg [15:0] vdp_din = 16'hFFFF,

	output reg [20:0] MA = 21'd0,
	inout wire [15:0] MD,
	output wire [1:0] MWR_N
);

reg phase = 1'b0;    // 0: the first clock of a slot
reg we_d = 1'b0;
reg wr_pend = 1'b0;
reg [21:0] wr_addr = 22'd0;
reg [7:0] wr_data = 8'd0;

reg s_we = 1'b0;     // the slot is a write
reg s_lane = 1'b0;   // addr[0] of the slot
reg s_read = 1'b0;   // the slot is a read
reg [7:0] s_data = 8'd0;  // the byte of a write slot
reg [15:0] md_q = 16'hFFFF;  // MD at the first edge of the next slot (an IOB register)
reg q_valid = 1'b0, q_lane = 1'b0;
reg s_aux = 1'b0;    // the slot is the aux port's
reg q_aux = 1'b0;
reg aux_turn = 1'b0; // the next slot may go to the aux port
reg aux_busy = 1'b0; // an aux request is in a slot, not acked yet
reg s_vdp = 1'b0;    // the slot is a read of the VDP
reg dl_d = 1'b0;
wire vdp_go = vdp_dlclk && !dl_d;   // the first clock of vdp_dlclk: a slot of the VDP starts
wire slot_start = !phase || vdp_go;

// the port of the machine through a register: its address is the end of a long path (the T80,
// the address decoding and the mappers of msx1, 11 levels of logic) and took the clock alone
reg [21:0] addr_q = 22'd0;
reg we_q = 1'b0;
reg [7:0] din_q = 8'd0;

always @(posedge clk) begin
	addr_q <= addr;
	we_q <= we;
	din_q <= din;
	phase <= slot_start;   // 1: the second clock of a slot
	dl_d <= vdp_dlclk;
	we_d <= we_q;

	// a write request: taken at the rising edge of we
	if (we_q && !we_d) begin
		wr_pend <= 1'b1;
		wr_addr <= addr_q;
		wr_data <= din_q;
	end

	// the requester changes aux_addr / aux_req at the edge where it sees aux_ack: a slot that starts
	// at that edge would take the request just served, so aux_busy ends one clock after the ack
	if (aux_ack)
		aux_busy <= 1'b0;
	aux_ack <= 1'b0;

	// the byte of the read slot before, one clock after its MD was taken
	if (q_valid) begin
		if (q_aux) begin
			aux_dout <= q_lane ? md_q[15:8] : md_q[7:0];
			aux_ack <= 1'b1;
		end
		else
			dout <= q_lane ? md_q[15:8] : md_q[7:0];
	end
	q_valid <= 1'b0;

	if (slot_start) begin
		// the first edge of a slot: MD of the slot before (two clocks after its address)
		md_q <= MD;
		if (s_vdp)
			vdp_din <= MD;
		q_valid <= s_read;
		q_lane <= s_lane;
		q_aux <= s_aux;
		if (s_aux && s_we)
			aux_ack <= 1'b1;   // an aux write ends with its slot
		s_aux <= 1'b0;
		s_vdp <= 1'b0;
		if (!vdp_go)
			aux_turn <= ~aux_turn;
		if (vdp_go) begin
			MA <= VRAM_BASE | { 5'd0, vdp_addr[15:0] };
			s_lane <= vdp_addr[16];
			s_we <= !vdp_we_n;
			s_data <= vdp_dout;
			s_read <= 1'b0;
			s_vdp <= vdp_we_n;
		end
		else if (aux_turn && aux_req && !aux_busy) begin
			MA <= aux_addr[21:1];
			s_lane <= aux_addr[0];
			s_we <= aux_we;
			s_data <= aux_din;
			s_read <= !aux_we;
			s_aux <= 1'b1;
			aux_busy <= 1'b1;
		end
		else if (wr_pend && !(we_q && !we_d)) begin
			MA <= wr_addr[21:1];
			s_lane <= wr_addr[0];
			s_we <= 1'b1;
			s_data <= wr_data;
			s_read <= 1'b0;
			wr_pend <= 1'b0;
		end
		else begin
			MA <= addr_q[21:1];
			s_lane <= addr_q[0];
			s_we <= 1'b0;
			s_read <= 1'b1;
		end
	end
end

// /WE and the write data on the falling edges, from the first clock of the slot to the second
reg [1:0] we_n = 2'b11;
reg [15:0] md_out = 16'd0;
always @(negedge clk) begin
	we_n <= 2'b11;
	if (s_we && phase) begin  // phase is 1 in the first clock of a slot
		we_n <= s_lane ? 2'b01 : 2'b10;
		md_out <= {s_data, s_data};
	end
end
assign MWR_N = we_n;
assign MD[7:0] = !we_n[0] ? md_out[7:0] : 8'bz;
assign MD[15:8] = !we_n[1] ? md_out[15:8] : 8'bz;

endmodule
