#!/usr/bin/env bash
# QEMU raspi4b 머신에서 BCM2711 SoC 수준 테스트를 실행한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

for command in python3 sudo losetup lsblk mountpoint; do
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
MOUNT_DIR="$(mktemp -d)"
LOOP_DEVICE=""

cleanup() {
    if mountpoint -q "$MOUNT_DIR"; then sudo umount "$MOUNT_DIR"; fi
    if [[ -n "$LOOP_DEVICE" ]]; then sudo losetup --detach "$LOOP_DEVICE"; fi
    rmdir "$MOUNT_DIR"
}
trap cleanup EXIT

echo "[1/4] 테스트용 SD 이미지 준비"
cp --reflink=auto "$SOURCE_WIC" "$TEST_WIC"
size="$(stat -c %s "$TEST_WIC")"
power=1
while (( power < size )); do power=$((power * 2)); done
truncate -s "$power" "$TEST_WIC"

echo "[2/4] rootfs 파티션에 테스트 파일 주입"
LOOP_DEVICE="$(sudo losetup --find --show --partscan "$TEST_WIC")"
ROOT_PARTITION="$(lsblk -lnpo NAME,TYPE "$LOOP_DEVICE" |
    awk '$2 == "part" {parts[++count]=$1} END {if (count >= 2) print parts[2]}')"
[[ -n "$ROOT_PARTITION" ]] || die "WIC의 두 번째 파티션을 찾을 수 없습니다."
sudo mount "$ROOT_PARTITION" "$MOUNT_DIR"
sudo install -d "$MOUNT_DIR/home/root/hosttest"
sudo cp -a "$TEST_DIR/." "$MOUNT_DIR/home/root/hosttest/"
sudo chmod +x "$MOUNT_DIR/home/root/hosttest/run-tests.sh"
sudo rm -f "$MOUNT_DIR/home/root/hosttest/result.txt"
sudo umount "$MOUNT_DIR"
sudo losetup --detach "$LOOP_DEVICE"
LOOP_DEVICE=""

echo "[3/4] raspi4b 부팅 및 게스트 테스트"
python3 "$PROJECT_ROOT/scripts/qemu_expect.py" \
    --mode raspi4b --qemu "$QEMU_BIN" --kernel "$KERNEL" --dtb "$DTB" \
    --disk "$TEST_WIC" --log "$LOG"

echo "[4/4] 테스트 결과 회수"
LOOP_DEVICE="$(sudo losetup --find --show --partscan "$TEST_WIC")"
ROOT_PARTITION="$(lsblk -lnpo NAME,TYPE "$LOOP_DEVICE" |
    awk '$2 == "part" {parts[++count]=$1} END {if (count >= 2) print parts[2]}')"
sudo mount "$ROOT_PARTITION" "$MOUNT_DIR"
sudo cp "$MOUNT_DIR/home/root/hosttest/result.txt" "$RESULT"
sudo chown "$(id -u):$(id -g)" "$RESULT"
sudo umount "$MOUNT_DIR"
sudo losetup --detach "$LOOP_DEVICE"
LOOP_DEVICE=""

echo "===== T3 result ====="
cat "$RESULT"
