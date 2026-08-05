#!/bin/bash
# raspi4b(T3) 자동테스트 하니스 — SD 이미지에 바이너리 주입 → 부팅·실행 → 결과 회수
# raspi4b엔 virtio-9p가 없으므로, 호스트에서 SD rootfs를 마운트해 파일을 주고받는다.
# 사용법: (앱을 넣으려면) cp myapp poc/raspi4b/testfiles/  후  bash poc/raspi4b/run-poc-raspi4b.sh
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SRC_WIC=$BASE/rpi4.wic                       # ttyAMA0 getty 포함 rootfs
SD=$BASE/poc/raspi4b/rpi4b-test.wic
OFF=$((155648*512))                          # p2(rootfs) 시작 오프셋
RUNNER=${TEST_CONTAINER_IMAGE:-device-simulation-test:latest}

if ! docker inspect "$RUNNER" >/dev/null 2>&1; then
  echo "[준비] 테스트 러너 이미지 빌드 중..."
  TEST_CONTAINER_IMAGE="$RUNNER" "$BASE/build-test-image.sh"
fi

echo "[1/4] SD 이미지 준비 (raspi4b가 요구하는 2의 거듭제곱 크기로 확장)"
cp -f "$SRC_WIC" "$SD"
image_size=$(stat -c %s "$SD")
sd_size=1
while [ "$sd_size" -lt "$image_size" ]; do
  sd_size=$((sd_size * 2))
done
truncate -s "$sd_size" "$SD"
echo "  QEMU SD 크기: ${sd_size} bytes"

echo "[2/4] 테스트/바이너리 주입 (rootfs p2 → /home/root/hosttest)"
docker run --rm --privileged -v "$BASE":/workdir "$RUNNER" bash -c "
  mkdir -p /mnt/p2 && mount -o loop,offset=$OFF /workdir/poc/raspi4b/rpi4b-test.wic /mnt/p2
  mkdir -p /mnt/p2/home/root/hosttest
  cp -f /workdir/poc/raspi4b/testfiles/* /mnt/p2/home/root/hosttest/ 2>/dev/null || true
  chmod +x /mnt/p2/home/root/hosttest/*.sh 2>/dev/null || true
  rm -f /mnt/p2/home/root/hosttest/result.txt
  sync && umount /mnt/p2 && echo '  주입 완료'"

echo "[3/4] raspi4b 부팅 + 테스트 실행 (BCM2711 SoC, 수 분 소요)"
docker rm -f raspi4b-poc 2>/dev/null || true
docker run --rm --name raspi4b-poc --security-opt seccomp=unconfined \
  -v "$BASE":/workdir -w /workdir "$RUNNER" \
  expect -f /workdir/poc/raspi4b/drive.expect | tail -6 || true

echo "[4/4] 결과 회수 (rootfs → result.txt)"
docker run --rm --privileged -v "$BASE":/workdir "$RUNNER" bash -c "
  mkdir -p /mnt/p2 && mount -o loop,offset=$OFF /workdir/poc/raspi4b/rpi4b-test.wic /mnt/p2
  cp -f /mnt/p2/home/root/hosttest/result.txt /workdir/poc/raspi4b/result.txt 2>/dev/null || echo '(result.txt 없음)'
  umount /mnt/p2" >/dev/null

echo
echo "===== raspi4b(T3) 테스트 결과 ====="
cat "$BASE/poc/raspi4b/result.txt" 2>/dev/null || echo "(결과 없음 — 부팅 로그 확인 필요)"
