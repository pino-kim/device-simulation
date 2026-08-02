#!/bin/bash
# 호스트에서 실행: QEMU로 보드 rootfs 부팅 → 자동테스트 → 결과 회수 (컨테이너 안에서 qemu+expect 구동)
# 사용법: bash poc/run-poc.sh
set -euo pipefail
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMG=${TEST_CONTAINER_IMAGE:-device-simulation-test:latest}

if ! docker inspect "$IMG" >/dev/null 2>&1; then
  echo "[준비] 테스트 러너 이미지 빌드 중..."
  TEST_CONTAINER_IMAGE="$IMG" "$BASE/build-test-image.sh"
fi

docker rm -f poc-run 2>/dev/null || true
rm -f "$BASE/poc/testshare/result.txt"

echo "[실행] QEMU 부팅 + 자동테스트..."
docker run --rm --name poc-run --security-opt seccomp=unconfined \
  -v "$BASE":/workdir -w /workdir \
  "$IMG" expect -f /workdir/poc/drive.expect

echo
echo "===== 회수된 테스트 결과 (poc/testshare/result.txt) ====="
cat "$BASE/poc/testshare/result.txt" 2>/dev/null || echo "(결과 파일 없음 — 부팅/테스트 로그 확인 필요)"
