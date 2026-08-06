#!/usr/bin/env bash
# Patched raspi4b PCIe/GENET model boot smoke test.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

for command in cp grep mktemp stat timeout truncate; do
    require_command "$command"
done
[[ -x "$QEMU_BIN" ]] || die "먼저 ./build-qemu.sh를 실행하십시오."

KERNEL="${KERNEL:-$(find_single_artifact 'Image-raspberrypi4-64.bin')}"
DTB="${DTB:-$(find_single_artifact 'bcm2711-rpi-4-b-qemu-console.dtb')}"
SOURCE_WIC="${WIC:-$(find_single_artifact 'core-image-base-raspberrypi4-64*.wic')}"
TEST_WIC="$(mktemp --suffix=.wic)"
LOG="${LOG:-$PROJECT_ROOT/poc/raspi4b/network-boot.log}"
SOCKET="${RPI4_NET_SOCKET:-listen=:12345}"

cleanup() {
    rm -f "$TEST_WIC"
}
trap cleanup EXIT INT TERM

cp --reflink=auto "$SOURCE_WIC" "$TEST_WIC"
size="$(stat -c %s "$TEST_WIC")"
power=1
while (( power < size )); do
    power=$((power * 2))
done
truncate -s "$power" "$TEST_WIC"

set +e
timeout "${BOOT_TIMEOUT:-45}s" "$QEMU_BIN" \
    -M raspi4b \
    -cpu cortex-a72 \
    -m 2G \
    -smp 4 \
    -display none \
    -monitor none \
    -serial stdio \
    -no-reboot \
    -kernel "$KERNEL" \
    -dtb "$DTB" \
    -drive "file=$TEST_WIC,format=raw,if=sd" \
    -append "earlycon=pl011,mmio32,0xfe201000 console=ttyAMA0,115200 root=/dev/mmcblk1p2 rootwait rw" \
    -nic "socket,$SOCKET" \
    > "$LOG" 2>&1
status=$?
set -e

if [[ "$status" -ne 0 && "$status" -ne 124 ]]; then
    tail -n 100 "$LOG" >&2
    die "QEMU PCIe/GENET 부팅 시험에 실패했습니다."
fi

grep -q 'brcm-pcie .*PCI host bridge to bus' "$LOG" ||
    die "PCIe host bridge가 초기화되지 않았습니다: $LOG"
grep -q 'bcmgenet .*GENET 5.0' "$LOG" ||
    die "GENET 컨트롤러가 probe되지 않았습니다: $LOG"
grep -Eq 'bcmgenet .*eth0: Link is (Up|Down)' "$LOG" ||
    die "eth0가 초기화되지 않았습니다: $LOG"
if grep -q 'failed to initialize DMA' "$LOG"; then
    die "GENET DMA 초기화가 실패했습니다: $LOG"
fi

echo "PASS: raspi4b PCIe host bridge와 GENET eth0 초기화"
echo "로그: $LOG"
