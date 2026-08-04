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
DEFAULT_KERNEL_APPEND="earlycon=pl011,mmio32,0xfe201000 console=$CONSOLE_TTY,115200 root=/dev/mmcblk1p2 rootwait rw"
if [[ "${DIRECT_SHELL:-0}" == "1" ]]; then
    DEFAULT_KERNEL_APPEND+=" init=/bin/sh"
fi
KERNEL_APPEND="${KERNEL_APPEND:-$DEFAULT_KERNEL_APPEND}"
RPI4_NET_MODE="${RPI4_NET_MODE:-none}"
RPI4_NET_SOCKET="${RPI4_NET_SOCKET:-listen=:12345}"
RPI4_NET_TAP="${RPI4_NET_TAP:-rpi4tap0}"
RPI4_PCIE_DEVICE="${RPI4_PCIE_DEVICE:-none}"
[[ -f "$DTB" ]] || die "DTB를 찾을 수 없습니다: $DTB"

if [[ "$RPI4_NET_MODE" == "tap" ]]; then
    require_command ip
    [[ "$RPI4_NET_TAP" =~ ^[a-zA-Z0-9_.-]{1,15}$ ]] ||
        die "안전하지 않은 TAP 인터페이스 이름입니다: $RPI4_NET_TAP"
    ip link show dev "$RPI4_NET_TAP" >/dev/null 2>&1 ||
        die "TAP 인터페이스가 없습니다: $RPI4_NET_TAP
먼저 Host에서 TAP을 생성하고 IP를 설정하십시오:
  sudo ip tuntap add dev $RPI4_NET_TAP mode tap user $USER
  sudo ip addr add 192.168.76.1/24 dev $RPI4_NET_TAP
  sudo ip link set $RPI4_NET_TAP up"
fi

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
QEMU_NET_ARGS=()
case "$RPI4_PCIE_DEVICE" in
    none)
        case "$RPI4_NET_MODE" in
            none) ;;
            user) QEMU_NET_ARGS=(-nic user,model=bcm2838-genet) ;;
            socket) QEMU_NET_ARGS=(-nic "socket,model=bcm2838-genet,$RPI4_NET_SOCKET") ;;
            tap)
                QEMU_NET_ARGS=(
                    -nic "tap,model=bcm2838-genet,ifname=$RPI4_NET_TAP,script=no,downscript=no"
                )
                ;;
            *) die "RPI4_NET_MODE은 none, user, socket, tap 중 하나여야 합니다." ;;
        esac
        ;;
    virtio-net-pci)
        case "$RPI4_NET_MODE" in
            none)
                QEMU_NET_ARGS=(
                    -device virtio-net-pci,bus=pcie.1,disable-modern=off,disable-legacy=on,vectors=0
                )
                ;;
            user)
                QEMU_NET_ARGS=(
                    -netdev user,id=pcienet0
                    -device virtio-net-pci,bus=pcie.1,netdev=pcienet0,disable-modern=off,disable-legacy=on,vectors=0
                )
                ;;
            socket)
                QEMU_NET_ARGS=(
                    -netdev "socket,id=pcienet0,$RPI4_NET_SOCKET"
                    -device virtio-net-pci,bus=pcie.1,netdev=pcienet0,disable-modern=off,disable-legacy=on,vectors=0
                )
                ;;
            tap)
                QEMU_NET_ARGS=(
                    -netdev "tap,id=pcienet0,ifname=$RPI4_NET_TAP,script=no,downscript=no"
                    -device virtio-net-pci,bus=pcie.1,netdev=pcienet0,disable-modern=off,disable-legacy=on,vectors=0
                )
                ;;
            *) die "RPI4_NET_MODE은 none, user, socket, tap 중 하나여야 합니다." ;;
        esac
        ;;
    *)
        die "RPI4_PCIE_DEVICE는 none 또는 virtio-net-pci여야 합니다."
        ;;
esac
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
    "${QEMU_NET_ARGS[@]}" \
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
