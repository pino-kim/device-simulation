#!/bin/bash
# Run the Raspberry Pi 4 image with virtio-gpu, USB input, and optional VNC.
set -euo pipefail

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
QEMU="${BASE}/qemu-install/bin/qemu-system-aarch64"
DEPLOY="${BASE}/build/tmp/deploy/images/raspberrypi4-64"
KERNEL="${DEPLOY}/Image-raspberrypi4-64.bin"
DTB="${DEPLOY}/bcm2711-rpi-4-b-qemu-console.dtb"
SOURCE_WIC="${DEPLOY}/core-image-base-raspberrypi4-64.rootfs.wic"
WAYLAND_WIC="${BASE}/poc/raspi4b/rpi4b-wayland.wic"
MONITOR_SOCKET="${RPI4_MONITOR_SOCKET:-/tmp/rpi4-wayland-monitor.sock}"
VNC_ADDRESS=127.0.0.1:1
FRESH=0

usage() {
    cat <<'EOF'
Usage: bash poc/raspi4b/run-wayland.sh [--fresh] [--vnc HOST:DISPLAY]

  --fresh              recreate the writable SD image from the latest Yocto WIC
  --vnc HOST:DISPLAY    change the VNC address (default: 127.0.0.1:1)

The guest always receives an emulated USB keyboard and absolute-position
USB tablet. For remote access, prefer an SSH tunnel instead of exposing VNC:
  ssh -L 5901:127.0.0.1:5901 USER@QEMU_HOST
  vncviewer 127.0.0.1:5901
EOF
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --fresh)
            FRESH=1
            shift
            ;;
        --vnc)
            shift
            if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then
                VNC_ADDRESS=$1
                shift
            fi
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            usage >&2
            exit 2
            ;;
    esac
done

for required in "$QEMU" "$KERNEL" "$DTB" "$SOURCE_WIC"; do
    if [ ! -f "$required" ]; then
        echo "Required file is missing: $required" >&2
        exit 1
    fi
done

if [ "$FRESH" -eq 1 ] || [ ! -f "$WAYLAND_WIC" ]; then
    cp --reflink=auto "$SOURCE_WIC" "$WAYLAND_WIC"
    image_size=$(stat -c %s "$WAYLAND_WIC")
    sd_size=1
    while [ "$sd_size" -lt "$image_size" ]; do
        sd_size=$((sd_size * 2))
    done
    truncate -s "$sd_size" "$WAYLAND_WIC"
fi

display_args=(-display "vnc=${VNC_ADDRESS}")
port=$((5900 + ${VNC_ADDRESS##*:}))
echo "VNC is listening on ${VNC_ADDRESS} (TCP ${port})"
rm -f "$MONITOR_SOCKET"
echo "QEMU monitor socket: ${MONITOR_SOCKET}"

exec "$QEMU" \
    -M raspi4b \
    -cpu cortex-a72 \
    -smp 4 \
    -m 2G \
    -kernel "$KERNEL" \
    -dtb "$DTB" \
    -drive "file=${WAYLAND_WIC},format=raw,if=sd" \
    -device virtio-gpu-pci,id=vgpu0,bus=pcie.1,addr=0.0,multifunction=on,disable-legacy=on,vectors=0,xres=800,yres=480 \
    -device qemu-xhci,id=xhci,bus=pcie.1,addr=0.1,msi=off,msix=off \
    -device usb-kbd,bus=xhci.0 \
    -device usb-tablet,bus=xhci.0 \
    "${display_args[@]}" \
    -serial stdio \
    -monitor "unix:${MONITOR_SOCKET},server=on,wait=off" \
    -no-reboot \
    -append "earlycon=pl011,mmio32,0xfe201000 console=ttyAMA0,115200 root=/dev/mmcblk1p2 rootwait rw"
