#!/usr/bin/env bash
# 빌드된 Raspberry Pi 4 이미지를 QEMU로 부팅하고 콘솔에 바로 연결한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

for command in cp stat truncate readlink; do
    require_command "$command"
done
[[ -x "$QEMU_BIN" ]] || die "먼저 ./build-qemu.sh를 실행하십시오."

KERNEL="${KERNEL:-$(find_single_artifact 'Image-raspberrypi4-64.bin')}"
DTB="${DTB:-$(find_single_artifact 'bcm2711-rpi-4-b.dtb')}"
SOURCE_WIC="${WIC:-$(find_single_artifact 'core-image-base-raspberrypi4-64*.wic')}"
CONSOLE_WIC="${CONSOLE_WIC:-$PROJECT_ROOT/poc/raspi4b/rpi4-console.wic}"

if [[ ! -f "$CONSOLE_WIC" || "${RESET_WIC:-0}" == "1" ]]; then
    echo "대화형 SD 이미지 준비: $CONSOLE_WIC"
    cp --reflink=auto "$SOURCE_WIC" "$CONSOLE_WIC"

    size="$(stat -c %s "$CONSOLE_WIC")"
    power=1
    while (( power < size )); do
        power=$((power * 2))
    done
    truncate -s "$power" "$CONSOLE_WIC"
else
    echo "기존 대화형 SD 이미지 재사용: $CONSOLE_WIC"
fi

echo "Raspberry Pi 4 콘솔을 시작합니다."
echo "게스트 종료: poweroff"
echo "QEMU 강제 종료: Ctrl+A, X"

exec "$QEMU_BIN" \
    -M raspi4b \
    -cpu cortex-a72 \
    -m 2G \
    -smp 4 \
    -nographic \
    -no-reboot \
    -kernel "$KERNEL" \
    -dtb "$DTB" \
    -drive "file=$CONSOLE_WIC,format=raw,if=sd" \
    -append "console=ttyAMA1,115200 earlycon=pl011,0xfe201000 root=/dev/mmcblk1p2 rootwait rw"
