// karabas: PHYS = 1 (Karabas Go): the physical floppy drives on the VG93 model (msx_fdc_phys), see below
module vy0010 #(parameter PHYS = 0)
(
   input            clk,
   input            clk_en,
   input            reset,
   input     [15:0] addr,
   input      [7:0] d_from_cpu,
   output     [7:0] d_to_cpu,
   input            stlsl_n,
   input            wr_n,
   input            rd_n,
   input            CS1_n,
   input            rom_en,  // karabas: the disk ROM answers (0: the FDC registers only, for C-BIOS)
   input            img_mounted,
   input     [31:0] img_size,
   input            img_wp,
   output    [31:0] sd_lba,
   output           sd_rd,
   output           sd_wr,
   input            sd_ack,
   input      [8:0] sd_buff_addr,
   input      [7:0] sd_buff_dout,
   output     [7:0] sd_buff_din,
   input            sd_buff_wr,
   input            sd_din_strobe,
   // karabas: the physical drives (PHYS): drive A / B is 0 the image (A) or none (B), 1 DS0, 2 DS1 of the
   // floppy connector; its pins, high = active: { rdata, wprt, tr00, index }, { wdata, wgate, side1, step,
   // dir, motor, ds1, ds0 }
   input      [1:0] phys_a,
   input      [1:0] phys_b,
   input      [3:0] fdd_in,
   output     [7:0] fdd_out
);

reg side_select, m_on, in_use = 1'b0;
reg [1:0] ds = 2'b0;
reg type1, type0 = 1'b1;

wire ic4 =   ~&{addr[13:3], ~stlsl_n};
wire r7ffc = ~ic4 && addr[2] && addr[1:0] == 2'b00;
wire r7ffd = ~ic4 && addr[2] && addr[1:0] == 2'b01; 
wire r7fff = ~ic4 && addr[2] && addr[1:0] == 2'b11; 
wire romce = addr[15:14] == 2'b01 && ic4 && ~stlsl_n && ~CS1_n;
wire csfdc = ~ic4 && ~addr[2];

assign d_to_cpu = romce            ? (rom_en ? d_from_rom : 8'hFF)          : 
                  r7ffc   && ~rd_n ? {7'b1111111, ~side_select}             :
                  r7ffd   && ~rd_n ? {m_on, in_use, 4'b1110, ~ds[1], ds[0]} :
                  r7fff   && ~rd_n ? {~drq, ~intrq, type1, type0, 4'b1111}  :
                  csfdc   && ~rd_n ? d_from_fdc :
                                     8'hFF;

wire wr7ffc = r7ffc & ~wr_n;
wire wr7ffd = r7ffd & ~wr_n;
// karabas: the registers on clk at the start of the write (its strobe and reset were their clocks)
reg wr7ffc_d = 1'b0, wr7ffd_d = 1'b0;
always @(posedge clk) begin
   wr7ffc_d <= wr7ffc;
   wr7ffd_d <= wr7ffd;
end
always @(posedge clk) begin
   if (reset) begin
      side_select <= 1'b0;
   end else if (wr7ffc & ~wr7ffc_d) begin
      if (~stlsl_n) begin
         side_select <= d_from_cpu[0];
      end
   end
end

always @(posedge clk) begin
   if (reset) begin
      m_on        <= 1'b0;
      in_use      <= 1'b0;
      ds          <= 2'b00;
   end else if (wr7ffd & ~wr7ffd_d) begin
      if (~stlsl_n) begin
         ds[0]  <=  d_from_cpu[0];
         ds[1]  <= ~d_from_cpu[1];     
         in_use <=  d_from_cpu[6];
         m_on   <=  d_from_cpu[7];
      end
   end
end
   
wire [7:0] d_from_wd, d_from_fdc;
wire drq, intrq, wd_drq, wd_intrq;
reg img_load;
// karabas: a single sided image (360 KB or less) has no side 1 between the tracks: layout 1 of
// wd1793 (side-track-sector) puts track t of side 0 at t * 9 sectors there; layout 0
// (track-side-sector, 720 KB) put it at 2t * 9 and every track after 0 was read wrong
reg img_ss = 1'b0;

always @(posedge clk) if(img_mounted) begin
   img_load <= |img_size;
   img_ss <= img_size <= 32'd368640;
end
wire fdd_ready = img_load & ~ds[0] & ds[1];

// karabas: the physical floppy drives (PHYS, Karabas Go). 7FFD bits 1..0 select the drive as in the disk
// ROM: 00 A (C4: motor on, A), 01 B (C5: the ROM looks for drive B by a restore), 11 none (03). A drive
// mapped to a physical one (phys_a / phys_b: DS0 / DS1) is served by the VG93 model on the pins, the
// others by wd1793 (the image of drive A; B without a physical drive has nothing, as before): the
// accesses to 7FF8..7FFB go to the controller of the selected drive only, so each keeps its own registers
// (the ROM writes the track register of a drive when it selects it). A Force Interrupt (Dx) goes to both:
// a command left in the other one ends.
wire sel_a = ~ds[0] &  ds[1];
wire sel_b =  ds[0] &  ds[1];
wire [1:0] map_sel = sel_a ? phys_a : sel_b ? phys_b : 2'd0;
wire phys_sel = (PHYS != 0) && map_sel != 2'd0;
wire force_int = ~wr_n && addr[1:0] == 2'b00 && d_from_cpu[7:4] == 4'hD;
wire wd_sel = ~phys_sel | force_int;
wire ph_sel = phys_sel | force_int;
wire [7:0] d_from_ph;
wire ph_drq, ph_intrq;
assign d_from_fdc = phys_sel ? d_from_ph : d_from_wd;
assign drq = phys_sel ? ph_drq : wd_drq;
assign intrq = phys_sel ? ph_intrq : wd_intrq;

wd1793 #(.RWMODE(1), .EDSK(0)) fdc
(
   .clk_sys(clk),
   .ce(clk_en),
   .reset(reset),
   .io_en(csfdc & wd_sel),    // karabas: see phys_sel
   .rd(~rd_n),
   .wr(~wr_n),
   .addr(addr[1:0]),
   .din(d_from_cpu),
   .dout(d_from_wd),
   .drq(wd_drq),
   .intrq(wd_intrq),
   .ready(fdd_ready),
   .layout(img_ss),           // karabas: see img_ss
   .size_code(3'h2),
   .side(side_select),
   .img_mounted(img_mounted),
   .wp(img_wp),
   .img_size(img_size[19:0]),
   .sd_lba(sd_lba),
   .sd_rd(sd_rd),
   .sd_wr(sd_wr),
   .sd_ack(sd_ack),
   .sd_buff_addr(sd_buff_addr),
   .sd_buff_dout(sd_buff_dout),
   .sd_buff_din(sd_buff_din), 
   .sd_buff_wr(sd_buff_wr),
   .input_active(1'b0),
   .input_addr(20'h0),
   .input_data(8'h0),
   .input_wr(1'b0),
   .buff_din(8'h0)
);

generate
if (PHYS != 0) begin : phys
   // the register of the access, held after it: the model takes the byte at the end of the write
   reg [1:0] a_hold = 2'd0;
   wire acc = csfdc & ph_sel & (~rd_n | ~wr_n);
   always @(posedge clk) if (acc) a_hold <= addr[1:0];
   msx_fdc_phys fdc_phys (
      .clk(clk),
      .reset(reset),
      .cs(csfdc & ph_sel),
      .rd(~rd_n),
      .wr(~wr_n),
      .a(acc ? addr[1:0] : a_hold),
      .din(d_from_cpu),
      .dout(d_from_ph),
      .drq(ph_drq),
      .intrq(ph_intrq),
      .ds({ map_sel == 2'd2, map_sel == 2'd1 }),
      .motor(m_on),
      .side(side_select),
      .fdd_in(fdd_in),
      .fdd_out(fdd_out)
   );
end else begin : no_phys
   assign d_from_ph = 8'hFF;
   assign ph_drq = 1'b0;
   assign ph_intrq = 1'b0;
   assign fdd_out = 8'd0;
end
endgenerate

wire [7:0] d_from_rom;

spram #(.addr_width(14), .mem_init_file("rtl/msx/rom/vy0010.hex"), .mem_name("VY0010ROM")) vy0010_rom
(
   .clock(clk),
   .address(addr[13:0]),
   .wren(1'b0),
   .data(8'h00), // karabas: the ROM as spram.v, the .mif as .hex
   .q(d_from_rom)
);

endmodule
