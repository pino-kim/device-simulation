#!/usr/bin/env bash
# QEMU raspi4b 머신에서 BCM2711 SoC 수준 테스트를 실행한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

for command in python3 sfdisk dd debugfs; do
    require_command "$command"
done
[[ -x "$QEMU_BIN" ]] || die "먼저 ./build-qemu.sh를 실행하십시오."
python3 -c 'import pexpect' 2>/dev/null || die "Python pexpect 패키지가 필요합니다."

KERNEL="${KERNEL:-$(find_single_artifact 'Image-raspberrypi4-64.bin')}"
DTB="${DTB:-$(find_single_artifact 'bcm2711-rpi-4-b.dtb')}"
SOURCE_WIC="${WIC:-$(find_single_artifact 'core-image-base-raspberrypi4-64*.wic')}"
TEST_DIR="$PROJECT_ROOT/poc/raspi4b/testfiles"
TEST_WIC="$PROJECT_ROOT/poc/raspi4b/rpi4b-test.wic"
RESULT="$PROJECT_ROOT/poc/raspi4b/result.txt"
LOG="$PROJECT_ROOT/poc/raspi4b/t3-boot.log"
ROOTFS_IMAGE="$(mktemp)"

cleanup() {
    rm -f "$ROOTFS_IMAGE"
}
trap cleanup EXIT

read -r ROOT_START ROOT_SIZE < <(
    sfdisk --json "$SOURCE_WIC" |
        python3 -c '
import json, sys
parts = json.load(sys.stdin)["partitiontable"]["partitions"]
if len(parts) < 2:
    raise SystemExit("WIC의 두 번째 파티션을 찾을 수 없습니다.")
print(parts[1]["start"], parts[1]["size"])
'
)

echo "[1/4] 테스트용 SD 이미지 준비"
cp --reflink=auto "$SOURCE_WIC" "$TEST_WIC"
size="$(stat -c %s "$TEST_WIC")"
power=1
while (( power < size )); do power=$((power * 2)); done
truncate -s "$power" "$TEST_WIC"

echo "[2/4] rootfs 파티션에 테스트 파일 주입"
dd if="$TEST_WIC" of="$ROOTFS_IMAGE" bs=512 skip="$ROOT_START" \
    count="$ROOT_SIZE" status=none
debugfs -w -R "mkdir /root/hosttest" "$ROOTFS_IMAGE" >/dev/null 2>&1 || true
for test_file in "$TEST_DIR"/*; do
    [[ -f "$test_file" ]] || continue
    guest_file="/root/hosttest/$(basename "$test_file")"
    debugfs -w -R "rm $guest_file" "$ROOTFS_IMAGE" >/dev/null 2>&1 || true
    debugfs -w -R "write $test_file $guest_file" "$ROOTFS_IMAGE" >/dev/null
done
debugfs -w -R "set_inode_field /root/hosttest/run-tests.sh mode 0100755" \
    "$ROOTFS_IMAGE" >/dev/null
debugfs -w -R "set_inode_field /root/hosttest/codex-init.sh mode 0100755" \
    "$ROOTFS_IMAGE" >/dev/null
debugfs -w -R "rm /root/hosttest/result.txt" \
    "$ROOTFS_IMAGE" >/dev/null 2>&1 || true
dd if="$ROOTFS_IMAGE" of="$TEST_WIC" bs=512 seek="$ROOT_START" \
    conv=notrunc status=none

echo "[3/4] raspi4b 부팅 및 게스트 테스트"
python3 "$PROJECT_ROOT/scripts/qemu_expect.py" \
    --mode raspi4b --qemu "$QEMU_BIN" --kernel "$KERNEL" --dtb "$DTB" \
    --disk "$TEST_WIC" --log "$LOG"

echo "[4/4] 테스트 결과 회수"
dd if="$TEST_WIC" of="$ROOTFS_IMAGE" bs=512 skip="$ROOT_START" \
    count="$ROOT_SIZE" status=none
debugfs -R "dump /root/hosttest/result.txt $RESULT" \
    "$ROOTFS_IMAGE" >/dev/null

echo "===== T3 result ====="
cat "$RESULT"
grep -q '^PASS: T3 raspi4b 테스트 통과$' "$RESULT" ||
    die "T3 게스트 테스트가 통과하지 못했습니다."
