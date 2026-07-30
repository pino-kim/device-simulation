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

Upstream QEMU `raspi4b`에 구현되지 않은 PCIe, GENET Ethernet, PWM과 실제
전기적 특성은 기본 T3에서 검증할 수 없다.

이 저장소는 2026-07-25에 게시된 Patchew PCIe/GENET 19개 패치와
프로젝트 로컬 호환성·PCIe 보정 패치 4개를 QEMU 11.0.2에 적용한다.
아직 upstream 정식 기능은 아니다.

## 네트워크 테스트

### GENET 콘솔 및 장치 확인

기본 콘솔 실행에서는 네트워크 백엔드를 만들지 않는다. 패치된 GENET에
소켓 백엔드를 연결하려면 다음처럼 실행한다.

```bash
RPI4_NET_MODE=socket RESET_WIC=1 ./run-rpi4-console.sh
```

다른 QEMU 또는 소켓 peer는 `RPI4_NET_SOCKET`으로 주소를 변경해 연결할 수
있다. QEMU가 slirp 지원으로 빌드된 호스트에서는 외부 네트워크 시험에
`RPI4_NET_MODE=user`를 사용할 수 있다.

PCIe host bridge와 GENET probe만 자동 확인하려면 다음을 실행한다.

```bash
./test-rpi4-network.sh
```

### GENET TAP 시험

Host와 Guest 사이의 양방향 ping 시험은 전용 TAP을 생성한다. 스크립트는
기존 인터페이스가 있으면 덮어쓰지 않고 중단하며, 종료 시 자신이 생성한
TAP만 삭제한다. QEMU 기본 RX ring 선택과 Guest MAC 설정을 보정하여
Host↔Guest 양방향 ping이 성공한다.

```bash
./test-rpi4-tap-ping.sh
```

기본 주소는 Host `192.168.76.1/24`, Guest `192.168.76.2/24`이다. 변경이
필요하면 sudo 뒤에 환경 변수를 전달한다.

Guest 커널이 DT에 MAC 주소가 없으면 임의 주소를 만들기 때문에 시험
스크립트는 Guest 인터페이스 MAC을 `GUEST_MAC` 값으로 명시하고 Host의
고정 neighbor 항목과 일치시킨다. 성공 시 양방향 ping 결과와 `PASS`가
표시되며 trace는 `poc/raspi4b/tap-ping.log`에 기록된다.

```bash
sudo TAP_IF=rpi4tap1 \
  HOST_CIDR=192.168.77.1/24 \
  GUEST_CIDR=192.168.77.2/24 \
  ./test-rpi4-tap-ping.sh
```

### PCIe virtio-net TAP 시험

PCIe root port 아래에 `virtio-net-pci` endpoint를 연결하는 시험은 다음과
같다. 이 경로는 PCIe config-space, bridge MMIO window, virtio BAR 접근과
Host↔Guest 양방향 ping까지 검증한다.

```bash
./test-rpi4-pcie-network.sh
```

기본 주소는 Host `192.168.78.1/24`, Guest `192.168.78.2/24`이고 PCIe
virtio 장치는 Guest의 `eth0`, GENET은 `eth1`로 등록된다.

성공 시 Guest→Host와 Host→Guest ping 결과가 모두 출력되고 마지막에
`PASS`가 표시된다. TAP 생성에는 root 권한이 필요하며, 일반 사용자로
실행하면 스크립트가 `sudo`로 다시 실행한다.

## PCIe USB/xHCI 테스트

### 구현 범위

현재 QEMU `raspi4b`에는 실물 Raspberry Pi 4의 PCIe VL805 USB
컨트롤러가 모델링되어 있지 않다. 대신 패치된 BCM2711 PCIe root port
`pcie.1`에 QEMU 범용 `qemu-xhci` endpoint를 연결하여 PCIe enumeration,
BAR 접근, xHCI 초기화와 USB 장치 연결 경로를 검증할 수 있다.

```bash
-device qemu-xhci,bus=pcie.1,id=xhci,msi=off,msix=off
```

이 구성에서 Guest가 xHCI controller와
`Host supports USB 3.0 SuperSpeed`를 인식하고, QEMU 가상 USB 키보드가
HID 장치로 등록되는 것을 확인했다. 이는 범용 xHCI 컨트롤러의 USB 3
지원 확인이며, 아래에서 시험한 물리 장치 자체는 USB 2.0 High-Speed
장치이므로 물리 USB 3 전송 속도를 검증한 결과는 아니다.

Raspberry Pi 3B에는 PCIe와 USB 3 컨트롤러가 없고 DWC2 USB 2 경로만
있으므로 이 `qemu-xhci` PCIe 구성은 적용할 수 없다.

### 물리 USB 장치 전달

QEMU 빌드 요약에 `libusb: YES`가 표시되고 장치 목록에 `usb-host`가
있어야 한다.

```bash
pkg-config --modversion libusb-1.0
./build-qemu.sh
qemu-install/bin/qemu-system-aarch64 -device help | grep usb-host
```

USB 메모리는 Host 파일시스템에서 먼저 안전하게 unmount하고, QEMU가
인터페이스를 점유할 수 있도록 Host의 `usb-storage` 드라이버에서
unbind한다. 아래의 bus/device 번호와 `1-9:1.0` 경로는 `lsusb`,
`lsusb -t`, `readlink /sys/bus/usb/devices/*` 결과에 맞게 변경해야 한다.

```bash
sudo umount /dev/sda1
echo '1-9:1.0' | sudo tee /sys/bus/usb/drivers/usb-storage/unbind
sudo setfacl -m "u:$USER:rw" /dev/bus/usb/001/022
getfacl /dev/bus/usb/001/022
```

QEMU에는 xHCI controller 다음에 물리 장치를 vendor/product ID로
연결한다. 같은 ID의 장치가 여러 개라면 `hostbus`와 `hostaddr`를
사용하여 정확한 장치를 지정한다.

```bash
-device qemu-xhci,bus=pcie.1,id=xhci,msi=off,msix=off \
-device usb-host,bus=xhci.0,vendorid=0x0781,productid=0x5567
```

SanDisk Cruzer Blade `0781:5567` 시험에서는 Guest가 USB mass-storage,
SCSI 디스크, `/dev/sda`와 `/dev/sda1`을 차례로 생성했다. `/dev/sda1`을
읽기 전용으로 마운트해 파일 접근까지 확인했으며 물리 장치에는 쓰지
않았다.

```bash
mkdir -p /tmp/host-usb
mount -o ro /dev/sda1 /tmp/host-usb
ls -laR /tmp/host-usb
umount /tmp/host-usb
```

Qualcomm `05c6:9501` vendor-specific 장치도 Guest enumeration까지
확인했다. 다만 bulk endpoint의 maxpacket 경고가 발생했으며 실제
프로토콜 통신은 검증하지 않았다. 상위 `05c6:9500` USB hub와 하위 장치를
동시에 전달하지 않고 필요한 하위 장치만 지정했다.

QEMU가 종료되면 일반적으로 Host의 `usb-storage` 드라이버가 다시
연결된다. 다음 명령으로 장치와 파티션이 복구됐는지 반드시 확인한다.

```bash
lsusb
lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINTS
```

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
  acl build-essential chrpath cpio debianutils diffstat file gawk gcc git \
  iputils-ping libacl1 libglib2.0-dev libpixman-1-dev libusb-1.0-0-dev \
  libsdl1.2-dev liblz4-tool locales python3 python3-git python3-jinja2 \
  python3-pexpect python3-pip python3-subunit socat texinfo unzip wget \
  usbutils xz-utils zstd lz4 ninja-build pkg-config
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

`run-rpi4-console.sh`는 QEMU `raspi4b`의 BCM2711, DTB와 MMC rootfs를
사용한다. QEMU 전용 PTY를 만들고 `stty`로 115200 baud, raw, no-echo를
설정한 뒤 `screen`으로 PL011 `ttyAMA0` 콘솔에 직접 연결한다.
필요한 가상 파일시스템은 접속 후 다음처럼 마운트할 수 있다.

```bash
mount -t proc proc /proc
mount -t sysfs sysfs /sys
```

`screen` 종료는 `Ctrl+A`, `\`를 차례로 누른다. CM3의
`raspi3b`/`ttyAMA0`에서 사용했던 것과 같은 연결 방식이다.

원본 RPi4 DTB는 PL011 아래의 Bluetooth serdev child가 활성화되어 있어
커널 드라이버가 RX FIFO를 읽더라도 일반 TTY 입력으로 전달되지 않는다.
Yocto 커널 recipe는 원본 DTB를 유지하면서 PL011을
`serial0`/`ttyAMA0`으로 지정하고 해당 Bluetooth child만 비활성화한
`bcm2711-rpi-4-b-qemu-console.dtb`를 별도 deploy한다. 실행 스크립트는
이 QEMU 전용 산출물을 사용한다. QEMU PL011 trace에서 PTY 입력, RX FIFO
적재, IRQ assert, Linux FIFO read와 셸 명령 실행까지 확인했다.

하나의 `core-image-base-raspberrypi4-64.rootfs.wic`을 실물 RPi4와
QEMU가 공유한다. `/boot`는 장치 번호 대신 WIC가 생성한 UUID로
마운트하므로 실물의 `/dev/mmcblk0`과 QEMU의 `/dev/mmcblk1` 모두에서
동작한다. 실물은 WIC에 포함된 원본 DTB와 `/dev/mmcblk0p2` 부팅 인자를
사용하고, QEMU는 외부의 QEMU 전용 DTB와 `/dev/mmcblk1p2` 인자를
사용한다. 실행 스크립트는 systemd와 직렬 root autologin을 기본으로 사용한다.
초기화 과정을 건너뛰고 PID 1 셸로 직접 들어가려면 다음처럼 실행한다.

```bash
DIRECT_SHELL=1 RESET_WIC=1 ./run-rpi4-console.sh
```

QEMU systemd 부팅에서 `/boot`의 `/dev/mmcblk1p1` 마운트,
`systemctl is-system-running`의 `running`, `ttyAMA0` root 자동 로그인을
확인했다.

RX 경로를 다시 검증하려면 다음을 실행한다. `INPUT_EOL=cr` 또는
`INPUT_EOL=lf`로 입력 종단 문자를 각각 확인할 수 있고, 결과는
`qemu-pl011-trace.log`, `qemu-rpi4-debug.log`,
`qemu-rpi4-console.log`에 저장된다.

```bash
INPUT_EOL=cr ./debug-rpi4-pl011-rx.sh
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
