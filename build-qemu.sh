#!/bin/bash
# crops 컨테이너(Ubuntu 22.04) 내부에서 root로 실행 — virt 머신용 QEMU 8.2 빌드
set -e
exec > >(tee -a /workdir/qemu-build.log) 2>&1
echo "===== QEMU BUILD START ($(date)) ====="

export DEBIAN_FRONTEND=noninteractive
echo "=== [1/5] 빌드 의존성 설치 ==="
apt-get update -qq
apt-get install -y -qq build-essential wget xz-utils pkg-config \
    libglib2.0-dev libpixman-1-dev python3 python3-pip python3-venv \
    flex bison ninja-build >/dev/null
# meson은 22.04 apt(0.61)가 낮아 pip로 최신 설치
pip3 install -q --upgrade meson ninja

echo "=== [2/5] qemu 8.2.0 소스 다운로드 ==="
cd /workdir
if [ ! -f qemu-8.2.0.tar.xz ]; then
  wget -q https://download.qemu.org/qemu-8.2.0.tar.xz
fi
rm -rf qemu-8.2.0
tar xf qemu-8.2.0.tar.xz

echo "=== [3/5] configure (aarch64-softmmu만) ==="
cd qemu-8.2.0
./configure --target-list=aarch64-softmmu --prefix=/workdir/qemu-install \
    --disable-docs --disable-gtk --disable-sdl --disable-vnc

echo "=== [4/5] make ==="
make -j16

echo "=== [5/5] install ==="
make install

echo "=== 완료: 버전 및 virt 머신 지원 확인 ==="
/workdir/qemu-install/bin/qemu-system-aarch64 --version | head -1
/workdir/qemu-install/bin/qemu-system-aarch64 -machine help | grep -E '^virt( |-)'
echo "===== QEMU BUILD DONE ($(date)) ====="
