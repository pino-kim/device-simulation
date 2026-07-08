#!/bin/bash
# 커널만 재빌드 — virtio/9p built-in 추가본 (crops 컨테이너 내부에서 실행)
set -e
exec > >(tee -a /workdir/kernel-virtio.log) 2>&1
export LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8
echo "===== KERNEL(virtio) REBUILD START ($(date)) ====="
cd /workdir
source sources/poky/oe-init-build-env build

echo "=== bbappend 인식 확인 ==="
bitbake-layers show-appends 2>/dev/null | grep -A2 linux-raspberrypi || echo "(show-appends에 안 보이면 아래 config 결과로 확인)"

echo "=== 커널 재설정+재빌드 (cleansstate 후) ==="
bitbake -c cleansstate virtual/kernel
bitbake virtual/kernel

echo "=== 새 커널의 virtio 설정 검증 ==="
CFG=$(find tmp/work -path "*linux-raspberrypi*" -name ".config" | head -1)
grep -E "CONFIG_VIRTIO_BLK|CONFIG_VIRTIO_PCI|CONFIG_PCI_HOST_GENERIC|CONFIG_9P_FS|CONFIG_VIRTIO_NET" "$CFG"

echo "=== 새 Image 배포 확인 ==="
ls -l tmp/deploy/images/raspberrypi4-64/Image-raspberrypi4-64.bin
echo "===== KERNEL(virtio) REBUILD DONE ($(date)) ====="
