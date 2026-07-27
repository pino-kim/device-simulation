#!/usr/bin/env bash
# 빌드된 Raspberry Pi 4 이미지를 QEMU로 부팅하고 콘솔에 바로 연결한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

for command in chmod cp mkdir stat truncate readlink screen stty tee; do
    require_command "$command"
done
[[ -x "$QEMU_BIN" ]] || die "먼저 ./build-qemu.sh를 실행하십시오."

KERNEL="${KERNEL:-$(find_single_artifact 'Image-raspberrypi4-64.bin')}"
DTB="${DTB:-$(find_single_artifact 'bcm2711-rpi-4-b-qemu-console.dtb')}"
SOURCE_WIC="${WIC:-$(find_single_artifact 'core-image-base-raspberrypi4-64*.wic')}"
CONSOLE_WIC="${CONSOLE_WIC:-$PROJECT_ROOT/poc/raspi4b/rpi4-console.wic}"
CONSOLE_TTY="${CONSOLE_TTY:-ttyAMA0}"
KERNEL_APPEND="${KERNEL_APPEND:-earlycon=pl011,mmio32,0xfe201000 console=$CONSOLE_TTY,115200 root=/dev/mmcblk1p2 rootwait rw init=/bin/sh}"
[[ -f "$DTB" ]] || die "DTB를 찾을 수 없습니다: $DTB"

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
echo "screen 종료: Ctrl+A, \\"

[[ -t 0 ]] || die "대화형 터미널에서 실행해야 합니다."
QEMU_LOG="$(mktemp)"
QEMU_PID=""
cleanup() {
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
    rm -f "$QEMU_LOG"
}
trap cleanup EXIT INT TERM

"$QEMU_BIN" \
    -M raspi4b \
    -cpu cortex-a72 \
    -m 2G \
    -smp 4 \
    -display none \
    -monitor none \
    -serial pty \
    -no-reboot \
    -kernel "$KERNEL" \
    -dtb "$DTB" \
    -drive "file=$CONSOLE_WIC,format=raw,if=sd" \
    -append "$KERNEL_APPEND" \
    > >(tee "$QEMU_LOG" >&2) 2>&1 &
QEMU_PID=$!

SERIAL_PTY=""
for _ in {1..100}; do
    SERIAL_PTY="$(sed -n 's/.*char device redirected to \(\/dev\/pts\/[0-9][0-9]*\).*/\1/p' "$QEMU_LOG" | tail -1)"
    [[ -n "$SERIAL_PTY" ]] && break
    kill -0 "$QEMU_PID" 2>/dev/null || break
    sleep 0.05
done

if [[ -z "$SERIAL_PTY" ]]; then
    cat "$QEMU_LOG" >&2
    die "QEMU 직렬 PTY를 찾지 못했습니다."
fi

echo "직렬 장치: $SERIAL_PTY"
stty -F "$SERIAL_PTY" 115200 raw -echo
SCREEN_DIR="${SCREEN_DIR:-${TMPDIR:-/tmp}/device-simulation-screen-$UID}"
mkdir -p "$SCREEN_DIR"
chmod 700 "$SCREEN_DIR"
SCREEN_TERM="${TERM:-xterm}"
[[ "$SCREEN_TERM" == "dumb" ]] && SCREEN_TERM="xterm"
TERM="$SCREEN_TERM" SCREENDIR="$SCREEN_DIR" screen "$SERIAL_PTY" 115200
