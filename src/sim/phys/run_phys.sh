#!/bin/bash
# The physical floppy drives of the Karabas Go (tb_phys.v, verilator --timing; iverilog takes minutes):
# vy0010 with the VG93 model on two drive models (fdd_model.v of the PCXT core), the disk of drive A at
# the nominal speed and 2 % off, in parallel, about 30 s with the build. Ends with "run_phys: N errors".
set -eu
S=$(cd "$(dirname "$0")/../.." && pwd)
cd "$S"
B=$S/sim/build/phys
mkdir -p $B
M=$S/../modules/rtl
verilator --binary --timing -j 8 -O3 --top-module tb_phys -Mdir $B/obj -o tb_phys -Irtl/vg93 \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING \
	sim/phys/tb_phys.v sim/phys/fdd_model.v rtl/msx/cart/vy0010.v rtl/msx/cart/wd1793.v rtl/msx/spram.v \
	$M/mem/kg_spram.v rtl/msx_fdc_phys.v rtl/vg93/vg93_*.v > $B/build.log 2>&1 || { tail -30 $B/build.log; exit 1; }
SPEEDS="1.0 1.02 0.98"
pids=()
for sp in $SPEEDS; do
	$B/obj/tb_phys +speed=$sp > $B/tb_phys_$sp.log 2>&1 &
	pids+=($!)
done
for p in "${pids[@]}"; do wait "$p" || true; done
err=0
for sp in $SPEEDS; do
	if grep -q "tb_phys: 0 errors" $B/tb_phys_$sp.log; then echo "speed $sp: ok"
	else echo "speed $sp: FAIL"; grep -E "ERROR|time out" $B/tb_phys_$sp.log | head -20; err=$((err + 1)); fi
done
echo "run_phys: $err errors"
[ $err -eq 0 ]
