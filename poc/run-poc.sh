#!/bin/bash
# 호스트에서 실행: QEMU로 보드 rootfs 부팅 → 자동테스트 → 결과 회수 (컨테이너 안에서 qemu+expect 구동)
# 사용법: bash poc/run-poc.sh
set -e
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMG=qemu-runner:latest   # expect와 런타임 라이브러리가 든 이미지(QEMU는 qemu-install/을 마운트)
docker rm -f poc-run 2>/dev/null || true
rm -f "$BASE/poc/testshare/result.txt"

# expect가 이미지에 없으면 설치 후 커밋(1회성)
if ! docker run --rm $IMG bash -c "command -v expect" >/dev/null 2>&1; then
  echo "[준비] 러너 이미지에 expect 설치 중..."
  cid=$(docker run -d --user 0 $IMG bash -c "apt-get update -qq && apt-get install -y -qq expect >/dev/null && echo done")
  docker wait "$cid" >/dev/null
  docker commit "$cid" $IMG >/dev/null
  docker rm "$cid" >/dev/null
  echo "[준비] 완료"
fi

echo "[실행] QEMU 부팅 + 자동테스트..."
docker run --rm --name poc-run --security-opt seccomp=unconfined \
  -v "$BASE":/workdir -w /workdir \
  $IMG expect -f /workdir/poc/drive.expect

echo
echo "===== 회수된 테스트 결과 (poc/testshare/result.txt) ====="
cat "$BASE/poc/testshare/result.txt" 2>/dev/null || echo "(결과 파일 없음 — 부팅/테스트 로그 확인 필요)"
