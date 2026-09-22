# 문서 안내

프로젝트 문서는 `docs/` 한 곳에서 관리한다. 루트 `README.md`는 빌드와
실행의 시작점이고, 이 문서는 분석·검증 보고서의 기준과 보관 문서를
구분한다.

## 현재 기준 문서

현재 기준은 Yocto Wrynose 6.0.2, Linux 6.18.33, 패치된 QEMU 11.0.3
`raspi4b` revision 1.5와 `fw` 브랜치다.

| 문서 | 내용 |
|---|---|
| [`QEMU_RPI4_PCIE_GENET_USB_REVIEW.md`](QEMU_RPI4_PCIE_GENET_USB_REVIEW.md) | QEMU 패치 구성과 콘솔, PCIe, GENET, TAP, xHCI 종합 검토 |
| [`RPI4_PCIE_USB_STORAGE_TEST.md`](RPI4_PCIE_USB_STORAGE_TEST.md) | SanDisk 물리 USB 저장장치 전달 및 raw-read 상세 시험 |
| [`WRYNOSE_BOOT_MOUNT_ANALYSIS.md`](WRYNOSE_BOOT_MOUNT_ANALYSIS.md) | `/boot` 장치 번호 문제와 filesystem UUID 해결 분석 |
| [`RPI4_DMESG_IMPLEMENTATION_STATUS.md`](RPI4_DMESG_IMPLEMENTATION_STATUS.md) | 실제 콘솔 부팅 dmesg 기반 모듈별 구현·미구현 현황 |
| [`RPI4_WAYLAND_VIRTIO_GPU_VALIDATION.md`](RPI4_WAYLAND_VIRTIO_GPU_VALIDATION.md) | virtio-gpu 기반 Weston/Wayland, USB 입력 및 15 FPS 화면 검증 |
| [`RPI4_VIRTUAL_CAMERA_PHASE1_VALIDATION.md`](RPI4_VIRTUAL_CAMERA_PHASE1_VALIDATION.md) | v4l2loopback 가상 카메라, Wayland preview 및 15 FPS 녹화 검증 |
| [`RPI4_VIRTUAL_CAMERA_PHASE1_JIRA_COMMENTS.md`](RPI4_VIRTUAL_CAMERA_PHASE1_JIRA_COMMENTS.md) | Camera Phase 1 작업 이력용 Jira comment 초안 |

최신 실행 명령은 프로젝트 루트 [`README.md`](../README.md)를 우선한다.

## 현재 확인된 범위

- Wrynose `core-image-base` 빌드 및 UUID 기반 `/boot` 마운트
- QEMU 전용 PL011 DTB를 이용한 `ttyAMA0` 콘솔 입력과 systemd 부팅
- BCM2711 PCIe root port 및 downstream PCIe BAR 접근
- BCM2838 GENET과 Host/Guest 양방향 TAP ping
- PCIe `virtio-net-pci`와 Host/Guest 양방향 TAP ping
- PCIe `qemu-xhci`와 물리 USB mass-storage 블록 읽기

## 현재 제한

- QEMU가 실물 Raspberry Pi 4의 모든 주변장치를 모델링하지는 않는다.
- xHCI 시험은 QEMU 범용 controller를 사용하며 실물 VL805 에뮬레이션이
  아니다.
- 시험한 SanDisk 장치는 USB 2.0 High-Speed 제품이다. xHCI의 USB 3
  capability는 확인했지만 물리 USB 3 SuperSpeed 전송률은 검증하지 않았다.
- 현재 Guest 이미지에는 NTFS3/`ntfs-3g`가 없어 NTFS 블록 장치는 읽을
  수 있지만 파일시스템으로 마운트할 수 없다.
- BCM2711 RNG200, thermal, VideoCore 기반 멀티미디어 등 미구현 장치는
  QEMU에서 비활성화되거나 probe 오류를 출력할 수 있다.

## 보관 문서

[`archive/kirkstone/`](archive/kirkstone/)에는 2026-07~08의 Kirkstone,
Linux 5.15, QEMU 8.2 `virt` 및 QEMU 9.2 `raspi4b` 검수 기록을 보관한다.
현재 환경의 사용법이나 TODO로 사용하지 않는다.
