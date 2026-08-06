# Raspberry Pi 4 PCIe xHCI Host USB 메모리 시험

## 목적과 범위

패치된 QEMU `raspi4b`의 BCM2711 PCIe root port에 범용 `qemu-xhci`
endpoint를 연결하고, Host의 물리 USB 메모리를 `usb-host`로 전달하여
Guest의 USB mass-storage 및 블록 읽기 경로를 검증한다.

`qemu-xhci`는 USB 3 SuperSpeed capable controller지만 시험한 SanDisk
장치는 USB 2.0 High-Speed 제품이다. 따라서 이 시험은 PCIe xHCI를 통한
물리 USB 전달 시험이며 실제 USB 3 전송 성능 시험은 아니다.

## 시험 환경

- 시험일: 2026-08-06
- Yocto: Wrynose 6.0.2
- 이미지: `core-image-base`
- Linux: 6.18.33-v8
- QEMU: 프로젝트 패치가 적용된 11.0.3 `raspi4b` revision 1.5
- DTB: `bcm2711-rpi-4-b-qemu-console.dtb`
- USB 메모리: SanDisk Cruzer Blade `0781:5567`
- 용량: 7.80 GB / 7.26 GiB
- Host 경로: `/dev/bus/usb/001/023`, `/dev/sda1`
- 파일시스템: NTFS
- Host 연결 속도: USB 2.0 High-Speed 480 Mbit/s

Bus와 Device 번호는 USB를 다시 연결할 때 바뀔 수 있다. 위의 `001/023`은
시험 당시 값이며 고정 설정으로 사용하면 안 된다.

## Host 사전 확인

다음 명령으로 대상 USB와 마운트 상태를 확인했다.

```sh
lsusb
lsusb -t
lsblk -o NAME,PATH,TRAN,VENDOR,MODEL,SERIAL,SIZE,FSTYPE,LABEL,MOUNTPOINTS
```

시험 당시 주요 결과는 다음과 같았다.

```text
Bus 001 Device 023: ID 0781:5567 SanDisk Corp. Cruzer Blade
Port 009: Dev 023, Class=Mass Storage, Driver=usb-storage, 480M
sda  usb  SanDisk  Cruzer Blade  7.3G
└─sda1                            7.3G ntfs
```

`/dev/sda1`은 이미 마운트 해제된 상태였다. 마운트되어 있다면 데이터
손상을 방지하기 위해 QEMU 실행 전에 다음처럼 해제해야 한다.

```sh
sudo umount /dev/sdX1
```

## 실행 명령

`run-console.sh`에 시험 시점의 Bus와 Device 번호를 전달했다.

```sh
RPI4_USB_BUS=1 \
RPI4_USB_ADDR=23 \
bash poc/raspi4b/run-console.sh --fresh
```

스크립트가 생성한 핵심 QEMU 구성은 다음과 같다.

```text
-device qemu-xhci,bus=pcie.1,id=xhci,msi=off,msix=off
-device usb-host,bus=xhci.0,hostbus=1,hostaddr=23
```

Docker에는 선택한 USB 노드만 전달했다.

```text
--device /dev/bus/usb/001/023
```

Host에서 별도로 `usb-storage` unbind를 수행하지 않아도 컨테이너 내부의
QEMU/libusb가 인터페이스를 점유하고, QEMU 종료 후 Host에 장치가 다시
등록되는 것을 확인했다.

## Guest 확인 명령

PCIe, xHCI, USB topology와 블록 장치를 확인했다.

```sh
lspci -nn
lsusb -t
cat /proc/partitions
dmesg | grep -Ei 'pcie|xhci|usb-storage|scsi|sd[a-z]|Cruzer'
```

USB 파티션의 앞 4 MiB를 읽고 SHA-256을 계산했다. 이 명령은 USB
메모리에 데이터를 쓰지 않는다.

```sh
set -o pipefail
dd if=/dev/sda1 bs=1M count=4 2>/dev/null | sha256sum
```

## 시험 결과

### 성공 항목

PCIe root port와 xHCI endpoint가 정상적으로 열거되었다.

```text
brcm-pcie fd500000.pcie: link up, 2.5 GT/s PCIe x1 (!SSC)
pci 0000:01:00.0: [1b36:000d] class 0x0c0330 PCIe Endpoint
xhci_hcd 0000:01:00.0: xHCI Host Controller
xhci_hcd 0000:01:00.0: Host supports USB 3.0 SuperSpeed
```

SanDisk 장치가 xHCI의 USB 2 bus에서 열거되고 mass-storage 및 SCSI
디스크로 등록되었다.

```text
usb 1-1: new high-speed USB device number 2 using xhci_hcd
usb 1-1: Product: Cruzer Blade
usb-storage 1-1:1.0: USB Mass Storage device detected
scsi 0:0:0:0: Direct-Access SanDisk Cruzer Blade 1.00
sd 0:0:0:0: [sda] 15232000 512-byte logical blocks
sda: sda1
```

Guest에서 `/dev/sda1`의 앞 4 MiB raw-read에 성공했다.

```text
c77820efbdee614c8f3c2afc104a4e8bd3ad58d160ba976cab5cff52f1243974  -
USB_RAW_READ_PASS
```

QEMU 종료 후 Host에서 `Bus 001 Device 023`과 `/dev/sda1`이 다시 나타나고
마운트되지 않은 상태로 복귀한 것을 확인했다.

### 제한 및 실패 항목

Guest에서 NTFS 파티션을 읽기 전용으로 마운트하는 시험은 실패했다.

```sh
mount -o ro /dev/sda1 /tmp/host-usb
```

```text
mount: /tmp/host-usb: unknown filesystem type 'ntfs'.
USB_MOUNT_FAIL
```

원인은 PCIe, xHCI 또는 USB 전달 실패가 아니라 현재 Wrynose
`core-image-base`에 NTFS filesystem 지원이 포함되지 않았기 때문이다.
파일 단위 접근까지 필요하면 이미지에 커널 NTFS3 또는 `ntfs-3g` 지원을
추가하여 Yocto 이미지를 다시 빌드해야 한다.

또한 시험 장치 자체가 USB 2.0 High-Speed 제품이므로 xHCI controller의
SuperSpeed capability는 확인했지만 물리 장치의 USB 3 전송 속도는
검증하지 않았다. 실제 SuperSpeed 시험에는 `lsusb -t`에서 `5000M`
이상으로 표시되는 USB 3 저장장치가 필요하다.

## 최종 판정

- BCM2711 PCIe root port: 성공
- PCIe `qemu-xhci` endpoint 및 BAR 접근: 성공
- xHCI USB 2/USB 3 root bus 초기화: 성공
- Host 물리 USB 메모리 전달: 성공
- Guest USB mass-storage/SCSI/`/dev/sda1` 생성: 성공
- Guest raw block read: 성공
- NTFS 파일시스템 마운트: 이미지 기능 누락으로 실패
- 실제 USB 3 SuperSpeed 장치 성능: 미검증

따라서 Raspberry Pi 4 PCIe xHCI를 통한 물리 USB 저장장치 연결 및 블록
읽기 경로는 정상 동작한다. 남은 작업은 USB 전달 문제가 아니라 Guest
이미지의 NTFS 지원 추가와 실제 USB 3 장치를 이용한 속도 검증이다.
