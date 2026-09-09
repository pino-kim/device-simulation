# Raspberry Pi 4 QEMU Wayland/virtio-gpu 검증

## 목적과 범위

이 작업은 Raspberry Pi 4 QEMU 머신에서 실제 VC4/V3D 모델 대신 PCIe
`virtio-gpu-pci`를 사용하여 Linux DRM/KMS, Weston, Wayland 클라이언트 및
USB 입력 경로를 단계적으로 검증한다. 따라서 이 결과는 Wayland 사용자 공간과
QEMU display 경로의 동작 증거이며 실제 Raspberry Pi VC4/V3D 하드웨어 에뮬레이션
완료를 의미하지 않는다.

## 구현 내용

### Yocto 이미지

`core-image-base.bbappend`에서 Raspberry Pi 4 이미지에 `weston` feature와
`weston-examples`를 명시했다. 다음 진단 앱이 rootfs에 설치된다.

- `weston-flower`: 여러 surface의 이동과 합성
- `weston-smoke`: 연속 SHM 픽셀 갱신
- `weston-simple-egl`: EGL/OpenGL ES 클라이언트 경로
- `weston-presentation-shm`: presentation feedback과 연속 화면 갱신

`weston-init.bbappend`는 이미지의 `weston.ini` 끝에 다음 설정을 추가한다.

```ini
[autolaunch]
path=/usr/bin/weston-presentation-shm
watch=false
```

따라서 Weston compositor가 시작되면 presentation 테스트 앱이 자동 실행된다.

### QEMU 그래픽 및 입력

`poc/raspi4b/run-wayland.sh`는 다음 장치를 구성한다.

```text
PCI 01:00.0  virtio-gpu-pci
PCI 01:00.1  qemu-xhci
USB 1-1      QEMU USB Keyboard
USB 1-2      QEMU USB Tablet
```

raspi4b PCIe root port가 슬롯 0 하나만 허용하므로 GPU와 xHCI를 같은 슬롯의
function 0/1로 배치하고 `multifunction=on`을 사용한다. `usb-tablet`은 VNC에서
호스트 포인터와 게스트 포인터의 좌표 오차를 줄이는 절대좌표 입력 장치다.

QEMU 빌드에서는 VNC를 활성화했다. 실행 스크립트의 기본 주소는 외부에 직접
노출되지 않는 `127.0.0.1:1`(TCP 5901)이다.

## 빌드 및 실행

```sh
./build-yocto.sh
bash poc/raspi4b/run-wayland.sh --fresh
```

다른 VNC display 번호를 사용하려면 다음처럼 실행한다.

```sh
bash poc/raspi4b/run-wayland.sh --vnc 127.0.0.1:9
```

원격 호스트에서는 비암호화 VNC 포트를 공개하지 말고 SSH tunnel을 사용한다.

```sh
ssh -L 5901:127.0.0.1:5901 USER@QEMU_HOST
vncviewer 127.0.0.1:5901
```

## 검증 결과

Yocto `core-image-base` 빌드는 6,687개 task가 모두 성공했다. 생성된 rootfs에서
네 Weston 앱의 실행 파일과 `[autolaunch]` 설정을 확인했다. 커널 설정에서는
`CONFIG_DRM_VIRTIO_GPU`, `CONFIG_USB_XHCI_HCD`, `CONFIG_USB_HID`,
`CONFIG_HID_GENERIC`, `CONFIG_INPUT_EVDEV`가 활성화되어 있다.

부팅 로그에서 다음 결과를 확인했다.

- virtio-gpu가 `0000:01:00.0`에서 DRM device와 framebuffer를 생성함
- xHCI가 `0000:01:00.1`에서 USB bus 1/2를 생성함
- QEMU USB Keyboard와 Tablet이 각각 input device로 등록됨
- Weston system service가 시작되고 `Graphical Interface` target에 도달함
- 화면에서 `weston-presentation-shm`의 색상 원판이 연속 회전함

## 화면 및 녹화 산출물

- [정지 화면](../artifacts/rpi4-weston-presentation-shm.png)
- [15 FPS GIF](../artifacts/rpi4-weston-presentation-shm.gif)
- [15 FPS MP4](../artifacts/rpi4-weston-presentation-shm.mp4)
- [캡처 측정값](../artifacts/rpi4-weston-presentation-shm.metrics.txt)

최종 녹화는 새 QEMU 부팅에서 monitor framebuffer를 15 FPS 목표로 150프레임
다시 캡처했다. 측정 결과는 9.964초 동안 150프레임, 평균 15.05 FPS였다.
평균 프레임 간격은 66.667 ms이고 최소/최대 간격은 각각 66.539/66.806 ms로
일정했다. GIF와 MP4 모두 새 원본 프레임을 보간 없이 15 FPS로 보존했다.
서로 떨어진 표본 프레임의 SHA-256 값 변화로 실제 화면 갱신도 확인했다.

이 15 FPS 값은 QEMU framebuffer를 관찰한 캡처 속도이지 게스트의 실제 최대
렌더링 성능 측정값은 아니다. 실제 compositor frame timing은 presentation feedback이나
Weston 계측 결과로 별도 평가해야 한다. 이전 영상이 끊겨 보였던 원인은 Weston
문제가 아니라 0.5초 간격, 즉 2 FPS로 캡처했기 때문이다.

## 알려진 제한

- 그래픽 장치는 VC4/V3D가 아니라 소프트웨어 렌더링 기반 virtio-gpu다.
- `use-pixman=true`이므로 V3D 가속 성능은 검증하지 않는다.
- QEMU monitor PNG 캡처는 성능 측정 도구가 아니며 관찰용 증거다.
- 기본 VNC에는 인증/TLS가 구성되지 않았으므로 SSH tunnel 사용이 필요하다.
- RNG200, thermal, VCHI/camera/codec/audio 경고는 이번 그래픽 검증 범위 밖이다.
