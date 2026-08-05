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
- DTB: Yocto가 생성한 원본 `bcm2711-rpi-4-b.dtb`

`meta-device-simulation`은 QEMU/테스트에 필요한 커널 config와 시리얼
getty만 추가한다. DTB를 패치하거나 별도의 QEMU용 DTB를 만들지 않는다.

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

## 2026-08-04 검증 결과

QEMU 11.0.3과 수정하지 않은 Wrynose DTB로 다음 항목을 확인했다.

- `Raspberry Pi 4 Model B` 인식
- Cortex-A72 4개 CPU 기동
- Linux 6.18.33 부팅
- `/dev/mmcblk1p2` rootfs 마운트 및 읽기/쓰기 remount
- systemd 259.2 실행과 multi-user 서비스 시작

공식 QEMU의 `raspi4b`는 stock DTB에서 미구현된 PCIe, RNG200, thermal,
GENET 노드를 시작 시 비활성화한다. 또한 stock DTB는 PL011을 Bluetooth에
연결하므로 `ttyAMA0` 대화형 입력과 Bluetooth 드라이버가 충돌할 수 있다.
따라서 이번 무-DTB 변경 검증 범위는 systemd 부팅까지이며, 안정적인
대화형 로그인은 별도 DTB 또는 QEMU의 UART 모델 개선 작업으로 분리한다.

### 확인된 콘솔 문제

부팅 인자는 기존 Kirkstone/QEMU 9.2 실행과 동일하게 유지했다.

```text
console=ttyAMA0,115200
earlycon=pl011,0xfe201000
root=/dev/mmcblk1p2 rootwait rw
```

`run-console.sh`에서 달라진 실행 요소는 QEMU 바이너리가
`qemu92-install`의 9.2에서 `qemu-install`의 11.0.3으로 바뀐 것이다.
머신, CPU, 메모리, kernel, DTB, SD 및 콘솔 인자는 변경하지 않았다.

Wrynose 부팅 로그에서 확인한 흐름은 다음과 같다.

1. PL011 earlycon을 통해 Linux 6.18.33 로그가 정상 출력됨
2. `/dev/mmcblk1p2`가 rootfs로 정상 마운트되고 systemd 259.2가 실행됨
3. udev가 Bluetooth 스택과 `hci_uart_bcm`을 로드함
4. stock DTB의 `serial0-0` Bluetooth 장치가 PL011을 사용하려고 probe함
5. QEMU가 구현하지 않은 firmware GPIO 때문에 Bluetooth probe가 `-5`로 실패함
6. 이후 `ttyAMA0`에서 안정적인 대화형 입력과 login 프롬프트를 확인하지 못함

진단용으로 `module_blacklist=hci_uart`를 추가했을 때 커널은 해당 모듈을
차단했지만 제한 시간 180초 내 login 프롬프트는 확인되지 않았다. 이 옵션은
진단 명령에서만 사용했으며 기본 실행 스크립트에는 넣지 않았다.

현재 결론은 커널과 rootfs의 부팅 실패가 아니라 stock DTB의 PL011 소유권과
QEMU raspi4b 입력 경로에 관련된 문제라는 것이다. 이전 환경과 정확히
구분하려면 동일 Wrynose Kernel/DTB/WIC를 QEMU 9.2와 11.0.3에서 각각
실행하는 A/B 테스트가 필요하다. 그다음 필요하면 Kirkstone Linux 5.15와
Wrynose Linux 6.18을 같은 QEMU에서 비교한다.

## 자동 테스트 하니스

- `poc/run-poc.sh`: `virt` 머신과 virtio/9p 기반 테스트
- `poc/raspi4b/run-poc-raspi4b.sh`: raspi4b SD 이미지에 테스트 파일을
  주입하고 결과를 회수하는 하니스
- `poc/raspi4b/run-console.sh`: raspi4b 대화형 콘솔

대용량 `sources/`, `build/`, QEMU 소스/빌드/설치 디렉터리와 `*.wic`은
모두 `.gitignore` 대상이다.
