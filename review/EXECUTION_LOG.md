# 실제 검수 명령 전체 기록

## 1. 실행 기준

아래 명령은 다음 프로젝트 경로에서 실제 검수에 사용했다.

```text
/home/sw.kim/workspace/device-simulation
```

먼저 프로젝트 루트로 이동한다.

```bash
cd /home/sw.kim/workspace/device-simulation
```

다른 경로에 프로젝트를 복제한 경우에는 위 경로만 실제 프로젝트
경로로 바꾼다. `$PWD`를 사용하는 명령은 반드시 프로젝트 루트에서
실행한다.

## 2. Git 초기 상태 확인

```bash
git status --short
git log --oneline -3
```

`git status --short`가 아무것도 출력하지 않으면 작업 트리가 깨끗한
상태다.

검수 기준 커밋:

```text
8e713c1 QEMU 8.2 virt 부팅 절차 검증
7d7f69e Yocto kirkstone RPi4 빌드 환경 추가
```

## 3. Yocto 소스 준비

실제 사용 명령:

```bash
./bootstrap-yocto.sh
```

동일 작업을 명시적으로 실행하려면:

```bash
bash bootstrap-yocto.sh
```

소스 커밋 확인:

```bash
git -C sources/poky rev-parse HEAD
git -C sources/meta-raspberrypi rev-parse HEAD
git -C sources/meta-openembedded rev-parse HEAD
```

기대 결과:

```text
393064579dfdd0ed2d4ed4c27d238d7d2292c08b
255500dd9f6a01a3445ac491d1abc401801e3bad
ce8539c941f6fcbecaca4d16640ac105c0595589
```

## 4. Yocto RPi4 이미지 빌드

실제 사용 명령:

```bash
./build-yocto.sh
```

`build-yocto.sh`가 내부적으로 실행하는 Docker 명령과 동등한 명령:

```bash
docker run --rm \
  --security-opt seccomp=unconfined \
  --user "$(id -u):$(id -g)" \
  -e HOME=/tmp/yocto-home \
  -v "$PWD":/workdir \
  -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash -c 'mkdir -p "$HOME" && exec bash /workdir/run-build.sh'
```

최초 빌드에서 확인한 결과:

```text
4014 / 4014 tasks succeeded
```

캐시 재사용 검증을 위해 같은 명령을 한 번 더 실행했다.

```bash
./build-yocto.sh
```

두 번째 빌드에서는 전체 작업이 캐시에서 재사용되는 것을 확인했다.

```text
100% cached
```

## 5. Yocto 산출물 확인

```bash
ls -lh build/tmp/deploy/images/raspberrypi4-64/
```

주요 파일만 확인:

```bash
ls -lh \
  build/tmp/deploy/images/raspberrypi4-64/Image-raspberrypi4-64.bin \
  build/tmp/deploy/images/raspberrypi4-64/bcm2711-rpi-4-b.dtb \
  build/tmp/deploy/images/raspberrypi4-64/core-image-base-raspberrypi4-64.wic.bz2 \
  build/tmp/deploy/images/raspberrypi4-64/core-image-base-raspberrypi4-64.wic.gz
```

## 6. 최종 커널 설정 확인

Yocto 빌드 트리에서 최종 커널 `.config`를 확인한다.

```bash
ls -l build/tmp/work-shared/raspberrypi4-64/kernel-build-artifacts/.config
```

해당 `.config`에서 다음 옵션을 확인한다.

```bash
grep -E \
  '^(CONFIG_VIRTIO=|CONFIG_VIRTIO_PCI=|CONFIG_VIRTIO_BLK=|CONFIG_PCI_HOST_GENERIC=|CONFIG_NET_9P=|CONFIG_NET_9P_VIRTIO=|CONFIG_9P_FS=)' \
  build/tmp/work-shared/raspberrypi4-64/kernel-build-artifacts/.config
```

모든 커널 `.config` 후보를 다시 찾으려면 다음 명령을 사용한다.

```bash
find build/tmp/work-shared build/tmp/work \
  -path '*linux*' -name .config -type f -print
```

기대값:

```text
CONFIG_VIRTIO=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_BLK=y
CONFIG_PCI_HOST_GENERIC=y
CONFIG_NET_9P=y
CONFIG_NET_9P_VIRTIO=y
CONFIG_9P_FS=y
```

## 7. QEMU용 WIC 이미지 준비

```bash
./prepare-image.sh
```

생성 결과 확인:

```bash
ls -lh rpi4.wic
fdisk -l rpi4.wic
```

검수 당시 확인한 값:

```text
rpi4.wic: 약 274 MiB
partition 1 start: 8192
partition 2 start: 155648
```

## 8. QEMU 8.2 빌드

실제로 사용한 전체 명령:

```bash
docker run --rm \
  --user 0 \
  --security-opt seccomp=unconfined \
  -v /home/sw.kim/workspace/device-simulation:/workdir \
  -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh
```

다른 프로젝트 경로에서 재현할 때 사용할 명령:

```bash
docker run --rm \
  --user 0 \
  --security-opt seccomp=unconfined \
  -v "$PWD":/workdir \
  -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh
```

확인한 빌드 결과:

```text
2919 / 2919
QEMU emulator version 8.2.0
```

## 9. qemu-runner 내부 QEMU 8.2 실행 확인

처음 보안 옵션 없이 실행한 명령:

```bash
docker run --rm \
  -v /home/sw.kim/workspace/device-simulation:/workdir \
  qemu-runner:latest \
  /workdir/qemu-install/bin/qemu-system-aarch64 --version
```

이 호스트에서는 다음 오류가 발생했다.

```text
qemu: qemu_thread_create: Operation not permitted
```

프로젝트에서 사용하는 seccomp 조건을 적용한 정상 확인 명령:

```bash
docker run --rm \
  --security-opt seccomp=unconfined \
  -v /home/sw.kim/workspace/device-simulation:/workdir \
  qemu-runner:latest \
  /workdir/qemu-install/bin/qemu-system-aarch64 --version
```

기대 결과:

```text
QEMU emulator version 8.2.0
```

`virt` 머신 지원 확인:

```bash
docker run --rm \
  --security-opt seccomp=unconfined \
  -v /home/sw.kim/workspace/device-simulation:/workdir \
  qemu-runner:latest \
  /workdir/qemu-install/bin/qemu-system-aarch64 -machine help
```

확인한 항목:

```text
virt       QEMU 8.2 ARM Virtual Machine (alias of virt-8.2)
virt-8.2   QEMU 8.2 ARM Virtual Machine
```

## 10. QEMU 8.2 virt 실제 부팅

하니스 실행 전에 입력 파일을 확인했다.

```bash
ls -lh \
  rpi4.wic \
  build/tmp/deploy/images/raspberrypi4-64/Image-raspberrypi4-64.bin \
  qemu-install/bin/qemu-system-aarch64 \
  poc/testshare/run-tests.sh
```

실제 자동 부팅 명령:

```bash
bash poc/run-poc.sh
```

하니스가 실행한 핵심 QEMU 명령:

```bash
/workdir/qemu-install/bin/qemu-system-aarch64 \
  -M virt \
  -cpu cortex-a72 \
  -m 2048 \
  -smp 4 \
  -nographic \
  -no-reboot \
  -kernel /workdir/build/tmp/deploy/images/raspberrypi4-64/Image-raspberrypi4-64.bin \
  -append "root=/dev/vda2 rootwait rw console=ttyAMA0 earlycon=pl011,0x9000000" \
  -drive file=/workdir/rpi4.wic,format=raw,if=none,id=hd0 \
  -device virtio-blk-pci,drive=hd0 \
  -fsdev local,id=fs0,path=/workdir/poc/testshare,security_model=none \
  -device virtio-9p-pci,fsdev=fs0,mount_tag=hostshare
```

확인한 최종 결과:

```text
MOUNT_OK
TESTS_DONE
RESULT_OK: PoC done -> poc/testshare/result.txt
```

결과 확인:

```bash
cat poc/testshare/result.txt
```

## 11. QEMU 9.2 빌드

실제로 사용한 전체 명령:

```bash
docker run --rm \
  --user 0 \
  --security-opt seccomp=unconfined \
  -v /home/sw.kim/workspace/device-simulation:/workdir \
  -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu92.sh
```

경로 독립적인 재현 명령:

```bash
docker run --rm \
  --user 0 \
  --security-opt seccomp=unconfined \
  -v "$PWD":/workdir \
  -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu92.sh
```

확인한 구성과 빌드 결과:

```text
Run-time dependency slirp found: YES 4.6.1
2964 / 2964 build steps completed
QEMU emulator version 9.2.0
raspi4b  Raspberry Pi 4B (revision 1.5)
```

## 12. qemu-runner 내부 QEMU 9.2 확인

버전 확인:

```bash
docker run --rm \
  --security-opt seccomp=unconfined \
  -v /home/sw.kim/workspace/device-simulation:/workdir \
  qemu-runner:latest \
  /workdir/qemu92-install/bin/qemu-system-aarch64 --version
```

raspi4b 머신 확인:

```bash
docker run --rm \
  --security-opt seccomp=unconfined \
  -v /home/sw.kim/workspace/device-simulation:/workdir \
  qemu-runner:latest \
  /workdir/qemu92-install/bin/qemu-system-aarch64 -machine help \
  | grep -E '^raspi4b '
```

기대 결과:

```text
QEMU emulator version 9.2.0
raspi4b  Raspberry Pi 4B (revision 1.5)
```

## 13. QEMU 9.2 raspi4b 실제 부팅

실제 사용 명령:

```bash
bash poc/raspi4b/run-poc-raspi4b.sh
```

하니스가 수행하는 SD 준비:

```bash
cp -f rpi4.wic poc/raspi4b/rpi4b-test.wic
truncate -s 512M poc/raspi4b/rpi4b-test.wic
```

하니스가 컨테이너 안에서 수행하는 rootfs 주입 절차:

```bash
mkdir -p /mnt/p2
mount -o loop,offset=79691776 \
  /workdir/poc/raspi4b/rpi4b-test.wic /mnt/p2
mkdir -p /mnt/p2/home/root/hosttest
cp -f /workdir/poc/raspi4b/testfiles/* \
  /mnt/p2/home/root/hosttest/
chmod +x /mnt/p2/home/root/hosttest/*.sh
rm -f /mnt/p2/home/root/hosttest/result.txt
sync
umount /mnt/p2
```

하니스가 실행한 핵심 QEMU 명령:

```bash
/workdir/qemu92-install/bin/qemu-system-aarch64 \
  -M raspi4b \
  -cpu cortex-a72 \
  -m 2G \
  -nographic \
  -no-reboot \
  -kernel /workdir/build/tmp/deploy/images/raspberrypi4-64/Image-raspberrypi4-64.bin \
  -dtb /workdir/build/tmp/deploy/images/raspberrypi4-64/bcm2711-rpi-4-b.dtb \
  -drive file=/workdir/poc/raspi4b/rpi4b-test.wic,format=raw,if=sd \
  -append "console=ttyAMA0,115200 earlycon=pl011,0xfe201000 root=/dev/mmcblk1p2 rootwait rw"
```

확인한 최종 결과:

```text
machine : Raspberry Pi 4 Model B
/dev/mmcblk1 /dev/mmcblk1p1 /dev/mmcblk1p2
RESULT_OK: raspi4b PoC done
PASS: T3 raspi4b 테스트 통과
```

결과 확인:

```bash
cat poc/raspi4b/result.txt
```

## 14. 셸 및 Git 검사

검수에 사용한 구문 검사:

```bash
bash -n \
  bootstrap-yocto.sh \
  build-yocto.sh \
  build-qemu.sh \
  build-qemu92.sh \
  prepare-image.sh \
  poc/run-poc.sh \
  poc/testshare/run-tests.sh \
  poc/raspi4b/run-poc-raspi4b.sh \
  poc/raspi4b/testfiles/run-tests.sh
```

diff 공백 오류 검사:

```bash
git diff --check
```

작업 트리 확인:

```bash
git status --short
```

대용량 산출물이 Git에서 제외되는지 확인:

```bash
git check-ignore -v \
  qemu-install/bin/qemu-system-aarch64 \
  qemu92-install/bin/qemu-system-aarch64 \
  qemu-8.2.0 \
  qemu-9.2.0 \
  qemu-8.2.0.tar.xz \
  qemu-9.2.0.tar.xz \
  rpi4.wic \
  poc/raspi4b/rpi4b-test.wic \
  poc/testshare/result.txt \
  poc/raspi4b/result.txt \
  qemu-build.log \
  qemu92-build.log
```

## 15. 재현 시 권장 실행 순서

완전히 준비된 현재 작업 공간에서는 다음 두 명령만으로 각각 다시
검증할 수 있다.

```bash
bash poc/run-poc.sh
bash poc/raspi4b/run-poc-raspi4b.sh
```

빈 작업 공간에서 전체를 재현할 때는 다음 순서를 사용한다.

```bash
./bootstrap-yocto.sh
./build-yocto.sh
./prepare-image.sh

docker run --rm --user 0 --security-opt seccomp=unconfined \
  -v "$PWD":/workdir -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh

bash poc/run-poc.sh

docker run --rm --user 0 --security-opt seccomp=unconfined \
  -v "$PWD":/workdir -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu92.sh

bash poc/raspi4b/run-poc-raspi4b.sh
```
