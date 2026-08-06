#!/bin/bash
# QEMU raspi4b 대화형 시리얼 콘솔
set -euo pipefail

BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
QEMU="${BASE}/qemu-install/bin/qemu-system-aarch64"
KERNEL="${BASE}/build/tmp/deploy/images/raspberrypi4-64/Image-raspberrypi4-64.bin"
DTB="${BASE}/build/tmp/deploy/images/raspberrypi4-64/bcm2711-rpi-4-b-qemu-console.dtb"
SOURCE_WIC="${BASE}/rpi4.wic"
CONSOLE_WIC="${BASE}/poc/raspi4b/rpi4b-console.wic"
RUNNER=${TEST_CONTAINER_IMAGE:-device-simulation-test:latest}
FRESH=0

usage() {
    cat <<'EOF'
Usage: bash poc/raspi4b/run-console.sh [--fresh]

  --fresh  기존 콘솔용 SD 이미지를 버리고 rpi4.wic에서 다시 생성
  -h       도움말 출력

로그인:
  raspberrypi4-64 login: root
  비밀번호: 없음

QEMU 키:
  Ctrl-a h  도움말
  Ctrl-a c  시리얼 콘솔/QEMU monitor 전환
  Ctrl-a x  QEMU 강제 종료

정상 종료:
  root 셸에서 poweroff
EOF
}

case "${1:-}" in
    "")
        ;;
    --fresh)
        FRESH=1
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

for required in "$QEMU" "$KERNEL" "$DTB" "$SOURCE_WIC"; do
    if [ ! -f "$required" ]; then
        echo "필수 파일이 없습니다: $required" >&2
        exit 1
    fi
done

if ! docker inspect "$RUNNER" >/dev/null 2>&1; then
    echo "[준비] 테스트 러너 이미지 빌드 중..."
    TEST_CONTAINER_IMAGE="$RUNNER" "$BASE/build-test-image.sh"
fi

if [ "$FRESH" -eq 1 ] || [ ! -f "$CONSOLE_WIC" ]; then
    echo "[준비] 콘솔용 SD 이미지 생성: $CONSOLE_WIC"
    cp -f "$SOURCE_WIC" "$CONSOLE_WIC"
    image_size=$(stat -c %s "$CONSOLE_WIC")
    sd_size=1
    while [ "$sd_size" -lt "$image_size" ]; do
        sd_size=$((sd_size * 2))
    done
    truncate -s "$sd_size" "$CONSOLE_WIC"
    echo "[준비] QEMU SD 크기: ${sd_size} bytes"
else
    echo "[재사용] 기존 콘솔용 SD 이미지: $CONSOLE_WIC"
fi

echo "[접속] 로그인 계정 root, 비밀번호 없음"
echo "[종료] 게스트에서 poweroff (강제 종료: Ctrl-a x)"

exec docker run --rm -it \
    --security-opt seccomp=unconfined \
    -v "$BASE":/workdir \
    -w /workdir \
    "$RUNNER" \
    /workdir/qemu-install/bin/qemu-system-aarch64 \
    -M raspi4b \
    -cpu cortex-a72 \
    -m 2G \
    -nographic \
    -no-reboot \
    -kernel /workdir/build/tmp/deploy/images/raspberrypi4-64/Image-raspberrypi4-64.bin \
    -dtb /workdir/build/tmp/deploy/images/raspberrypi4-64/bcm2711-rpi-4-b-qemu-console.dtb \
    -drive file=/workdir/poc/raspi4b/rpi4b-console.wic,format=raw,if=sd \
    -append "console=ttyAMA0,115200 earlycon=pl011,0xfe201000 root=/dev/mmcblk1p2 rootwait rw"
