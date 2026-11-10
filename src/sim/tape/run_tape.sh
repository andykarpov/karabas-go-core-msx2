#!/bin/bash
# The cassette tests (tape.txt) in parallel, about 4 minutes: sim_sys with C-BIOS, the tape test cartridge
# (mktape.py) in slot 2, a CAS file loaded by the file loader at the rate of a 32 MHz burst
# (SIM_FILE_GAP=10) while the disk image fills the SRAM (a disk in the drive, its ROM off), then
# played: the CRC of the last frame against tape.txt and no wrong byte of the CAS file in the SRAM.
# Build sim_sys first (sim/sys/build.sh).
set -eu
S=$(cd "$(dirname "$0")/../.." && pwd)
cd "$S"
B=$S/sim/build
[ -x $B/sys/sim_sys ] || { echo "no $B/sys/sim_sys: run sim/sys/build.sh"; exit 1; }
python3 sim/tape/mktape.py $B/tape > /dev/null
python3 sim/fdd/mkfdd.py $B/fdd > /dev/null
mkdir -p $B/out
pids=()
while read -r name cas frames crc; do
	SIM_NO_DISKROM=1 SIM_FILE_GAP=10 $B/sys/sim_sys --cbios $S/roms --fast-logo \
		--cart-b $B/tape/tapetest.rom --cas $B/tape/$cas --disk $B/fdd/test720.dsk --fdd-latency 2 \
		--frames "$frames" --hash --ppm $B/out/tape_$name.ppm > $B/out/tape_$name.log 2>&1 &
	pids+=($!)
done < <(grep -v '^#' $S/sim/tape/tape.txt)
for p in "${pids[@]}"; do wait "$p"; done
err=0
while read -r name cas frames crc; do
	got=$(sed -n "s/^frame $frames crc \([0-9a-f]*\).*/\1/p" $B/out/tape_$name.log)
	sram=$(sed -n 's/^cas: .* \([0-9]*\) wrong in the SRAM/\1/p' $B/out/tape_$name.log)
	if [ "$got" = "$crc" ] && [ "$sram" = "0" ]; then echo "$name: ok"
	else echo "$name: FAIL (crc $got, expected $crc; SRAM: ${sram:-?} wrong bytes)"; err=$((err + 1)); fi
done < <(grep -v '^#' $S/sim/tape/tape.txt)
echo "run_tape: $err errors"
[ $err -eq 0 ]
