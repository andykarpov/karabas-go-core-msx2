// sim_sys: tb_sys (msx_system + SRAM model) under verilator.
//
//   sim_sys [--cbios DIR] [--rom FILE:ADDR ...] [--cart FILE] [--cart-b FILE] [--bios FILE] [--mapper-a N]
//           [--pal] [--v9938] [--ram64] [--no-opll] [--audio-min N] [--audio-max N] [--frames N] [--ppm OUT] [--every N] [--key F:CODE[,CODE]] [--hash]
//           [--disk FILE.dsk [--fdd-latency MS] [--fdd-drop N] [--save-disk OUT]]
//           [--nextor [--nextor-rom FILE]] [--hdd FILE [--save-hdd OUT]] [--no-slot1-rom]
//
// --cbios DIR: C-BIOS MSX2+ EU from DIR (src/roms) at the places of msx2_slots, as core.json has it:
// main 020000, sub 030000, MSX-MUSIC 02C000, logo 03C000. --fast-logo: instead of the logo ROM
// a stub of 17 bytes at 03C000: the ident C-BIOS looks for ("C-BIOS Logo ROM" at 8000) and a RET at
// 8010, where it calls the logo: no logo animation; and the wait of 120 frames after the logo in
// the main ROM ("ld b,120 / call wait_b", 06 78 CD 2F 11 at 0E05 of C-BIOS 0.29a MSX2 / MSX2+) is 1
// frame in the SRAM: a cartridge starts after about 10 frames instead of 200.
// The ROMs go in through the ROM loader of the mcu (rom_active, one byte every 12 clocks, as a
// burst at 32 MHz), the files through the file loader (FL slot 4 = cartridge A, 1 = B, 2 = BIOS).
// The clocks: a tick of the VCO (600 MHz), clk every 14 ticks (42.857 MHz), clk21 every 28 (its
// rising edges with every other one of clk), as the PLL of the tops. The picture is the 15 kHz
// output of the VDP: a pixel at each clk21 with dhclk (684 a line, the 512 dots of the wide modes
// and the border), a line from hsync to hsync, a frame from vsync to vsync (262 / 313 lines).
// A frame is a vsync of the VDP; --ppm writes the frame after the last one (or every N with
// --every, OUT-<n>.ppm). --pal: 50 Hz forced (else R9 of the VDP decides: the BIOS), --v9938: the
// VDP answers as a V9938 (MSX2) instead of a V9958 (MSX2+). --hash prints a
// CRC-32 of each written frame. --key F:CODE sends the PS/2 set 2 codes (hex) at frame F, a
// release (F0 code) 5 frames later. --ram64: the RAM of 64 KB, without the memory mapper. --no-opll:
// the OPLL (MSX-MUSIC) off. The range of the audio output (max - min) in the last 20 frames is
// printed at the end ("audio range N"), with FAIL after it when it is below --audio-min or above
// --audio-max. --disk: slot 1 is the disk drive with this image on a model of the
// file mounter of the firmware (mcu_clk); SIM_FDD=1 logs its requests. --nextor: slot 1 is the SD
// interface for Nextor (its ROM from FL slot 5 with --nextor-rom), --hdd: the hard disk image of
// F slot 6 on the same model. --no-slot1-rom: the ROM of slot 1 (disk ROM, Nextor ROM) reads FF.
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <cstdint>
#include <string>
#include <vector>
#include <map>
#include "Vtb_sys.h"
#include "verilated.h"

static Vtb_sys *top;
static uint64_t ticks = 0;
static uint64_t clks = 0;

// frame capture from the VDP (clk21): a line from the rise of hs, a frame from the rise of vs. In
// the vertical sync the VDP (vdp_ntsc_pal) gives hs pulses at twice the line rate (equalizing and
// serration pulses): a rise of hs starts a line only 1300 clocks of clk21 or more after the line
// before (a line is 1368)
static const int FW = 700, FH = 640;
static std::vector<uint8_t> cap(FW * FH * 3), frame;
static int fx = 0, fy = 0, frames = 0, fw = 0, fh = 0, cap_w = 0;
static bool prev_hs = false, prev_vs = false;
static int since_hs = 0;

static void on_vdp() {
	bool hs = top->hs, vs = top->vs;
	since_hs++;
	if (hs && !prev_hs && since_hs >= 1300) { if (fx > cap_w) cap_w = fx; fx = 0; fy++; since_hs = 0; }
	if (vs && !prev_vs) {
		// 1368 clocks of clk21 a line, a pixel in two
		fw = cap_w < 684 ? cap_w : 684; fh = fy < FH ? fy : FH;
		frame.assign(fw * fh * 3, 0);
		for (int y = 0; y < fh; y++) memcpy(&frame[y * fw * 3], &cap[y * FW * 3], fw * 3);
		std::fill(cap.begin(), cap.end(), 0);
		fy = 0; fx = 0; cap_w = 0; frames++;
	}
	if (top->dhclk) {
		if (fx < FW && fy < FH) {
			uint32_t c = top->rgb;
			uint8_t *p = &cap[(fy * FW + fx) * 3];
			p[0] = c >> 16; p[1] = c >> 8; p[2] = c;
		}
		fx++;
	}
	prev_hs = hs; prev_vs = vs;
}

static int isr_cnt = 0; static bool prev_isr = false;
static int trace_n = getenv("SIM_TRACE") ? atoi(getenv("SIM_TRACE")) : 0;
static bool tr_on = false, tr_w = false; static int tr_a = 0, tr_d = 0;
static int dbg_b = -1, dbg_k = -1, dbg_kb = -1, dbg_row = -1;
static int kbdbg_from = getenv("SIM_KBDBG") ? atoi(getenv("SIM_KBDBG")) : -1;
static bool dbg = getenv("SIM_DBG") != 0;
// ---- the file mounter of the firmware (docs/protocol.md section 6), on the IMG_* ports of kg_mcu:
// the requests of img_sdc come as img_q words (acked one clock), a read is answered after
// fdd_latency clk with 512 bytes (one per 11 clk, a burst at 32 MHz), the sum, the result; a write
// is taken with its bytes and sum and answered after fdd_latency.
static std::vector<uint8_t> disk;
static std::vector<uint8_t> hdd;      // F slot 6 (Nextor)
static std::vector<uint8_t> *img = &disk; // the image of the request
static int hdd_mount_at = -1;
static int fdd_latency = 0;           // clk
static int fdd_drop = -1;             // the number of the request whose answer is lost
static int fdd_reqs = 0;
static uint64_t fdd_busy_clk = 0;     // clk between a request and its answer, summed
static uint32_t mcu_lba = 0;
static int mcu_lba_bytes = 0;
static int mcu_op = 0;                // 1 read, 2 write in progress
static int64_t mcu_wait = -1;         // clk until the answer
static int mcu_pos = -1;              // the next byte of a read answer
static int mcu_gap = 0;
static uint8_t mcu_wbuf[512];
static int mcu_wcnt = 0, mcu_bank = 0;
static uint16_t mcu_wsum = 0;
static int mcu_wsum_parts = 0;
static uint64_t mcu_req_clk = 0;
static bool fdd_log = getenv("SIM_FDD") != 0;
static bool fdd_log_all = getenv("SIM_FDD_ALL") != 0;
static int mount_at = -1;             // clk to mount the disk (pulse img_mounted[0])
static uint64_t mount_clk = 0;
static bool fill_reported = false;

static void mcu_answer(bool ok) {
	top->img_result = ok ? 1 : 2;
	top->img_result_wr = 1;
}

static void mcu_clk() {
	// pulses of one clock end here
	top->img_q_ack = 0;
	top->img_data_wr = 0;
	top->img_result_wr = 0;
	top->img_mounted = 0;
	if (mount_at >= 0 && (int64_t)clks >= mount_at) {
		top->img_size = disk.size();
		top->img_mounted = 1;
		mount_at = -1;
		mount_clk = clks;
		fill_reported = false;
		if (fdd_log) printf("mcu: mount %zu bytes\n", disk.size());
	} else if (hdd_mount_at >= 0 && (int64_t)clks >= hdd_mount_at) {
		top->img_size = hdd.size();
		top->img_mounted = 1 << 6;
		hdd_mount_at = -1;
		if (fdd_log) printf("mcu: mount slot 6, %zu bytes\n", hdd.size());
	}
	if (!fill_reported && mount_clk && !top->fdd_filling && top->fdd_filled) {
		fill_reported = true;
		printf("fdd: image in the SRAM after %.1f ms (%d sectors)\n", (clks - mount_clk) / 42857.0, top->fdd_filled);
	}
	if (top->img_q_wr && !top->img_q_ack) {
		uint32_t w = top->img_q_di;
		uint8_t c = w >> 16, a = w >> 8, d = w;
		top->img_q_ack = 1;
		if (c == 0x42) {
			if (a == 0) { mcu_lba = 0; mcu_lba_bytes = 0; }
			mcu_lba |= (uint32_t)d << (8 * a);
			mcu_lba_bytes++;
		}
		else if (c == 0x43) {
			fdd_reqs++;
			mcu_op = d;
			img = a == 6 ? &hdd : &disk;
			mcu_req_clk = clks;
			mcu_wcnt = 0; mcu_wsum_parts = 0; mcu_wsum = 0;
			if (fdd_log && (fdd_log_all || d != 1 || fdd_reqs <= 3)) printf("mcu: %s lba %u (request %d, %.1f ms)\n", d == 1 ? "read" : "write", mcu_lba, fdd_reqs, clks / 42857.0);
			if (fdd_reqs == fdd_drop) { if (fdd_log) printf("mcu: request %d lost\n", fdd_reqs); mcu_op = 0; }
			else if (d == 1) mcu_wait = fdd_latency;
		}
		else if (c == 0x44 && mcu_op == 2) {
			if (a == 0) mcu_bank = d & 1;
			else if (a == 0x10) { mcu_wsum = (mcu_wsum & 0xFF00) | d; mcu_wsum_parts++; }
			else if (a == 0x11) { mcu_wsum = (mcu_wsum & 0x00FF) | (d << 8); mcu_wsum_parts++; if (mcu_wsum_parts == 2) mcu_wait = fdd_latency; }
		}
		else if (c == 0x45 && mcu_op == 2) {
			mcu_wbuf[mcu_bank * 256 + a] = d;
			mcu_wcnt++;
		}
	}
	if (mcu_wait > 0) mcu_wait--;
	else if (mcu_wait == 0) {
		mcu_wait = -1;
		if (mcu_op == 1) { mcu_pos = 0; mcu_gap = 0; }
		else if (mcu_op == 2) {
			uint16_t sum = 0;
			for (int i = 0; i < 512; i++) sum += mcu_wbuf[i];
			bool ok = mcu_wcnt == 512 && sum == mcu_wsum && (size_t)(mcu_lba + 1) * 512 <= img->size();
			if (ok) memcpy(&(*img)[mcu_lba * 512], mcu_wbuf, 512);
			if (fdd_log) printf("mcu: write lba %u %s\n", mcu_lba, ok ? "done" : "ERROR");
			fdd_busy_clk += clks - mcu_req_clk;
			mcu_answer(ok);
			mcu_op = 0;
		}
	}
	if (mcu_pos >= 0) {
		bool in = (size_t)(mcu_lba + 1) * 512 <= img->size() && mcu_lba_bytes == 4;
		if (mcu_pos < 512) {
			if (in && ++mcu_gap >= 11) {
				mcu_gap = 0;
				top->img_data_addr = mcu_pos;
				top->img_data = (*img)[mcu_lba * 512 + mcu_pos];
				top->img_data_wr = 1;
				mcu_pos++;
			}
			if (!in) mcu_pos = 512;
		}
		else {
			uint16_t sum = 0;
			if (in) for (int i = 0; i < 512; i++) sum += (*img)[mcu_lba * 512 + i];
			top->img_sum = sum;
			mcu_answer(in);
			fdd_busy_clk += clks - mcu_req_clk;
			mcu_pos = -1;
			mcu_op = 0;
		}
	}
}

static void tick() {
	ticks++;
	bool step = false;
	bool clk_rise = false;
	bool vdp_rise = false;
	if (ticks % 7 == 0) {
		top->clk = !top->clk; step = true;
		if (top->clk) { clks++; clk_rise = true; top->clk21 = !top->clk21; vdp_rise = top->clk21; }
	}
	if (step) top->eval();
	if (clk_rise && (!disk.empty() || !hdd.empty())) mcu_clk();
	if (dbg && top->dbg_border != dbg_b) { printf("frame %d y %d border %d\n", frames, top->dbg_y, top->dbg_border); dbg_b = top->dbg_border; }
	{ bool isr = !top->cpu_m1_n && top->cpu_a == 0x38; if (isr && !prev_isr) isr_cnt++; prev_isr = isr; }
	// SIM_TRACE=N: the first N opcode fetches (address, the byte at the end of the read)
	if (trace_n > 0 && clk_rise) {
		bool f = !top->cpu_m1_n && !top->cpu_rd_n;
		if (f) { tr_a = top->cpu_a; tr_d = top->cpu_di; }
		if (!f && tr_on) { printf("m1 %04x %02x\n", tr_a, tr_d); trace_n--; }
		tr_on = f;
	}
	// the writes to the slot registers (port A8, FFFF) with the trace
	if (trace_n > 0 && clk_rise) {
		bool w = !top->cpu_wr_n;
		if (w && !tr_w) {
			if (!top->cpu_iorq_n && (top->cpu_a & 0xFF) == 0xA8) printf("out a8 %02x\n", top->cpu_do);
			if (top->cpu_iorq_n && top->cpu_a == 0xFFFF) printf("wr ffff %02x (a8 %02x)\n", top->cpu_do, top->dbg_ppi_a);
		}
		tr_w = w;
	}
	if (kbdbg_from >= 0 && frames >= kbdbg_from && top->dbg_kb_row != dbg_row) { dbg_row = top->dbg_kb_row; printf("frame %d row %d kb %02x\n", frames, dbg_row, top->dbg_kb); }
	if (dbg && top->dbg_ps2_key != dbg_k) { printf("frame %d ps2_key %03x\n", frames, top->dbg_ps2_key); dbg_k = top->dbg_ps2_key; }
	if (dbg && top->dbg_kb != 0xFF && ((top->dbg_kb_row << 8) | top->dbg_kb) != dbg_kb) { dbg_kb = (top->dbg_kb_row << 8) | top->dbg_kb; printf("frame %d kb row %d = %02x\n", frames, top->dbg_kb_row, top->dbg_kb); }
	if (vdp_rise) on_vdp();
}

static void clk_cycles(int n) {
	uint64_t end = clks + n;
	while (clks < end) tick();
}

static std::vector<uint8_t> load(const char *fn) {
	FILE *f = fopen(fn, "rb");
	if (!f) { perror(fn); exit(1); }
	std::vector<uint8_t> d;
	int c;
	while ((c = fgetc(f)) != EOF) d.push_back(c);
	fclose(f);
	return d;
}

static void rom_load(const std::vector<uint8_t> &d, uint32_t addr) {
	top->rom_active = 1;
	for (size_t i = 0; i < d.size(); i++) {
		top->rom_addr = addr + i;
		top->rom_data = d[i];
		top->rom_wr = 1;
		clk_cycles(1);
		top->rom_wr = 0;
		clk_cycles(11);
	}
	clk_cycles(4);
	top->rom_active = 0;
}

// SIM_FILE_GAP: the clocks between two bytes after the one of file_wr (11; a burst at 32 MHz is
// a byte in 10.7 clocks)
static void file_load(const std::vector<uint8_t> &d, int slot) {
	int gap = getenv("SIM_FILE_GAP") ? atoi(getenv("SIM_FILE_GAP")) : 11;
	// as the firmware (core_ioctl_send): IOCTL_STATE 1 first, IOCTL_SLOT (file_reset, the slot) after it,
	// so file_active is on with the slot of the file before for a while
	top->file_active = 1;
	clk_cycles(40);
	top->file_slot = slot;
	top->file_reset = 1;
	clk_cycles(1);
	top->file_reset = 0;
	clk_cycles(4);
	for (size_t i = 0; i < d.size(); i++) {
		top->file_addr = i;
		top->file_data = d[i];
		top->file_wr = 1;
		clk_cycles(1);
		top->file_wr = 0;
		clk_cycles(gap);
	}
	clk_cycles(4);
	top->file_active = 0;
}

static uint32_t crc32(const uint8_t *p, size_t n) {
	uint32_t c = 0xFFFFFFFF;
	for (size_t i = 0; i < n; i++) {
		c ^= p[i];
		for (int k = 0; k < 8; k++) c = (c >> 1) ^ (0xEDB88320 & -(c & 1));
	}
	return ~c;
}

static void write_ppm(const std::string &fn) {
	FILE *f = fopen(fn.c_str(), "wb");
	if (!f) { perror(fn.c_str()); exit(1); }
	fprintf(f, "P6\n%d %d\n255\n", fw, fh);
	fwrite(frame.data(), 1, frame.size(), f);
	fclose(f);
}

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	top = new Vtb_sys;
	std::vector<std::pair<std::string, uint32_t>> roms;
	std::string cart_a, cart_b, bios, ppm;
	int nframes = 60, every = 0, mapper_a = 0;
	bool pal = false, v9938 = false, fast_logo = false, bios_first = false, hash = false, fdd = false, ram64 = false, no_opll = false;
	int audio_min = -1, audio_max = -1;
	std::string save_disk, cas, save_hdd, nextor_rom;
	bool nextor = false, no_slot1_rom = false;
	std::map<int, std::vector<int>> keys;
	for (int i = 1; i < argc; i++) {
		std::string a = argv[i];
		auto next = [&]() { if (i + 1 >= argc) { fprintf(stderr, "%s: value?\n", a.c_str()); exit(1); } return std::string(argv[++i]); };
		if (a == "--cbios") {
			std::string d = next();
			roms.push_back({d + "/cbios_main_msx2+_eu.rom", 0x20000});
			roms.push_back({d + "/cbios_sub.rom", 0x30000});
			roms.push_back({d + "/cbios_music.rom", 0x2C000});
			roms.push_back({d + "/cbios_logo_msx2+.rom", 0x3C000});
		}
		else if (a == "--rom") { std::string v = next(); size_t c = v.rfind(':'); roms.push_back({v.substr(0, c), (uint32_t)strtoul(v.c_str() + c + 1, 0, 0)}); }
		else if (a == "--cart") cart_a = next();
		else if (a == "--cart-b") cart_b = next();
		else if (a == "--bios") bios = next();
		else if (a == "--mapper-a") mapper_a = atoi(next().c_str());
		else if (a == "--pal") pal = true;
		else if (a == "--v9938") v9938 = true;
		else if (a == "--fast-logo") fast_logo = true;
		else if (a == "--bios-first") bios_first = true;
		else if (a == "--ram64") ram64 = true;
		else if (a == "--no-opll") no_opll = true;
		else if (a == "--audio-min") audio_min = atoi(next().c_str());
		else if (a == "--audio-max") audio_max = atoi(next().c_str());
		else if (a == "--disk") { disk = load(next().c_str()); fdd = true; }
		else if (a == "--fdd-latency") fdd_latency = atof(next().c_str()) * 42857;
		else if (a == "--fdd-drop") { fdd_drop = atoi(next().c_str()); if (!fdd_drop) fdd_drop = -1; }
		else if (a == "--save-disk") save_disk = next();
		else if (a == "--nextor") nextor = true;
		else if (a == "--nextor-rom") nextor_rom = next();
		else if (a == "--no-slot1-rom") no_slot1_rom = true;
		else if (a == "--hdd") hdd = load(next().c_str());
		else if (a == "--save-hdd") save_hdd = next();
		else if (a == "--cas") cas = next();
		else if (a == "--frames") nframes = atoi(next().c_str());
		else if (a == "--ppm") ppm = next();
		else if (a == "--every") every = atoi(next().c_str());
		else if (a == "--hash") hash = true;
		else if (a == "--key") {
			std::string v = next(); size_t c = v.find(':');
			int f = atoi(v.substr(0, c).c_str());
			std::string codes = v.substr(c + 1);
			size_t p = 0;
			while (p < codes.size()) {
				size_t q = codes.find(',', p); if (q == std::string::npos) q = codes.size();
				keys[f].push_back(strtol(codes.substr(p, q - p).c_str(), 0, 16));
				p = q + 1;
			}
		}
		else if (a[0] == '+') ;
		else { fprintf(stderr, "unknown argument %s\n", a.c_str()); return 1; }
	}
	top->clk = 0; top->clk21 = 0;
	top->reset = 1;
	top->mapper_a = mapper_a; top->mapper_b = 0;
	top->pal = pal;
	top->pal_auto = !pal;
	top->v9958 = !v9938;
	top->joy_l = 0;
	top->fdd = fdd;
	top->fdd_rom_en = !getenv("SIM_NO_DISKROM") && !no_slot1_rom;
	top->nextor = nextor;
	top->ram_mapper = !ram64;
	top->opll = !no_opll;
	top->eval();
	clk_cycles(100);
	// --bios-first: the BIOS file before the roms (the order of the firmware of 2026-11-10: the FL autoload
	// first); the core must keep the BIOS file then
	if (bios_first && !bios.empty()) file_load(load(bios.c_str()), 2);
	for (auto &r : roms) rom_load(load(r.first.c_str()), r.second);
	if (fast_logo) {
		std::vector<uint8_t> stub(17, 0);
		memcpy(stub.data(), "C-BIOS Logo ROM", 15);
		stub[16] = 0xC9;   // 8010: RET
		rom_load(stub, 0x3C000);
		std::vector<uint8_t> one(1, 1);
		top->dbg_sram_addr = 0x20E05; top->eval();
		if (top->dbg_sram_q == 0x06) {
			top->dbg_sram_addr = 0x20E06; top->eval();
			if (top->dbg_sram_q == 0x78) rom_load(one, 0x20E06);
			else printf("fast-logo: no wait at 0E05\n");
		}
		else printf("fast-logo: no wait at 0E05\n");
	}
	if (!bios_first && !bios.empty()) file_load(load(bios.c_str()), 2);
	if (!cart_a.empty()) file_load(load(cart_a.c_str()), 4);
	if (!cart_b.empty() && cas.empty()) file_load(load(cart_b.c_str()), 1);
	if (fdd) mount_at = clks + 1000;
	if (!hdd.empty()) hdd_mount_at = clks + 2000;
	if (!nextor_rom.empty()) file_load(load(nextor_rom.c_str()), 5);
	clk_cycles(2000);
	// the CAS file after the mount: its load runs with the fill of the disk image in the SRAM
	if (!cas.empty()) {
		std::vector<uint8_t> d = load(cas.c_str());
		file_load(d, 3);
		clk_cycles(2000);
		size_t bad = 0;
		// the tape of msx_tape: 3E0000, 128 KB
		for (size_t i = 0; i < d.size() && i < 0x20000; i++) {
			top->dbg_sram_addr = 0x3E0000 + i;
			top->eval();
			if (top->dbg_sram_q != d[i] && bad++ < 4) printf("cas: SRAM %06zx %02x, file %02x\n", 0x3E0000 + i, top->dbg_sram_q, d[i]);
		}
		printf("cas: %zu bytes, %zu wrong in the SRAM\n", d.size(), bad);
		// cartridge B after the CAS file: its load starts with the slot of the CAS (see file_load)
		if (!cart_b.empty()) file_load(load(cart_b.c_str()), 1);
	}
	top->reset = 0;
	int f0 = frames;
	std::map<int, std::vector<int>> release;
	bool upd = false;
	int last = -1;
	int amin = 32767, amax = -32768;
	while (frames - f0 < nframes) {
		tick();
		int f = frames - f0;
		if (f >= nframes - 20) { int a = (int16_t)top->audio; if (a < amin) amin = a; if (a > amax) amax = a; }
		if (f != last) {
			last = f;
			if (getenv("SIM_ISR")) { printf("frame %d isr %d pc %04x a8 %02x\n", f, isr_cnt, top->cpu_a, top->dbg_ppi_a); isr_cnt = 0; }
			auto send = [&](int code) {
				top->kb_scancode = code; upd = !upd; top->kb_scancode_upd = upd;
				clk_cycles(2000);
			};
			if (keys.count(f)) {
				for (int c : keys[f]) { if (c >= 0xE0) send(c); else { send(c); release[f + 5].push_back(c); } }
			}
			if (release.count(f)) for (int c : release[f]) { send(0xF0); send(c); }
			if (f > 0 && ((every && f % every == 0) || f == nframes)) {
				if (hash) printf("frame %d crc %08x %dx%d\n", f, crc32(frame.data(), frame.size()), fw, fh);
				if (!ppm.empty()) write_ppm(every ? ppm + "-" + std::to_string(f) + ".ppm" : ppm);
			}
		}
	}
	printf("%d frames, %llu clk\n", nframes, (unsigned long long)clks);
	{
		int r = amax - amin;
		bool bad = (audio_min >= 0 && r < audio_min) || (audio_max >= 0 && r > audio_max);
		printf("audio range %d%s\n", r, bad ? " FAIL" : "");
	}
	if (fdd) printf("fdd: %d requests, %.1f ms waiting for the mcu\n", fdd_reqs, fdd_busy_clk / 42857.0);
	if (!save_disk.empty()) { FILE *f = fopen(save_disk.c_str(), "wb"); fwrite(disk.data(), 1, disk.size(), f); fclose(f); }
	if (!save_hdd.empty()) { FILE *f = fopen(save_hdd.c_str(), "wb"); fwrite(hdd.data(), 1, hdd.size(), f); fclose(f); }
	delete top;
	return 0;
}
