#!/bin/bash
# The VHDL of the machine as Verilog netlists (ghdl --synth), for verilator: T80 (t80pa), vdp18_core,
# cv_clock, keyboard, the SCC (scc_wave, with ram and scc_wave_mul), the ESE-VDP (vdp) and ram alone
# (the backup memory of rtc.v). Output: $1 (a directory).
set -eu
OUT=${1:?output dir}
R=$(cd "$(dirname "$0")/../../rtl/msx" && pwd)
mkdir -p "$OUT"
cd "$OUT"
G="--std=93c -fexplicit --ieee=synopsys -frelaxed"
SRC="$R/T80/T80_Pack.vhd $R/T80/T80_ALU.vhd $R/T80/T80_MCode.vhd $R/T80/T80_Reg.vhd $R/T80/T80.vhd $R/T80/T80pa.vhd
 $R/vdp18/vdp18_pack-p.vhd $R/vdp18/vdp18_col_pack-p.vhd $R/vdp18/vdp18_clk_gen.vhd $R/vdp18/vdp18_hor_vert.vhd
 $R/vdp18/vdp18_ctrl.vhd $R/vdp18/vdp18_cpuio.vhd $R/vdp18/vdp18_addr_mux.vhd $R/vdp18/vdp18_pattern.vhd
 $R/vdp18/vdp18_sprite.vhd $R/vdp18/vdp18_col_mux.vhd $R/vdp18/vdp18_core.vhd
 $R/cv_clock.vhd $R/keyboard.vhd $R/cart/ram.vhd $R/cart/scc_wave.vhd
 $R/vdp/vdp_package.vhd $R/vdp/vdp_spinforam.vhd $R/vdp/vdp_sprite.vhd $R/vdp/vdp_hvcounter.vhd $R/vdp/vdp_ssg.vhd
 $R/vdp/vdp_interrupt.vhd $R/vdp/vdp_ntsc_pal.vhd $R/vdp/vdp_linebuf.vhd $R/vdp/vdp_doublebuf.vhd $R/vdp/vdp_vga.vhd
 $R/vdp/vdp_command.vhd $R/vdp/vdp_wait_control.vhd $R/vdp/vdp_colordec.vhd $R/vdp/vdp_text12.vhd
 $R/vdp/vdp_graphic123m.vhd $R/vdp/vdp_graphic4567.vhd $R/vdp/vdp_register.vhd $R/vdp/vdp.vhd"
# T80.vhd: its signal ALU_Q and the output Q of its instance alu both become alu_q in the netlist
# of ghdl: a copy with the signal renamed (for the simulation only)
sed -E 's/\bALU_Q\b/ALU_Q_s/g' "$R/T80/T80.vhd" > T80_sim.vhd
SRC=${SRC/$R\/T80\/T80.vhd/T80_sim.vhd}
ghdl -a $G $SRC
for e in t80pa vdp18_core cv_clock keyboard scc_wave vdp ram; do
	# "release" is a keyword of Verilog (a signal of keyboard.vhd); ghdl writes the escaped name of an
	# instance signal after its prefix ("u0_\reg "), which is no identifier: "u0_reg_x"
	ghdl --synth $G --out=verilog $e | sed -E -e "s/\brelease\b/release_s/g" -e 's/(\w)\\(\w+) /\1\2_x /g' > $e.v
done
# the generics are fixed in the netlists (their defaults, the values msx1.v sets): parameters for the
# instances; T80pa keeps the case of its VHDL name, msx1.v instantiates t80pa
python3 - <<'PY'
import re
for f, mod, par in (('vdp18_core.v', 'vdp18_core', 'compat_rgb_g'), ('t80pa.v', 'T80pa', 'Mode')):
    s = open(f).read()
    m = re.search(r'\nmodule ' + mod + r'\b[^;]*;', s)
    s = s[:m.end()] + '\n  parameter ' + par + ' = 0;' + s[m.end():]
    s = s.replace('\nmodule T80pa', '\nmodule t80pa')
    open(f, 'w').write(s)
# ram (cart/ram.vhd) is a submodule of scc_wave and of vdp too: one copy, ram.v (the same netlist
# with other net names)
for f in ('vdp.v', 'scc_wave.v'):
    s = open(f).read()
    s = re.sub(r'\nmodule ram\b.*?\nendmodule\n', '\n', s, flags=re.S)
    open(f, 'w').write(s)
# the names of vdp.v are those of its VHDL (upper case) for the ports of the top, lower case for
# the ports of its submodules: all lower case, as msx2.v names the ports (XST binds VHDL without
# case); a VHDL name differs from another in more than its case, a clash would be a redeclaration
# that verilator reports
s = open('vdp.v').read()
# PRAMDBO is 'Z' between the writes (a register driving Z, which verilator does not take): 0
s = s.lower().replace("8'bz", "8'b00000000")
open('vdp.v', 'w').write(s)
PY
