# Wrynose Raspberry Pi 4 QEMU 구현 현황

## 기준

이 문서는 2026-08-10 `fw` 브랜치에서 다음 명령으로 실제 콘솔 부팅 후
수집한 `dmesg`를 기준으로 한다.

```sh
bash poc/raspi4b/run-console.sh --fresh
```

시험 환경:

- Yocto Wrynose 6.0.2
- Linux 6.18.33-v8
- QEMU 11.0.3 `raspi4b` revision 1.5와 프로젝트 PCIe/GENET 패치 24개
- QEMU 전용 `bcm2711-rpi-4-b-qemu-console.dtb`
- `core-image-base` WIC, UUID 기반 `/boot` 마운트

Wrynose 6.0은 2026년의 최신 LTS series이고, 이 프로젝트가 사용하는
6.0.2는 2026-08-10 현재 공개된 최신 Wrynose point release다. 6.0.3은
2026-08-24로 예정되어 있다. 따라서 여기서 “최신 Yocto”는 개발 master가
아니라 최신 LTS의 현재 point release를 의미한다.

- Yocto 6.0 release notes: <https://docs.yoctoproject.org/dev/migration-guides/release-notes-6.0.html>
- Yocto release calendar: <https://wiki.yoctoproject.org/wiki/Release_calendar>

상태 판정:

- **완료**: 현재 부팅 또는 별도 기능 시험에서 실제 동작을 확인함
- **부분 구현**: 일부 register/probe만 동작하거나 실제 하드웨어와 다른
  대체 모델을 사용함
- **미구현**: QEMU 장치 모델이 없거나 Guest driver probe가 실패함
- **이미지 미포함**: QEMU 문제가 아니라 Yocto 이미지 패키지/설정이 없음

## 콘솔 부팅 결과

부팅과 종료 흐름은 정상이다.

```text
Linux raspberrypi4-64 6.18.33-v8 ... aarch64 GNU/Linux
Machine model: Raspberry Pi 4 Model B
fe201000.serial: ttyAMA0 ... is a PL011 rev3
printk: console [ttyAMA0] enabled
brcm-pcie fd500000.pcie: link up, 2.5 GT/s PCIe x1 (!SSC)
bcmgenet fd580000.ethernet eth0: Link is Up - 1Gbps/Full
root@raspberrypi4-64:~#
reboot: Power down
```

systemd multi-user target, 자동 root 콘솔 로그인, `/boot` 마운트, 정상
poweroff까지 약 19초가 걸렸다.

## 모듈별 구현 현황

| 넘버 | 모듈명 | 기능 | 구현 |
|---:|---|---|---|
| 1 | Yocto/OE-Core | Wrynose `core-image-base` 생성 | **완료** — Wrynose 6.0.2와 Linux 6.18.33 이미지 빌드 및 부팅 확인 |
| 2 | Cortex-A72/SMP | ARM64 CPU 4개 실행 | **완료** — 4 CPU가 EL2에서 기동됨 |
| 3 | GIC/arch_timer | 인터럽트와 ARM generic timer | **완료** — GIC handler와 62.5 MHz physical timer 동작 |
| 4 | RAM/CMA | 1 GiB Guest RAM과 contiguous memory | **완료** — 64 MiB CMA pool 포함 정상 초기화 |
| 5 | BCM2835 DMA | SD·주변장치 DMA | **부분 구현** — DMA manager가 올라오지만 `dmachans=0x1`로 제한적이며 전체 채널 기능은 미검증 |
| 6 | Firmware mailbox | ARM과 Raspberry Pi firmware property 통신 | **부분 구현** — mailbox는 활성화되지만 firmware 시간/hash가 dummy 값이고 일부 property 요청 실패 |
| 7 | PL011 UART | earlycon, `ttyAMA0`, 입력 가능한 serial console | **완료** — QEMU 전용 DTB로 출력·입력·getty·poweroff 확인 |
| 8 | AUX UART | mini UART/8250 | **미구현 또는 불완전** — `bcm2835-aux-uart`가 pin map 오류 `-EINVAL`로 probe 실패 |
| 9 | SD/MMC | WIC SD 카드와 파티션 제공 | **완료** — `/dev/mmcblk1`, `p1`, `p2` 생성 |
| 10 | EXT4/VFAT mount | rootfs 및 `/boot` 파일시스템 | **완료** — rootfs R/W, `/boot` filesystem UUID 마운트, 정상 unmount 확인 |
| 11 | BCM2711 PCIe root | PCIe host bridge, config space, IRQ, MMIO window | **완료(검증 범위)** — link up, root port, PME/AER와 downstream config/MMIO 접근 확인 |
| 12 | PCIe downstream | PCIe endpoint BAR 접근 | **완료** — `virtio-net-pci`와 `qemu-xhci` endpoint를 별도 시험해 BAR 및 데이터 전달 확인 |
| 13 | PCI I/O window | legacy port-I/O bridge window | **부분 구현** — I/O window 공간 할당 경고가 남지만 현재 ARM MMIO endpoint에는 영향 없음 |
| 14 | BCM2838 GENET | 내장 Ethernet MAC/PHY, TX/RX DMA와 IRQ | **완료** — 1 Gbps link 및 Host↔Guest TAP ping 양방향 성공 |
| 15 | GENET identity | 영구 Ethernet MAC/OTP 정보 | **부분 구현** — 네트워크는 동작하지만 firmware/OTP MAC이 없어 random MAC 사용 |
| 16 | `qemu-xhci` | PCIe USB 2/3 capable host controller | **완료(대체 모델)** — PCIe endpoint, xHCI root bus와 USB 3 capability 확인; 실물 VL805 모델은 아님 |
| 17 | `usb-host`/libusb | Host 물리 USB를 Guest로 전달 | **완료** — SanDisk USB mass-storage, SCSI, `/dev/sda1`, 4 MiB raw-read 확인 |
| 18 | VL805 USB controller | 실물 RPi4의 PCIe USB 3 controller | **미구현** — QEMU 범용 `qemu-xhci`로 대체함 |
| 19 | BCM2708 framebuffer | 부트 framebuffer와 텍스트 화면 | **부분 구현** — `/dev/fb0`, 800×480, framebuffer console 등록 확인; Host GUI 출력은 아직 미검증 |
| 20 | QEMU GUI backend | framebuffer를 Host Wayland/GTK 창으로 표시 | **미구현(현재 빌드)** — 현재 QEMU display backend는 `none`, `dbus`뿐이며 GTK 재빌드 또는 D-Bus viewer 필요 |
| 21 | VC4 DRM/KMS | display pipeline, HDMI connector, modesetting | **미구현** — `/dev/dri`가 없고 DRM module이 시작되지 않음 |
| 22 | V3D GPU | VideoCore 3D/OpenGL 가속 | **미구현** — V3D device/driver가 생성되지 않음 |
| 23 | VideoCore/VCHI | firmware service, shared memory, MMAL 통신 | **미구현** — `Videocore not initialized`, VCHI `-107` 발생 |
| 24 | BCM2835 audio | Raspberry Pi firmware 기반 오디오 | **미구현** — VCHI 초기화 실패로 audio probe `-5` |
| 25 | Camera/MMAL | Raspberry Pi camera와 MMAL service | **미구현** — camera와 MMAL VCHI probe 실패 |
| 26 | ISP/codec/HEVC | 이미지 처리 및 하드웨어 영상 codec | **미구현** — ISP, bcm2835 codec, HEVC decoder probe 실패 |
| 27 | RNG200 | BCM2711 hardware random number generator | **미구현** — QEMU가 DT node를 부팅 전 비활성화함 |
| 28 | Thermal sensor | SoC 온도 측정과 throttling 입력 | **미구현** — thermal governor만 있고 BCM2711 sensor는 QEMU가 비활성화함 |
| 29 | GPIO/pinctrl | SoC GPIO와 `/dev/gpiomem` | **부분 구현** — pinctrl과 `/dev/gpiomem`은 생성되지만 외부 pin I/O 기능은 미검증 |
| 30 | Firmware GPIO/regulator | board 전원·LED·카메라·SD voltage GPIO | **미구현 또는 불완전** — firmware GPIO property 실패로 LED/regulator probe `-5` |
| 31 | Watchdog | BCM2835 watchdog timer | **부분 구현** — driver probe 성공, timeout/reset 동작은 미검증 |
| 32 | Bluetooth HCI | Bluetooth controller와 UART transport | **미구현** — Linux protocol stack만 로드됨; PL011 console 보호를 위해 DTB의 Bluetooth serdev를 비활성화 |
| 33 | Wi-Fi/brcmfmac | onboard WLAN controller | **미구현** — Wi-Fi device와 `brcmfmac` probe 증적 없음 |
| 34 | I2C/SPI | 외부 sensor 및 HAT bus | **미검증** — DT node 존재 여부만으로 기능 구현을 판정하지 않았으며 장치 연결 시험 필요 |
| 35 | NTFS filesystem | 전달한 USB의 NTFS 파일 접근 | **이미지 미포함** — block raw-read는 성공했으나 NTFS3/`ntfs-3g` 부재로 mount 실패 |

## 구현 완료 범위 요약

현재 환경은 다음 용도에 사용할 수 있다.

- 최신 Yocto LTS 기반 ARM64 userspace와 systemd 부팅 검증
- PL011 대화형 콘솔을 통한 firmware/application 시험
- SD image, rootfs와 `/boot` 파일시스템 시험
- BCM2711 PCIe endpoint 개발과 MMIO/BAR 접근 시험
- GENET 및 PCIe network endpoint의 Host↔Guest 통신 시험
- PCIe xHCI를 이용한 Host USB 장치 전달과 block I/O 시험
- 800×480 legacy framebuffer 생성 확인

## 추가 구현 우선순위

1. **Host 화면 출력**: QEMU GTK backend를 빌드하거나 현재 D-Bus display에
   viewer를 연결해 `/dev/fb0`의 800×480 화면을 실제 확인한다.
2. **USB 파일 접근**: Yocto 이미지에 NTFS3 또는 `ntfs-3g`를 추가해
   물리 USB의 파일 단위 read-only 시험을 완료한다.
3. **GPIO/I2C/SPI 기능 시험**: 가상 장치 모델 또는 외부 backend를 정한
   뒤 register/IRQ/data path를 기능적으로 검증한다.
4. **RNG/thermal 최소 모델**: Guest software가 해당 sysfs/device를
   요구할 때 QEMU 장치 모델을 구현한다. 일반 부팅 우선순위는 낮다.
5. **VideoCore/VCHI/VC4**: 구현 범위가 매우 크다. 단순 화면 확인은 기존
   framebuffer로 먼저 완료하고, GPU·HDMI·camera·codec이 필수일 때만
   별도 장기 과제로 분리한다.

## 판정

현재 Wrynose 이미지에서 콘솔, SD, PCIe와 GENET은 실제 동작한다. PCIe
downstream도 `virtio-net-pci`와 범용 xHCI endpoint로 기능 검증됐다.
화면은 Guest legacy framebuffer까지 생성됐지만 Host 창 출력과
DRM/KMS/VideoCore 가속은 별개의 미완료 영역이다.
