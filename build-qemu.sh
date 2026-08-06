#!/bin/bash
# Build the latest stable QEMU with raspi4b support in Ubuntu 22.04 crops.
set -euo pipefail

exec > >(tee -a /workdir/qemu-build.log) 2>&1
QEMU_VERSION=${QEMU_VERSION:-11.0.3}
JOBS=${QEMU_BUILD_JOBS:-16}
ARCHIVE="qemu-${QEMU_VERSION}.tar.xz"
SOURCE="qemu-${QEMU_VERSION}"

echo "===== QEMU ${QEMU_VERSION} BUILD START ($(date)) ====="
export DEBIAN_FRONTEND=noninteractive

apt-get update -qq
apt-get install -y -qq \
    build-essential flex bison ninja-build patch pkg-config python3 python3-pip \
    python3-venv python3-tomli wget xz-utils libglib2.0-dev libpixman-1-dev \
    libslirp-dev libusb-1.0-0-dev >/dev/null

cd /workdir
if [ ! -f "$ARCHIVE" ]; then
    wget -q "https://download.qemu.org/${ARCHIVE}"
fi

rm -rf "$SOURCE" "${SOURCE}-build"
tar -xf "$ARCHIVE"

PATCH_DIR="/workdir/qemu-patches/20260725-rpi4-pcie-genet"
mapfile -t QEMU_PATCHES < <(find "$PATCH_DIR" -maxdepth 1 -type f \
    -name '*.patch' -print | sort)
if [ "${#QEMU_PATCHES[@]}" -ne 24 ]; then
    echo "Expected 24 Raspberry Pi PCIe/GENET patches in: $PATCH_DIR" >&2
    exit 1
fi
for qemu_patch in "${QEMU_PATCHES[@]}"; do
    echo "Applying $(basename "$qemu_patch")"
    patch --batch --forward --fuzz=0 -d "$SOURCE" -p1 < "$qemu_patch"
done

mkdir -p "${SOURCE}-build"
cd "${SOURCE}-build"

"/workdir/${SOURCE}/configure" \
    --target-list=aarch64-softmmu \
    --prefix=/workdir/qemu-install \
    --enable-slirp \
    --enable-libusb \
    --disable-docs \
    --disable-gtk \
    --disable-sdl \
    --disable-vnc

ninja -j "$JOBS"
ninja install

/workdir/qemu-install/bin/qemu-system-aarch64 --version | head -1
/workdir/qemu-install/bin/qemu-system-aarch64 -machine help | grep '^raspi4b '
echo "===== QEMU ${QEMU_VERSION} BUILD DONE ($(date)) ====="
