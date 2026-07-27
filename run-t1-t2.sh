#!/usr/bin/env bash
# QEMU virt 머신에서 유저스페이스/범용 커널 테스트를 실행한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

require_command python3
[[ -x "$QEMU_BIN" ]] || die "먼저 ./build-qemu.sh를 실행하십시오."
python3 -c 'import pexpect' 2>/dev/null || die "Python pexpect 패키지가 필요합니다."

KERNEL="${KERNEL:-$(find_single_artifact 'Image-raspberrypi4-64.bin')}"
WIC="${WIC:-$(find_single_artifact 'core-image-base-raspberrypi4-64*.wic')}"
SHARE="$PROJECT_ROOT/poc/testshare"
RESULT="$SHARE/result.txt"
LOG="$PROJECT_ROOT/poc/t1-t2-boot.log"

rm -f "$RESULT"
python3 "$PROJECT_ROOT/scripts/qemu_expect.py" \
    --mode virt --qemu "$QEMU_BIN" --kernel "$KERNEL" --disk "$WIC" \
    --share "$SHARE" --log "$LOG"

echo "===== T1/T2 result ====="
cat "$RESULT"
