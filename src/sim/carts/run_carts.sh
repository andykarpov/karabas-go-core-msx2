#!/bin/bash
# The cartridge tests (carts.txt) in parallel, about 4 minutes: sim_sys with C-BIOS from the ROM loader
# and a test cartridge from the file loader, the CRC of the last frame against carts.txt. The frames go to
# sim/build/out/<name>.ppm. Build sim_sys first (sim/sys/build.sh). Run from anywhere.
set -eu
S=$(cd "$(dirname "$0")/../.." && pwd)
cd "$S"
B=sim/build
[ -x $B/sys/sim_sys ] || { echo "no $B/sys/sim_sys: run sim/sys/build.sh"; exit 1; }
python3 sim/carts/mkcarts.py $B/carts > /dev/null
mkdir -p $B/out
pids=()
while read -r name cart mapper frames crc args; do
	./$B/sys/sim_sys --cbios roms --fast-logo \
		--cart $B/carts/$cart --mapper-a "$mapper" --frames "$frames" --hash --ppm $B/out/$name.ppm $args \
		> $B/out/$name.log 2>&1 &
	pids+=($!)
done < <(grep -v '^#' sim/carts/carts.txt)
for p in "${pids[@]}"; do wait "$p"; done
err=0
while read -r name cart mapper frames crc args; do
	got=$(sed -n "s/^frame $frames crc \([0-9a-f]*\).*/\1/p" $B/out/$name.log)
	audio=$(sed -n "s/^audio range //p" $B/out/$name.log)
	if [ "$got" != "$crc" ]; then echo "$name: FAIL (crc $got, expected $crc)"; err=$((err + 1))
	elif [ "${audio% FAIL}" != "$audio" ]; then echo "$name: FAIL (audio range ${audio% FAIL})"; err=$((err + 1))
	else echo "$name: ok"; fi
done < <(grep -v '^#' sim/carts/carts.txt)
echo "run_carts: $err errors"
[ $err -eq 0 ]
