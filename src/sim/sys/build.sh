#!/bin/bash
# Builds sim_sys (verilator) into src/sim/build/sys: tb_sys.v with msx_system and the
# machine; its VHDL through ghdl --synth (vhdl2v.sh). Run sim_sys from src/ (the INIT_FILE of the
# VY0010 ROM is relative to it, as for XST).
set -eu
H=$(cd "$(dirname "$0")" && pwd)
S=$(cd "$H/../.." && pwd)
B=$S/sim/build
"$H/vhdl2v.sh" "$B/vhdl" > /dev/null 2> "$B/vhdl.log" || { cat "$B/vhdl.log"; exit 1; }
R=$S/rtl
M=$S/../modules/rtl
SRC="$H/tb_sys.v $R/msx_system.v $R/msx_sram.v $R/msx_ps2_key.v $R/msx_fdd_cache.v $R/msx_tape.v $R/msx/tape.v $M/mcu/img_sdc.v
 $R/msx/msx2.v $R/msx/msx2_slots.v $R/msx/rtc.v $R/msx/spram.v $R/msx/ls74.v $R/msx/jt8255.v $R/msx/io_decoder.v $R/msx/memory_mapper.v $R/msx/ram_mapper.v $R/msx/nextor_sd.v $M/mem/kg_tdpram.v $R/msx/slots.v
 $R/msx/cart/rom.v $R/msx/cart/rom_detect.v $R/msx/cart/konami.v $R/msx/cart/konami_scc.v $R/msx/cart/ascii8.v
 $R/msx/cart/ascii16.v $R/msx/cart/gamemaster2.v $R/msx/cart/vy0010.v $R/msx/cart/wd1793.v
 $R/msx/jt49/jt49_bus.v $R/msx/jt49/jt49.v $R/msx/jt49/jt49_cen.v $R/msx/jt49/jt49_div.v $R/msx/jt49/jt49_eg.v
 $R/msx/jt49/jt49_exp.v $R/msx/jt49/jt49_noise.v $R/msx/jtopl/*.v
 $M/mem/kg_spram.v $M/mem/kg_fifo.v $M/mem/kg_sdpram.v $M/ctl/kg_sync.v
 $B/vhdl/t80pa.v $B/vhdl/vdp.v $B/vhdl/ram.v $B/vhdl/cv_clock.v $B/vhdl/keyboard.v $B/vhdl/scc_wave.v"
verilator --language 1364-2005 --cc --exe --build -j 8 -O3 --top-module tb_sys -Mdir "$B/sys" -o sim_sys \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-PINNOTFOUND \
	--x-initial fast -CFLAGS -O2 $SRC "$H/sim_sys.cpp" > "$B/sys.log" 2>&1 || { tail -40 "$B/sys.log"; exit 1; }
echo "$B/sys/sim_sys"
