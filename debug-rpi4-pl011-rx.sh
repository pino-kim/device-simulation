#!/usr/bin/env bash
# QEMU raspi4b PL011 RX 경로를 PTY 강제 입력과 trace로 검증한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

for command in cp kill readlink sed socat stat tail tee truncate; do
    require_command "$command"
done
[[ -x "$QEMU_BIN" ]] || die "먼저 ./build-qemu.sh를 실행하십시오."

KERNEL="${KERNEL:-$(find_single_artifact 'Image-raspberrypi4-64.bin')}"
DTB="${DTB:-$(find_single_artifact 'bcm2711-rpi-4-b-qemu-console.dtb')}"
SOURCE_WIC="${WIC:-$(find_single_artifact 'core-image-base-raspberrypi4-64*.wic')}"
DEBUG_WIC="${DEBUG_WIC:-$PROJECT_ROOT/poc/raspi4b/rpi4-pl011-debug.wic}"
TRACE_EVENTS="${TRACE_EVENTS:-$PROJECT_ROOT/pl011-rx-events}"
TRACE_LOG="${TRACE_LOG:-$PROJECT_ROOT/qemu-pl011-trace.log}"
QEMU_LOG="${QEMU_LOG:-$PROJECT_ROOT/qemu-rpi4-debug.log}"
CONSOLE_LOG="${CONSOLE_LOG:-$PROJECT_ROOT/qemu-rpi4-console.log}"
BOOT_WAIT="${BOOT_WAIT:-5}"
INPUT_EOL="${INPUT_EOL:-lf}"
KERNEL_APPEND="${KERNEL_APPEND:-earlycon=pl011,mmio32,0xfe201000 console=ttyAMA0,115200 root=/dev/mmcblk1p2 rootwait rw init=/bin/sh}"

[[ -f "$DTB" ]] || die "DTB를 찾을 수 없습니다: $DTB"
[[ -f "$TRACE_EVENTS" ]] || die "trace event 파일을 찾을 수 없습니다: $TRACE_EVENTS"

cp --reflink=auto "$SOURCE_WIC" "$DEBUG_WIC"
size="$(stat -c %s "$DEBUG_WIC")"
power=1
while (( power < size )); do
    power=$((power * 2))
done
truncate -s "$power" "$DEBUG_WIC"
: >"$TRACE_LOG"
: >"$QEMU_LOG"
: >"$CONSOLE_LOG"

QEMU_PID=""
READER_PID=""
cleanup() {
    if [[ -n "$READER_PID" ]] && kill -0 "$READER_PID" 2>/dev/null; then
        kill "$READER_PID" 2>/dev/null || true
        wait "$READER_PID" 2>/dev/null || true
    fi
    if [[ -n "$QEMU_PID" ]] && kill -0 "$QEMU_PID" 2>/dev/null; then
        kill "$QEMU_PID" 2>/dev/null || true
        wait "$QEMU_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

"$QEMU_BIN" \
    -machine raspi4b \
    -cpu cortex-a72 \
    -smp 4 \
    -m 2G \
    -kernel "$KERNEL" \
    -dtb "$DTB" \
    -drive "file=$DEBUG_WIC,if=sd,format=raw" \
    -append "$KERNEL_APPEND" \
    -serial pty \
    -display none \
    -monitor none \
    -no-reboot \
    -trace "events=$TRACE_EVENTS,file=$TRACE_LOG" \
    > >(tee "$QEMU_LOG" >&2) 2>&1 &
QEMU_PID=$!

SERIAL_PTY=""
for _ in {1..100}; do
    SERIAL_PTY="$(sed -n 's/.*char device redirected to \(\/dev\/pts\/[0-9][0-9]*\).*/\1/p' "$QEMU_LOG" | tail -1)"
    [[ -n "$SERIAL_PTY" ]] && break
    kill -0 "$QEMU_PID" 2>/dev/null || break
    sleep 0.05
done
[[ -n "$SERIAL_PTY" ]] || die "QEMU 직렬 PTY를 찾지 못했습니다."

echo "PL011 PTY: $SERIAL_PTY"
socat -u "FILE:$SERIAL_PTY,raw,echo=0,b115200" - >"$CONSOLE_LOG" &
READER_PID=$!

sleep "$BOOT_WAIT"
case "$INPUT_EOL" in
    cr) printf 'echo QEMU_PL011_RX_CR_OK\r' ;;
    lf) printf 'echo QEMU_PL011_RX_LF_OK\n' ;;
    *) die "INPUT_EOL은 cr 또는 lf여야 합니다: $INPUT_EOL" ;;
esac | socat -u - "FILE:$SERIAL_PTY,raw,echo=0,b115200"
sleep 2

echo "trace: $TRACE_LOG"
echo "qemu: $QEMU_LOG"
echo "console: $CONSOLE_LOG"
