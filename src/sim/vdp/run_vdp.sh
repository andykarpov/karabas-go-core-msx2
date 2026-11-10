#!/bin/bash
# The VDP tests (vdp.txt) in parallel, about 3 minutes: sim_sys with C-BIOS MSX2+ (--fast-logo) and a
# test cartridge of mkvdp.py in slot 1, the CRC of the last frame against vdp.txt. The frames go to
# sim/build/out/vdp_<name>.ppm. Build sim_sys first (sim/sys/build.sh). Run from anywhere.
set -eu
S=$(cd "$(dirname "$0")/../.." && pwd)
cd "$S"
B=sim/build
[ -x $B/sys/sim_sys ] || { echo "no $B/sys/sim_sys: run sim/sys/build.sh"; exit 1; }
python3 sim/vdp/mkvdp.py $B/vdp > /dev/null 2>&1
mkdir -p $B/out
pids=()
while read -r name frames crc args; do
	./$B/sys/sim_sys --cbios roms --fast-logo --cart $B/vdp/$name.rom --frames "$frames" --hash \
		--ppm $B/out/vdp_$name.ppm $args > $B/out/vdp_$name.log 2>&1 &
	pids+=($!)
done < <(grep -v '^#' sim/vdp/vdp.txt)
for p in "${pids[@]}"; do wait "$p"; done
err=0
while read -r name frames crc args; do
	got=$(sed -n "s/^frame $frames crc \([0-9a-f]*\).*/\1/p" $B/out/vdp_$name.log)
	if [ "$got" != "$crc" ]; then echo "$name: FAIL (crc $got, expected $crc)"; err=$((err + 1))
	else echo "$name: ok"; fi
done < <(grep -v '^#' sim/vdp/vdp.txt)
echo "run_vdp: $err errors"
[ $err -eq 0 ]
