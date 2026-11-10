#!/bin/bash
# The disk drive tests (fdd.txt) in parallel, about 4 minutes: sim_sys with C-BIOS, the FDC test cartridge
# in slot 2 and an image in the drive of slot 1 on the model of the file mounter, the CRC of the last
# frame against fdd.txt. C-BIOS hangs in the INIT of the Philips disk ROM (it needs a real BIOS): the
# tests run with the disk ROM off (SIM_NO_DISKROM: fdd_rom_en 0, the OSD option "Disk (no ROM)").
# Build sim_sys first (sim/sys/build.sh).
set -eu
S=$(cd "$(dirname "$0")/../.." && pwd)
cd "$S"
B=$S/sim/build
[ -x $B/sys/sim_sys ] || { echo "no $B/sys/sim_sys: run sim/sys/build.sh"; exit 1; }
python3 sim/fdd/mkfdd.py $B/fdd > /dev/null
mkdir -p $B/out
pids=()
while read -r name rom disk lat drop frames crc; do
	SIM_FDD=1 SIM_NO_DISKROM=1 $B/sys/sim_sys --cbios $S/roms --fast-logo \
		--cart-b $B/fdd/$rom --disk $B/fdd/$disk --fdd-latency "$lat" --fdd-drop "$drop" \
		--frames "$frames" --hash --ppm $B/out/fdd_$name.ppm > $B/out/fdd_$name.log 2>&1 &
	pids+=($!)
done < <(grep -v '^#' $S/sim/fdd/fdd.txt)
for p in "${pids[@]}"; do wait "$p"; done
err=0
while read -r name rom disk lat drop frames crc; do
	got=$(sed -n "s/^frame $frames crc \([0-9a-f]*\).*/\1/p" $B/out/fdd_$name.log)
	if [ "$got" = "$crc" ]; then echo "$name: ok"; else echo "$name: FAIL (crc $got, expected $crc)"; err=$((err + 1)); fi
done < <(grep -v '^#' $S/sim/fdd/fdd.txt)
echo "run_fdd: $err errors"
[ $err -eq 0 ]
