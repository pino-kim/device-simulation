# Device Simulation 검수 보고서

## 1. 검수 기준

- 검수일: 2026-07-31
- 작업 디렉터리: `/home/sw.kim/workspace/device-simulation`
- Yocto 환경 커밋: `7d7f69e Yocto kirkstone RPi4 빌드 환경 추가`
- QEMU 검증 커밋: `8e713c1 QEMU 8.2 virt 부팅 절차 검증`
- 대상 이미지: `core-image-base`
- 대상 머신: `raspberrypi4-64`
- QEMU 머신: `virt-8.2`

## 2. 종합 판정

현재 환경은 다음 범위에서 검수 통과했다.

1. 고정된 Yocto kirkstone 소스를 내려받을 수 있다.
2. RPi4용 `core-image-base`와 WIC 이미지를 빌드할 수 있다.
3. RPi4 커널에 QEMU `virt` 부팅용 virtio, generic PCI 및 9p 기능이
   built-in으로 적용된다.
4. QEMU 8.2.0을 소스에서 빌드해 프로젝트의 `qemu-install/`에 설치할
   수 있다.
5. `qemu-runner:latest`에 프로젝트의 QEMU 설치 디렉터리를 연결해
   `qemu-system-aarch64`를 실행할 수 있다.
6. `rpi4.wic`의 두 번째 파티션을 `/dev/vda2` 루트 파일시스템으로
   실제 부팅할 수 있다.
7. `ttyAMA0`에서 root 로그인, 9p 공유 마운트, 게스트 테스트 실행,
   결과 회수 및 정상 종료까지 자동화할 수 있다.

현재 PASS는 인프라 smoke test에 대한 판정이다. 실제 애플리케이션
`myapp`은 배치되지 않았으므로 애플리케이션 self-test까지 통과한 것은
아니다.

## 3. Yocto 소스 검수

`bootstrap-yocto.sh`가 사용하는 소스는 다음 커밋으로 고정돼 있다.

| 구성 요소 | 브랜치 | 커밋 |
|---|---|---|
| poky | kirkstone | `393064579dfdd0ed2d4ed4c27d238d7d2292c08b` |
| meta-raspberrypi | kirkstone | `255500dd9f6a01a3445ac491d1abc401801e3bad` |
| meta-openembedded | kirkstone | `ce8539c941f6fcbecaca4d16640ac105c0595589` |

소스는 `sources/` 아래에 배치되며 대용량 소스와 빌드 산출물은 Git에서
제외된다.

## 4. Yocto 빌드 검수

빌드 컨테이너는 `crops/yocto:ubuntu-22.04-base`를 사용한다.
호스트 프로젝트는 컨테이너의 `/workdir`로 연결되며, 오래된 Docker
seccomp 제약을 피하기 위해 `--security-opt seccomp=unconfined`을
사용한다.

실제 전체 빌드 결과:

```text
4014 / 4014 tasks succeeded
```

동일한 설정으로 두 번째 빌드를 수행했을 때 전체 작업이 캐시에서
재사용되는 것도 확인했다.

```text
100% cached
```

주요 산출물 위치:

```text
build/tmp/deploy/images/raspberrypi4-64/
├── Image-raspberrypi4-64.bin
├── bcm2711-rpi-4-b.dtb
├── core-image-base-raspberrypi4-64.wic.bz2
└── core-image-base-raspberrypi4-64.wic.gz
```

## 5. 커널 설정 검수

`meta-device-simulation` 레이어를 통해 다음 기능을 커널 built-in으로
적용했다.

```text
CONFIG_VIRTIO=y
CONFIG_VIRTIO_MENU=y
CONFIG_VIRTIO_PCI=y
CONFIG_VIRTIO_PCI_LEGACY=y
CONFIG_VIRTIO_MMIO=y
CONFIG_VIRTIO_BLK=y
CONFIG_VIRTIO_NET=y
CONFIG_VIRTIO_CONSOLE=y
CONFIG_PCI_HOST_GENERIC=y
CONFIG_NET_9P=y
CONFIG_NET_9P_VIRTIO=y
CONFIG_9P_FS=y
```

루트 디스크가 virtio block으로 연결되므로 `CONFIG_VIRTIO_BLK`와 관련
PCI 기능은 모듈이 아닌 built-in이어야 한다. 빌드 후 최종 커널
`.config`에서 관련 설정이 `=y`로 반영된 것을 확인했다.

실제 부팅에서도 다음 기능이 동작했다.

```text
pci-host-generic ... PCI host bridge
virtio_blk virtio1: [vda]
vda: vda1 vda2
9p: Installing v9fs 9p2000 file system support
9pnet: Installing 9P2000 support
```

## 6. WIC 이미지 검수

`prepare-image.sh`는 빌드된 `.wic.gz` 파일을 프로젝트 루트의
`rpi4.wic`으로 안전하게 압축 해제한다. 임시 파일을 사용하므로 압축
해제 중 실패한 파일이 최종 이미지로 남지 않는다.

확인한 이미지 크기와 파티션:

```text
rpi4.wic: 약 274 MiB
```

| 파티션 | 시작 섹터 | 종류 및 용도 |
|---|---:|---|
| 1 | 8192 | FAT32 부트 파티션 |
| 2 | 155648 | Linux rootfs |

QEMU에서는 파티션 2를 `root=/dev/vda2`로 사용했다.

## 7. QEMU 빌드 검수

`build-qemu.sh`로 QEMU 8.2.0 소스를 받아 `aarch64-softmmu` 타깃을
빌드했다.

```text
2919 / 2919 build steps completed
QEMU emulator version 8.2.0
```

설치 위치:

```text
qemu-install/bin/qemu-system-aarch64
```

머신 목록에서 다음 지원을 확인했다.

```text
virt       QEMU 8.2 ARM Virtual Machine (alias of virt-8.2)
virt-8.2   QEMU 8.2 ARM Virtual Machine
```

기존 빌드 스크립트가 `raspi4b` 지원을 확인한다고 잘못 설명하던 부분은
실제 사용 대상인 `virt` 머신 지원 확인으로 수정했다. Upstream QEMU
8.2에는 `raspi4b` 머신이 없다.

## 8. qemu-runner 구조 검수

`qemu-runner:latest`에는 Expect와 QEMU 실행용 런타임 라이브러리가
있지만 QEMU 실행 파일은 없다. QEMU 실행 파일은 프로젝트의
`qemu-install/`을 컨테이너에 연결해 사용한다.

```text
호스트 qemu-install/
        │
        └── /workdir/qemu-install/로 볼륨 연결
                    │
                    └── qemu-runner:latest에서 실행
```

기본 Docker seccomp 프로필에서는 다음 오류가 재현됐다.

```text
qemu: qemu_thread_create: Operation not permitted
```

기존 스크립트와 동일하게 `--security-opt seccomp=unconfined`을
적용하면 정상 실행됐다.

## 9. 실제 QEMU 부팅 명령 검수

실제 명령은 `poc/drive.expect`에 정의돼 있다.

```text
qemu-system-aarch64
  -M virt
  -cpu cortex-a72
  -m 2048
  -smp 4
  -nographic
  -no-reboot
  -kernel Image-raspberrypi4-64.bin
  -append "root=/dev/vda2 rootwait rw console=ttyAMA0 earlycon=pl011,0x9000000"
  -drive file=rpi4.wic,format=raw,if=none,id=hd0
  -device virtio-blk-pci,drive=hd0
  -fsdev local,id=fs0,path=poc/testshare,security_model=none
  -device virtio-9p-pci,fsdev=fs0,mount_tag=hostshare
```

검증 결과:

| 항목 | 결과 |
|---|---|
| QEMU `virt` 머신 시작 | 통과 |
| Cortex-A72 CPU 4개 활성화 | 통과 |
| 2 GiB 메모리 인식 | 통과 |
| PL011 `ttyAMA0` 콘솔 | 통과 |
| virtio block 디스크 인식 | 통과 |
| `/dev/vda2` ext4 rootfs 마운트 | 통과 |
| init 및 Yocto 사용자 공간 시작 | 통과 |
| root 자동 로그인 | 통과 |
| virtio 9p 공유 마운트 | 통과 |
| 게스트 테스트 실행 | 통과 |
| 결과 파일 호스트 회수 | 통과 |
| poweroff 및 QEMU 종료 | 통과 |

## 10. 실제 부팅 증적

커널 및 아키텍처:

```text
Linux version 5.15.92-v8
Machine model: linux,dummy-virt
SMP: Total of 4 processors activated
```

디스크와 루트 파일시스템:

```text
virtio_blk virtio1: [vda] 560332 512-byte logical blocks
vda: vda1 vda2
EXT4-fs (vda2): mounted filesystem
VFS: Mounted root (ext4 filesystem) on device 254:2
```

로그인:

```text
Poky (Yocto Project Reference Distro) 4.0.35
raspberrypi4-64 /dev/ttyAMA0
raspberrypi4-64 login: root
root@raspberrypi4-64:~#
```

9p와 테스트:

```text
MOUNT_OK
TESTS_DONE
RESULT_OK: PoC done -> poc/testshare/result.txt
```

종료:

```text
The system is going down for system halt NOW!
reboot: Power down
```

## 11. 게스트 테스트 결과

회수된 결과:

```text
=== 게스트 자동테스트 시작 ===
uname : Linux raspberrypi4-64 5.15.92-v8 ... aarch64 GNU/Linux
arch  : aarch64
distro:

(myapp 없음 — testshare/에 바이너리를 두면 여기서 실행됩니다)

PASS: 샘플 테스트 통과
=== 게스트 자동테스트 종료 ===
```

이를 통해 ARM64 게스트 셸 실행, 9p 읽기, 테스트 실행 및 9p 쓰기를
확인했다. `myapp`은 존재하지 않았기 때문에 실제 애플리케이션 실행은
검증하지 않았다.

## 12. 적용한 재현성 개선

- `/data/yocto-rpi4` 절대경로를 제거했다.
- `poc/run-poc.sh`가 자신의 위치를 기준으로 프로젝트 루트를 계산한다.
- `qemu-runner:latest`와 `qemu-install/`의 역할을 정확히 문서화했다.
- QEMU 빌드 후 `raspi4b`가 아닌 `virt` 머신 지원을 확인하도록 수정했다.
- README에 QEMU 빌드, 버전 확인, 머신 확인 및 PoC 실행 명령을 추가했다.

## 13. 검수 결론

현재 프로젝트는 다음 목적으로 사용할 수 있다.

> RPi4용 Yocto ARM64 rootfs와 사용자 공간을 QEMU 8.2 `virt` 머신에서
> 부팅하고, 9p를 이용해 이미지 재빌드 없이 테스트 파일 또는
> 애플리케이션을 교체해 실행하는 자동 테스트 PoC.

이 결과는 RPi4 실제 SoC 전체를 에뮬레이션했다는 의미가 아니다.
GPIO, 카메라, GPU, Raspberry Pi 펌웨어 및 기타 BCM2711 전용 장치
테스트는 실제 보드 또는 별도의 SoC 에뮬레이션 환경이 필요하다.
