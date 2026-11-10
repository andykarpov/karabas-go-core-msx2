#!/bin/bash
# The frame buffer test (tb_msx2_fb.v: rtl/fb/msx2_fb.v + msx2_fb_sdram.v and a model of the SDRAM)
# with iverilog, about 4 minutes a run: dhclk in both phases (+ph1: a dot in the clock of the line start).
# Usage: sim/fb/run_fb.sh [+dbg]
set -e
cd "$(dirname "$0")"
B=../build/fb
mkdir -p $B
M=../../../modules/rtl
X=/opt/Xilinx/14.7/ISE_DS/ISE/verilog/src
iverilog -g2005 -o $B/tb_msx2_fb.vvp -s tb_msx2_fb -s glbl tb_msx2_fb.v ../../rtl/fb/msx2_fb.v ../../rtl/fb/msx2_fb_sdram.v \
	$M/mem/kg_sdpram.v $M/ctl/kg_sync.v $X/unisims/ODDR2.v $X/glbl.v
vvp -n $B/tb_msx2_fb.vvp "$@" > $B/tb_msx2_fb.log &
vvp -n $B/tb_msx2_fb.vvp +ph1 "$@" > $B/tb_msx2_fb_ph1.log &
wait
for l in $B/tb_msx2_fb.log $B/tb_msx2_fb_ph1.log; do
	echo "== $l"; grep -E "ERROR|errors|checked|x " $l | head -20
done
grep -q "tb_msx2_fb: 0 errors" $B/tb_msx2_fb.log && grep -q "tb_msx2_fb: 0 errors" $B/tb_msx2_fb_ph1.log
