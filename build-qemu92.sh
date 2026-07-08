#!/bin/bash
# crops 컨테이너(root)에서 QEMU 9.2 빌드 — raspi4b 머신(BCM2711) 포함, slirp 포함
set -e
exec > >(tee -a /workdir/qemu92-build.log) 2>&1
echo "===== QEMU 9.2 BUILD START ($(date)) ====="

export DEBIAN_FRONTEND=noninteractive
echo "=== [1/5] 의존성 ==="
apt-get update -qq
apt-get install -y -qq build-essential wget xz-utils pkg-config \
    libglib2.0-dev libpixman-1-dev libslirp-dev python3 python3-pip python3-venv \
    flex bison ninja-build >/dev/null
pip3 install -q --upgrade meson ninja tomli

echo "=== [2/5] 소스 다운로드 (9.2.0) ==="
cd /workdir
[ -f qemu-9.2.0.tar.xz ] || wget -q https://download.qemu.org/qemu-9.2.0.tar.xz
rm -rf qemu-9.2.0 && tar xf qemu-9.2.0.tar.xz

echo "=== [3/5] configure (aarch64-softmmu, slirp) ==="
cd qemu-9.2.0
./configure --target-list=aarch64-softmmu --prefix=/workdir/qemu92-install \
    --enable-slirp --disable-docs --disable-gtk --disable-sdl --disable-vnc

echo "=== [4/5] make ==="
make -j16

echo "=== [5/5] install ==="
make install

echo "=== raspi4 머신 확인 ==="
/workdir/qemu92-install/bin/qemu-system-aarch64 --version | head -1
/workdir/qemu92-install/bin/qemu-system-aarch64 -machine help | grep -i raspi
echo "===== QEMU 9.2 BUILD DONE ($(date)) ====="
