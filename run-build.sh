#!/bin/bash
# Yocto Raspberry Pi 4 build script — crops/yocto 컨테이너 내부에서 실행됨
set -e

# 로그를 파일에도 남김 (호스트에서 tail 가능)
exec > >(tee -a /workdir/build.log) 2>&1

# bitbake는 UTF-8 로케일 필요
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

echo "===== BUILD START ($(date)) ====="
cd /workdir

echo "=== [1/4] oe-init-build-env ==="
# build 디렉토리를 /workdir/build 로 초기화
source sources/poky/oe-init-build-env build

echo "=== [2/4] 레이어 추가 ==="
bitbake-layers add-layer ../sources/meta-raspberrypi || echo "(meta-raspberrypi 이미 추가됨)"
bitbake-layers add-layer ../meta-device-simulation || echo "(meta-device-simulation 이미 추가됨)"

echo "=== [3/4] local.conf 설정 (MACHINE=raspberrypi4-64) ==="
if ! grep -q '^# ---- RPi4 QEMU build settings' conf/local.conf; then
  cat >> conf/local.conf <<'EOF'

# ---- RPi4 QEMU build settings (added by run-build.sh) ----
MACHINE = "raspberrypi4-64"
BB_NUMBER_THREADS = "16"
PARALLEL_MAKE = "-j 16"
# QEMU/expect 자동 로그인을 위한 PL011 시리얼 콘솔
ENABLE_UART = "1"
SERIAL_CONSOLES = "115200;ttyAMA0"
# 개발용 PoC: root 무비밀번호 로그인 허용
EXTRA_IMAGE_FEATURES += "debug-tweaks"
# SD 카드 이미지 생성
IMAGE_FSTYPES = "wic.bz2 wic.gz"
EOF
fi

echo "=== 현재 레이어 목록 ==="
bitbake-layers show-layers

echo "=== [4/4] bitbake core-image-base 시작 ==="
bitbake core-image-base

echo "=== 빌드 완료. 결과 이미지: ==="
ls -lh tmp/deploy/images/raspberrypi4-64/ | grep -E "wic|\.rpi" || true
