# RPi4 Yocto 이미지 빌드 + QEMU 자동 테스트

Ubuntu 호스트에서 Raspberry Pi 4용 Yocto 이미지를 빌드하고, QEMU로 실물
보드 없이 T1~T3 자동 테스트를 수행하는 프로젝트다. Docker는 사용하지 않는다.

## 테스트 계층

| 계층 | QEMU 머신 | 검증 범위 |
|---|---|---|
| T1 | `virt` | 앱, 라이브러리, 파일시스템, 유저스페이스 |
| T2 | `virt` | 실제 Pi 커널의 syscall, virtio, 블록 등 범용 기능 |
| T3 | `raspi4b` | BCM2711, Device Tree, MMC, GPIO 등 QEMU 구현 SoC 장치 |
| T4 | 실물 보드 | 센서, 실제 GPIO 타이밍, 카메라, GPU, 물리 네트워크 |

QEMU `raspi4b`에 구현되지 않은 PCIe, GENET Ethernet, PWM과 실제 전기적
특성은 T3에서 검증할 수 없다.

## 호스트 요구사항

- Ubuntu 24.04 x86_64
- 권장: CPU 8코어 이상, RAM 16GiB 이상, 여유 디스크 150GiB 이상
- Yocto Wrynose 6.0 LTS 호스트 패키지
- QEMU 빌드 패키지
- Python 3와 `pexpect`
- T3 WIC 주입을 위한 `sfdisk`, `dd`, `debugfs`

Ubuntu 패키지 예시:

```bash
sudo apt-get install \
  build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 libglib2.0-dev libpixman-1-dev \
  libsdl1.2-dev liblz4-tool locales python3 python3-git python3-jinja2 \
  python3-pexpect python3-pip python3-subunit socat texinfo unzip wget \
  xz-utils zstd lz4 ninja-build pkg-config
```

`libslirp-dev`는 QEMU 사용자 모드 네트워크가 필요할 때만 선택적으로
설치합니다. 이 저장소의 시리얼·디스크 기반 T1~T3 검증에는 필요하지
않으며, 빌드 스크립트가 설치 여부를 자동 감지합니다.

## 전체 실행 순서

```bash
# 1. Poky 6.0.2 + meta-raspberrypi wrynose 준비
./setup-yocto.sh

# 2. Pi4 core-image-base 빌드
./build-image.sh

# 3. stable QEMU 11.0.2 빌드
./build-qemu.sh

# 4. 범용 T1/T2 테스트
./run-t1-t2.sh

# 5. BCM2711 T3 테스트
./run-t3.sh

# Raspberry Pi 4 대화형 콘솔 접속
./run-rpi4-console.sh
```

최초 Yocto 빌드는 네트워크와 머신 성능에 따라 수십 분에서 수 시간이
걸린다. 다운로드와 sstate 캐시는 각각 `downloads/`, `sstate-cache/`에
보존된다.

## 구성

- `setup-yocto.sh`: 공식 6.0.2 릴리스 아카이브와 BSP 레이어를 `sources/`에 준비
- `build-image.sh`: 호스트 BitBake 빌드 및 `conf/auto.conf` 생성
- `meta-device-simulation/`: virtio/9p 커널 설정을 담은 커스텀 레이어
- `build-qemu.sh`: QEMU stable을 `qemu-install/`에 설치
- `run-t1-t2.sh`: `virt` 머신, 9p 공유 기반 테스트
- `run-t3.sh`: `raspi4b` 머신, root 권한 없는 WIC 주입/회수 기반 테스트
- `run-rpi4-console.sh`: `raspi4b` 대화형 시리얼 콘솔 실행
- `scripts/qemu_expect.py`: 부팅, 테스트, 종료 자동화
- `poc/testshare/`: T1/T2 게스트 테스트 및 앱 배치 위치
- `poc/raspi4b/testfiles/`: T3 게스트 테스트 및 앱 배치 위치

## 앱 바이너리 테스트

바이너리는 ARM64이며 `--selftest`를 지원한다고 가정한다.

```bash
cp /path/to/myapp poc/testshare/myapp
./run-t1-t2.sh

cp /path/to/myapp poc/raspi4b/testfiles/myapp
./run-t3.sh
```

테스트 스크립트는 `myapp` 종료 코드를 호스트까지 전달한다. 결과와 전체
시리얼 로그는 다음 위치에 생성된다.

```text
poc/testshare/result.txt
poc/t1-t2-boot.log
poc/raspi4b/result.txt
poc/raspi4b/t3-boot.log
```

## 빌드 설정

`build-image.sh`는 `build/conf/auto.conf`를 매번 생성한다.

- `MACHINE = "raspberrypi4-64"`
- `IMAGE_FSTYPES = "wic wic.bz2"`
- T1/T2용 virtio-blk, PCI, 9p built-in
- 자동 로그인을 위한 명시적 test-only root login image features
- `ttyAMA0` serial console
- 다운로드 및 sstate 캐시의 저장소 간 재사용
- BCM43456 Wi-Fi firmware의 `synaptics-killswitch` 라이선스 명시적 수락

`allow-empty-password`, `empty-root-password`, `allow-root-login`,
`serial-autologin-root`는 테스트 이미지에만 사용해야 하며 프로덕션
이미지에서는 제거해야 한다.

QEMU `raspi4b`에서는 DT의 UART 번호 배치에 맞춰 커널 명령행을
`ttyAMA1`로 덮어쓰고, 테스트 전용 init이 결과를 WIC에 기록한 뒤
종료한다. 따라서 T3는 `sudo`나 loop/mount 권한 없이 실행할 수 있다.

대화형 콘솔은 `poc/raspi4b/rpi4-console.wic`을 계속 재사용하므로 게스트에서
변경한 파일이 다음 부팅에도 유지된다. 원본 빌드 이미지로 초기화하려면 다음과
같이 실행한다.

QEMU에서는 SD 카드가 `/dev/mmcblk1`, PL011 콘솔이 `ttyAMA1`로 등록된다.
반면 실물 보드용 이미지의 `/etc/fstab`과 getty는 각각 `mmcblk0`,
`ttyAMA0`을 기다리므로 systemd 부팅이 지연된다. 대화형 실행은
`init=/bin/sh`로 이 실물 전용 초기화를 건너뛰고 root 셸에 직접 연결한다.
필요한 가상 파일시스템은 접속 후 다음처럼 마운트할 수 있다.

```bash
mount -t proc proc /proc
mount -t sysfs sysfs /sys
```

```bash
RESET_WIC=1 ./run-rpi4-console.sh
```

환경 변수로 주요 경로와 병렬도를 변경할 수 있다.

```bash
BB_NUMBER_THREADS=16 PARALLEL_MAKE_JOBS=16 ./build-image.sh
QEMU_BUILD_JOBS=16 ./build-qemu.sh
KERNEL=/path/to/Image WIC=/path/to/image.wic ./run-t1-t2.sh
```
