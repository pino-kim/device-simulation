# Raspberry Pi 4 Yocto Wrynose + QEMU PoC

Yocto Project Wrynose 6.0.2로 Raspberry Pi 4용 `core-image-base`를 만들고,
공식 QEMU 11.0.3의 `raspi4b` 머신으로 부팅을 검증하는 환경이다. Yocto와
QEMU 빌드는 Ubuntu 22.04 컨테이너에서 수행하므로 호스트에 빌드 도구를
직접 설치할 필요가 없다.

## 현재 기준

- Yocto: Wrynose 6.0.2 공식 릴리스 아카이브
- BitBake: 2.18.0
- OE-Core: 공식 6.0.2 릴리스 아카이브
- meta-raspberrypi: `wrynose`
- 머신: `raspberrypi4-64`
- 이미지: `core-image-base`
- Linux: 6.18.33
- QEMU: 11.0.3, `raspi4b` revision 1.5
- 실물 DTB: 원본 `bcm2711-rpi-4-b.dtb`
- QEMU DTB: 별도 생성한 `bcm2711-rpi-4-b-qemu-console.dtb`

`meta-device-simulation`은 실물용 DTB를 그대로 보존한다. QEMU용 DTB만
PL011을 `serial0`으로 지정하고 그 하위 Bluetooth 노드를 비활성화한다.
WIC의 `/boot` 항목은 장치 번호 대신 FAT filesystem UUID를 사용한다.

## 전체 빌드 순서

### 1. Wrynose 소스 준비

```sh
./bootstrap-yocto.sh
```

공식 6.0.2 BitBake, OE-Core, meta-yocto 아카이브를 다운로드하고 SHA-256을
검증한다. OE-Core와 BitBake는 `sources/oe-core`, meta-yocto는
`sources/meta-yocto`에 풀며 meta-raspberrypi `wrynose` 브랜치를
`sources/meta-raspberrypi`에 준비한다. Poky 저장소는 사용하지 않는다.

### 2. Raspberry Pi 4 이미지 빌드

```sh
./build-yocto.sh
```

주요 산출물은 다음 경로에 생성된다.

```text
build/tmp/deploy/images/raspberrypi4-64/
├── Image-raspberrypi4-64.bin
├── bcm2711-rpi-4-b.dtb
├── bcm2711-rpi-4-b-qemu-console.dtb
├── core-image-base-raspberrypi4-64.rootfs.wic
└── core-image-base-raspberrypi4-64.rootfs.wic.bz2
```

### 3. 쓰기 가능한 QEMU 디스크 준비

```sh
./prepare-image.sh
```

최신 `wic.bz2`를 프로젝트 루트의 `rpi4.wic`으로 푼다. 이 파일과 빌드
산출물은 Git에 포함되지 않는다.

### 4. QEMU 11.0.3 빌드

```sh
docker run --rm --user 0 --security-opt seccomp=unconfined \
  -v "$PWD":/workdir -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh
```

빌드 결과는 `qemu-install/`에 설치된다. 버전과 머신은 다음처럼 확인한다.

```sh
./qemu-install/bin/qemu-system-aarch64 --version
./qemu-install/bin/qemu-system-aarch64 -machine help | grep '^raspi4b '
```

### 5. 대화형 raspi4b 콘솔

```sh
./build-test-image.sh
bash poc/raspi4b/run-console.sh --fresh
```

콘솔용 WIC는 원본을 자르지 않고 QEMU SD 모델이 요구하는 최소 2의
거듭제곱 크기로 자동 확장된다. 로그인 계정은 `root`, 비밀번호는 없다.
게스트에서는 `poweroff`, QEMU에서는 `Ctrl-a x`로 종료한다.

## 2026-08-06 검증 결과

QEMU 11.0.3과 별도 QEMU 콘솔 DTB로 다음 항목을 확인했다.

- `Raspberry Pi 4 Model B` 인식
- Cortex-A72 4개 CPU 기동
- Linux 6.18.33 부팅
- `/dev/mmcblk1p2` rootfs 마운트 및 읽기/쓰기 remount
- systemd 259.2 실행과 multi-user 서비스 시작
- PL011 `ttyAMA0` 로그인, 명령 입력 및 정상 poweroff
- UUID 기반 `/boot` 마운트

공식 QEMU의 `raspi4b`는 stock DTB에서 미구현된 PCIe, RNG200, thermal,
GENET 노드를 시작 시 비활성화한다. stock DTB는 PL011을 Bluetooth에
연결하므로 QEMU 전용 DTB에서 해당 Bluetooth serdev 노드만 끈다.

### 콘솔 및 `/boot` 원인과 해결

부팅 인자는 기존 Kirkstone/QEMU 9.2 실행과 동일하게 유지했다.

```text
console=ttyAMA0,115200
earlycon=pl011,0xfe201000
root=/dev/mmcblk1p2 rootwait rw
```

Wrynose stock DTB 부팅 로그에서 확인한 흐름은 다음과 같다.

1. PL011 earlycon을 통해 Linux 6.18.33 로그가 정상 출력됨
2. `/dev/mmcblk1p2`가 rootfs로 정상 마운트되고 systemd 259.2가 실행됨
3. udev가 Bluetooth 스택과 `hci_uart_bcm`을 로드함
4. stock DTB의 `serial0-0` Bluetooth 장치가 PL011을 사용하려고 probe함
5. QEMU가 구현하지 않은 firmware GPIO 때문에 Bluetooth probe가 `-5`로 실패함
6. PL011이 `ttyAMA1`로 등록되어 `ttyAMA0` getty와 RX가 동작하지 않음

QEMU 전용 DTB는 PL011을 `serial0`/`ttyAMA0`으로 되돌리고 Bluetooth
child를 비활성화한다. 동일 Wrynose 이미지에서 QEMU 9.2와 11.0.3 모두
stock DTB 문제를 재현했으므로 QEMU 버전 변경이 직접 원인은 아니다.

기본 Raspberry Pi WKS는 부트 파티션에 `--ondisk mmcblk0`을 사용한다.
Wic이 이를 최종 `/etc/fstab`의 `/dev/mmcblk0p1 /boot` 항목으로 변환하지만,
QEMU의 SD 카드는 `mmcblk1`이므로 systemd가 90초 동안 잘못된 장치를
기다렸다. 전용 WKS의 `--use-uuid`로 `/boot`를 `UUID=...` 형식으로 생성해
실물 보드와 QEMU의 장치 번호 차이를 제거했다.

## 자동 테스트 하니스

- `poc/run-poc.sh`: `virt` 머신과 virtio/9p 기반 테스트
- `poc/raspi4b/run-poc-raspi4b.sh`: raspi4b SD 이미지에 테스트 파일을
  주입하고 결과를 회수하는 하니스
- `poc/raspi4b/run-console.sh`: raspi4b 대화형 콘솔

대용량 `sources/`, `build/`, QEMU 소스/빌드/설치 디렉터리와 `*.wic`은
모두 `.gitignore` 대상이다.
