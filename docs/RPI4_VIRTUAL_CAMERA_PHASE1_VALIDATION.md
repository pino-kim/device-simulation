# Raspberry Pi 4 QEMU 가상 카메라 Phase 1 검증

## 목적과 범위

이 시험은 QEMU `raspi4b` 게스트에 실제 USB/UVC 카메라 없이 V4L2 capture
device를 제공하고, 합성 영상을 카메라 입력처럼 읽어 Weston/Wayland 화면에
표시할 수 있는지 검증한다.

Phase 1은 다음 경로를 대상으로 한다.

```text
GStreamer videotestsrc
  -> v4l2sink
  -> v4l2loopback /dev/video10
  -> v4l2src
  -> videoconvert
  -> waylandsink
  -> Weston
  -> virtio-gpu-pci
  -> QEMU VNC/display backend
```

이는 실제 USB 카메라 passthrough나 QEMU UVC device model 검증이 아니다.
Raspberry Pi의 VideoCore camera/MMAL/VCHI 경로도 사용하지 않는다.

## 구현 내용

### v4l2loopback 커널 모듈

`v4l2loopback_0.15.4.bb`는 Linux 6.18.33용 out-of-tree 모듈을 빌드한다.
source revision은 signed v0.15.4 tag가 가리키는 commit
`0f9ee86760b7f2bea174b7e3e7a1d38845da0ab4`로 고정했다.

모듈은 부팅 시 다음 옵션으로 자동 로드된다.

```text
video_nr=10
card_label=QEMU-Virtual-Camera
exclusive_caps=1
max_buffers=4
```

따라서 게스트에는 `/dev/video10`과 `QEMU-Virtual-Camera` 장치가 생성된다.

### 가상 카메라 producer

`virtual-camera-feed`는 기본적으로 다음 영상을 `/dev/video10`에 공급한다.

- pattern: `ball`
- format: `YUY2`
- resolution: `640x480`
- rate: `30/1 fps`

장치, 크기, 프레임률 및 pattern은 환경 변수로 변경할 수 있다.

```sh
virtual-camera-feed
```

### Wayland preview

`virtual-camera-preview`는 systemd Weston socket인 `/run/wayland-0`을 찾아
다음 파이프라인을 실행한다.

```sh
gst-launch-1.0 -v \
    v4l2src device=/dev/video10 io-mode=mmap \
    ! videoconvert \
    ! waylandsink sync=false
```

consumer 파이프라인에는 중간 `queue`를 사용하지 않는다. 시험 결과 이
`queue`가 v4l2loopback capture buffer를 점유해 반복 `DQBUF`를 실패시키는
것으로 확인됐다.

### Yocto 이미지 구성

simulation layer가 자체 `.bb` recipe를 검색하도록 `BBFILES`를 확장했고,
Raspberry Pi 4 `core-image-base`에 다음 패키지를 포함했다.

- `v4l2loopback`
- `virtual-camera-demo`
- GStreamer core
- `videotestsrc`
- `videoconvertscale`
- `video4linux2`
- `waylandsink`

## 빌드 검증

다음 명령으로 이미지를 빌드했다.

```sh
./build-yocto.sh
```

결과는 다음과 같다.

- 대상: `core-image-base`
- machine: `raspberrypi4-64`
- kernel: Linux `6.18.33-v8`
- BitBake task: `7480/7480` 성공
- 생성 이미지: `core-image-base-raspberrypi4-64.rootfs.wic`
- recipe/package QA: 성공

rootfs에서 다음 파일을 확인했다.

```text
/lib/modules/6.18.33-v8/updates/v4l2loopback.ko.xz
/usr/lib/modules-load.d/v4l2loopback.conf
/usr/lib/modprobe.d/v4l2loopback.conf
/usr/bin/virtual-camera-feed
/usr/bin/virtual-camera-preview
/usr/lib/gstreamer-1.0/libgstvideotestsrc.so
/usr/lib/gstreamer-1.0/libgstvideo4linux2.so
/usr/lib/gstreamer-1.0/libgstwaylandsink.so
```

## 기능 시험

### 부팅 및 장치 확인

```sh
bash poc/raspi4b/run-wayland.sh --fresh --vnc 127.0.0.1:9
```

게스트에서 다음 결과를 확인했다.

```text
module version: 0.15.4
device: /dev/video10
card name: QEMU-Virtual-Camera
module: v4l2loopback loaded
```

`videotestsrc`, `v4l2sink`, `v4l2src`, `waylandsink` 플러그인도 모두 정상
로드됐다.

### V4L2 단독 시험

Wayland 영향을 제외하기 위해 producer 실행 후 다음 consumer를 시험했다.

```sh
gst-launch-1.0 -q \
    v4l2src device=/dev/video10 io-mode=2 num-buffers=30 \
    ! fakesink sync=false
```

v0.15.4에서는 30프레임 처리가 exit code 0으로 완료됐다.

### v0.15.3과 v0.15.4 A/B 시험

동일한 Linux, QEMU, GStreamer 및 pipeline에서 드라이버 버전만 바꿔
시험했다.

| 항목 | v0.15.3 | v0.15.4 |
|---|---:|---:|
| 첫 capture buffer dequeue | 성공 | 성공 |
| 연속 DQBUF | 두 번째 요청에서 실패 | 정상 |
| 30프레임 fakesink | 실패 | 성공 |

v0.15.3 실패 로그의 핵심은 다음과 같다.

```text
dequeued buffer ... seq:64 (ix=2)
dequeueing a buffer
Failed to allocate a buffer
streaming stopped, reason error (-5)
```

따라서 producer 시작, format negotiation 또는 최초 메모리 할당 문제가
아니라 반복 capture queue 처리 문제로 판정했다. v0.15.4의 buffer
mapping/locking 관련 수정이 적용된 뒤 단독 consumer가 정상화됐다.

### Wayland pipeline 교차 시험

| 드라이버/파이프라인 | 결과 |
|---|---|
| v0.15.4, `queue` 포함, `max_buffers=4` | DQBUF 실패 |
| v0.15.4, `queue` 포함, `max_buffers=32` | DQBUF 실패 |
| v0.15.4, `queue` 제거, `max_buffers=32` | 지속 실행 성공 |
| v0.15.4, `queue` 제거, `max_buffers=4` | 지속 실행 성공 |

따라서 buffer 개수를 늘리는 것은 해결책이 아니며, preview consumer의
불필요한 `queue`를 제거하는 것이 필요한 수정임을 확인했다.

최종 이미지에서 `virtual-camera-feed`와 `virtual-camera-preview` 두 process가
동시에 유지되고, Weston 화면에 움직이는 ball pattern이 표시됐다.

`Could not bind to zwp_linux_dmabuf_v1` 경고는 발생하지만 SHM 경로로 출력이
계속되므로 Phase 1의 software-rendered virtio-gpu 구성에서는 기능 실패가
아니다.

## 15 FPS 화면 캡처

QEMU monitor의 `screendump`로 framebuffer를 새로 측정했다. 기존 영상을
재인코딩한 것이 아니라 실행 중인 가상 카메라 화면에서 150장의 원본 PNG를
15 FPS 목표로 직접 수집했다.

측정 결과:

```text
target_fps=15
frames=150
elapsed_seconds=9.933387
measured_fps=14.9999
mean_interval_ms=66.667
min_interval_ms=66.451
max_interval_ms=66.865
```

0, 30, 60, 90, 120, 149번째 프레임의 SHA-256 값이 모두 달라 화면이 실제로
갱신됐음도 확인했다.

MP4 검증 결과:

```text
codec=h264
resolution=800x480
frame_rate=15/1
duration=10.000000
frames=150
```

GIF는 10 ms 단위 frame duration 제약을 고려해 `70/70/60 ms` 패턴을
반복했다. 총 150프레임, 10초, 평균 15.0000 FPS다.

## 결과 산출물

- [정지 화면](../artifacts/rpi4-virtual-camera-wayland.png)
- [15 FPS GIF](../artifacts/rpi4-virtual-camera-wayland.gif)
- [15 FPS H.264 MP4](../artifacts/rpi4-virtual-camera-wayland.mp4)
- [캡처 측정값](../artifacts/rpi4-virtual-camera-wayland.metrics.txt)

## 결론과 제한

Phase 1 목표인 가상 V4L2 카메라 생성, 합성 frame 공급, camera consumer 읽기,
Weston/Wayland 표시 및 15 FPS 관찰용 녹화가 모두 동작한다.

현재 결과가 보장하는 범위는 software virtual camera와 virtio-gpu display
경로다. 다음 항목은 별도 후속 단계다.

- 실제 USB/UVC device passthrough
- QEMU UVC device model 또는 USB gadget 방식
- 일반 camera application에서 `/dev/video10` 선택 및 촬영
- camera application의 사진/영상 저장 검증
- 실제 VC4/V3D 및 VideoCore camera/VCHI/MMAL 경로

