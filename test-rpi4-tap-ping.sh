#!/usr/bin/env bash
# Create a private TAP and verify bidirectional ping with patched raspi4b GENET.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

TAP_IF="${TAP_IF:-rpi4tap0}"
HOST_CIDR="${HOST_CIDR:-192.168.76.1/24}"
GUEST_CIDR="${GUEST_CIDR:-192.168.76.2/24}"
GUEST_MAC="${GUEST_MAC:-52:54:00:12:34:56}"
RPI4_NET_DEVICE="${RPI4_NET_DEVICE:-genet}"
GUEST_IFACE="${GUEST_IFACE:-eth0}"
HOST_IP="${HOST_CIDR%/*}"
GUEST_IP="${GUEST_CIDR%/*}"
LOG="${LOG:-$PROJECT_ROOT/poc/raspi4b/tap-ping.log}"

[[ "$TAP_IF" =~ ^[a-zA-Z0-9_.-]{1,15}$ ]] ||
    die "안전하지 않은 TAP 인터페이스 이름입니다: $TAP_IF"
[[ "$HOST_CIDR" =~ ^[0-9.]+/[0-9]{1,2}$ ]] ||
    die "HOST_CIDR 형식이 잘못되었습니다: $HOST_CIDR"
[[ "$GUEST_CIDR" =~ ^[0-9.]+/[0-9]{1,2}$ ]] ||
    die "GUEST_CIDR 형식이 잘못되었습니다: $GUEST_CIDR"

if (( EUID != 0 )); then
    echo "TAP 생성에 root 권한이 필요합니다. sudo로 다시 실행합니다."
    exec sudo "$0" "$@"
fi

for command in cp ip ping python3 stat timeout truncate; do
    require_command "$command"
done
[[ -x "$QEMU_BIN" ]] || die "먼저 ./build-qemu.sh를 실행하십시오."

KERNEL="${KERNEL:-$(find_single_artifact 'Image-raspberrypi4-64.bin')}"
DTB="${DTB:-$(find_single_artifact 'bcm2711-rpi-4-b-qemu-console.dtb')}"
SOURCE_WIC="${WIC:-$(find_single_artifact 'core-image-base-raspberrypi4-64*.wic')}"
TEST_WIC="$(mktemp --suffix=.wic)"
tap_created=0

cleanup() {
    if (( tap_created )); then
        ip link set dev "$TAP_IF" down 2>/dev/null || true
        ip tuntap del dev "$TAP_IF" mode tap 2>/dev/null || true
    fi
    rm -f "$TEST_WIC"
    if [[ -n "${SUDO_UID:-}" && -e "$LOG" ]]; then
        chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$LOG" 2>/dev/null || true
    fi
}
trap cleanup EXIT INT TERM

if ip link show dev "$TAP_IF" >/dev/null 2>&1; then
    die "기존 인터페이스를 보호하기 위해 중단합니다: $TAP_IF"
fi

echo "TAP 생성: $TAP_IF ($HOST_CIDR)"
ip tuntap add dev "$TAP_IF" mode tap
tap_created=1
ip addr add "$HOST_CIDR" dev "$TAP_IF"
ip link set dev "$TAP_IF" up
ip neigh replace "$GUEST_IP" lladdr "$GUEST_MAC" \
    nud permanent dev "$TAP_IF"

cp --reflink=auto "$SOURCE_WIC" "$TEST_WIC"
size="$(stat -c %s "$TEST_WIC")"
power=1
while (( power < size )); do
    power=$((power * 2))
done
truncate -s "$power" "$TEST_WIC"

python3 "$PROJECT_ROOT/scripts/rpi4_tap_ping.py" \
    --qemu "$QEMU_BIN" \
    --kernel "$KERNEL" \
    --dtb "$DTB" \
    --disk "$TEST_WIC" \
    --tap "$TAP_IF" \
    --host-ip "$HOST_IP" \
    --guest-cidr "$GUEST_CIDR" \
    --guest-mac "$GUEST_MAC" \
    --network-device "$RPI4_NET_DEVICE" \
    --guest-iface "$GUEST_IFACE" \
    --log "$LOG" \
    --timeout "${BOOT_TIMEOUT:-120}"
