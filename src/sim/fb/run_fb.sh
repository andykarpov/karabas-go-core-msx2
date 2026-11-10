#!/bin/bash
# The frame buffer test (tb_msx2_fb.v: rtl/fb/msx2_fb.v + msx2_fb_sdram.v and a model of the SDRAM)
# with iverilog, a few minutes. Usage: sim/fb/run_fb.sh [+dbg]
set -e
cd "$(dirname "$0")"
B=../build/fb
mkdir -p $B
M=../../../modules/rtl
X=/opt/Xilinx/14.7/ISE_DS/ISE/verilog/src
iverilog -g2005 -o $B/tb_msx2_fb.vvp -s tb_msx2_fb -s glbl tb_msx2_fb.v ../../rtl/fb/msx2_fb.v ../../rtl/fb/msx2_fb_sdram.v \
	$M/mem/kg_sdpram.v $M/ctl/kg_sync.v $X/unisims/ODDR2.v $X/glbl.v
vvp -n $B/tb_msx2_fb.vvp "$@" | tee $B/tb_msx2_fb.log | grep -E "ERROR|errors|frame|checked|x " | head -60
grep -q "tb_msx2_fb: 0 errors" $B/tb_msx2_fb.log
