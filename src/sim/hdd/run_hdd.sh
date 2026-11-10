#!/bin/bash
# The Nextor SD interface tests (hdd.txt) in parallel, about 3 minutes: sim_sys with C-BIOS, the test
# cartridge sdtest.rom (mkhdd.py) in slot 2, slot 1 the SD interface (--nextor) without its ROM
# (--no-slot1-rom: C-BIOS would start the Nextor ROM and hang, it needs a real BIOS), the hard disk image
# test.img on F slot 6 of the model of the file mounter. Checked: the CRC of the last frame ("SD ... OK")
# and the image saved after the run (the written sectors 7, 20, 21, the others unchanged).
# Build sim_sys first (sim/sys/build.sh).
set -eu
S=$(cd "$(dirname "$0")/../.." && pwd)
cd "$S"
B=$S/sim/build
[ -x $B/sys/sim_sys ] || { echo "no $B/sys/sim_sys: run sim/sys/build.sh"; exit 1; }
python3 sim/hdd/mkhdd.py $B/hdd > /dev/null
mkdir -p $B/out
pids=()
while read -r name lat drop frames crc; do
	SIM_FDD=1 $B/sys/sim_sys --cbios $S/roms --fast-logo \
		--cart-b $B/hdd/sdtest.rom --nextor --no-slot1-rom --hdd $B/hdd/test.img --save-hdd $B/out/hdd_$name.img \
		--fdd-latency "$lat" --fdd-drop "$drop" --frames "$frames" --hash --ppm $B/out/hdd_$name.ppm > $B/out/hdd_$name.log 2>&1 &
	pids+=($!)
done < <(grep -v '^#' $S/sim/hdd/hdd.txt)
for p in "${pids[@]}"; do wait "$p"; done
err=0
while read -r name lat drop frames crc; do
	got=$(sed -n "s/^frame $frames crc \([0-9a-f]*\).*/\1/p" $B/out/hdd_$name.log)
	img=$(python3 - "$B/hdd/test.img" "$B/out/hdd_$name.img" <<'PY'
import sys
a = open(sys.argv[1], 'rb').read()
b = open(sys.argv[2], 'rb').read()
want = {7: 0x3C, 20: 20, 21: 21}
bad = []
for n in range(len(a) // 512):
    s = b[n * 512:(n + 1) * 512]
    exp = bytes((i & 0xFF) ^ want[n] for i in range(512)) if n in want else a[n * 512:(n + 1) * 512]
    if s != exp:
        bad.append(n)
print('ok' if not bad else 'sectors ' + ' '.join(map(str, bad[:8])))
PY
)
	if [ "$got" != "$crc" ]; then echo "$name: FAIL (crc $got, expected $crc)"; err=$((err + 1))
	elif [ "$img" != "ok" ]; then echo "$name: FAIL (image: $img)"; err=$((err + 1))
	else echo "$name: ok"; fi
done < <(grep -v '^#' $S/sim/hdd/hdd.txt)
echo "run_hdd: $err errors"
[ $err -eq 0 ]
