# Camera Phase 1 Jira comments

아래 comment를 번호 순서대로 Jira에 등록한다.

## Comment 1 - 구현 범위

QEMU Raspberry Pi 4 환경에서 실제 카메라 없이 camera application 및 Wayland
출력 경로를 시험할 수 있도록 v4l2loopback 기반 가상 카메라 구현을 시작했다.

검증 경로는 다음과 같다.

GStreamer test pattern -> v4l2loopback `/dev/video10` -> V4L2 consumer ->
Wayland sink -> Weston -> virtio-gpu -> QEMU display/VNC

이번 Phase 1에는 실제 USB/UVC passthrough 및 Raspberry Pi VideoCore
camera/VCHI/MMAL 경로는 포함하지 않는다.

## Comment 2 - Yocto 구현

Yocto layer에 v4l2loopback 0.15.4 kernel module recipe와 가상 카메라 demo
recipe를 추가했다.

부팅 시 `/dev/video10`이 `QEMU-Virtual-Camera`라는 이름으로 생성되도록 다음
옵션을 적용했다.

`video_nr=10 card_label=QEMU-Virtual-Camera exclusive_caps=1 max_buffers=4`

이미지에는 GStreamer core, videotestsrc, videoconvert, V4L2 source/sink 및
Wayland sink plugin을 포함했다. simulation layer가 자체 `.bb` recipe를 찾을
수 있도록 `BBFILES` 설정도 확장했다.

## Comment 3 - 실행 도구

다음 실행 도구를 추가했다.

- `virtual-camera-feed`: ball test pattern을 YUY2 640x480 30fps로
  `/dev/video10`에 공급
- `virtual-camera-preview`: `/dev/video10`을 mmap 방식으로 읽어
  `/run/wayland-0` Weston socket에 출력

장치 경로, 해상도, FPS와 test pattern은 환경 변수로 변경할 수 있다.

## Comment 4 - 초기 장애 분석

초기 v4l2loopback 0.15.3 시험에서 producer와 format negotiation은
정상이었지만 consumer가 첫 frame을 dequeue한 직후 두 번째 DQBUF에서
실패했다.

주요 오류는 `Failed to allocate a buffer`, `streaming stopped, reason error
(-5)`였다. Wayland를 제외한 `v4l2src -> fakesink`에서도 동일하게 재현되어
그래픽/Wayland 문제가 아니라 v4l2loopback capture queue 문제로 분리했다.

## Comment 5 - A/B 시험 및 수정

동일한 kernel, QEMU, GStreamer pipeline에서 v4l2loopback 버전만 변경해
A/B 시험했다.

- v0.15.3: 두 번째 DQBUF 실패, 30 frame consumer 실패
- v0.15.4: 30 frame consumer 정상 종료(exit code 0)

따라서 recipe를 v0.15.4로 변경하고 signed release가 가리키는 commit SHA로
고정했다.

Wayland pipeline에서는 중간 GStreamer `queue`가 capture buffer를 점유하면서
DQBUF 실패를 유발했다. `max_buffers`를 4에서 32로 늘려도 해결되지 않았고,
`queue`를 제거하면 max_buffers=4에서도 지속 실행됐다. 최종 preview는
`v4l2src io-mode=mmap ! videoconvert ! waylandsink`로 구성했다.

## Comment 6 - 빌드 및 기능 검증

최종 Yocto `core-image-base` 빌드에서 BitBake 7480/7480 task가 모두
성공했다. rootfs에서 v4l2loopback module, module autoload/configuration,
producer/preview script 및 필요한 GStreamer plugin을 확인했다.

QEMU 부팅 후 다음 항목을 확인했다.

- v4l2loopback 0.15.4 로드
- `/dev/video10` 및 `QEMU-Virtual-Camera` 생성
- producer와 preview process 동시 실행 유지
- YUY2 640x480 30fps 입력 협상
- RGBx 640x480 30fps Wayland 출력 협상
- Weston 화면에서 움직이는 ball pattern 표시

`zwp_linux_dmabuf_v1` bind 경고는 발생하지만 SHM fallback으로 출력이
정상 유지되므로 Phase 1 기능에는 영향이 없다.

## Comment 7 - 15 FPS 캡처 결과

실행 중인 QEMU framebuffer에서 기존 영상을 재인코딩하지 않고 150장의 PNG를
15 FPS 목표로 새로 수집했다.

- frames: 150
- elapsed: 9.933387초
- measured FPS: 14.9999
- mean interval: 66.667ms
- min/max interval: 66.451/66.865ms

표본 frame들의 SHA-256 값이 모두 달라 실제 화면 갱신도 확인했다.

GIF는 800x480, 150 frame, 10초, 평균 15.0000 FPS다. MP4는 H.264,
800x480, 150 frame, 15/1 FPS, 10초로 검증했다.

산출물:

- `artifacts/rpi4-virtual-camera-wayland.png`
- `artifacts/rpi4-virtual-camera-wayland.gif`
- `artifacts/rpi4-virtual-camera-wayland.mp4`
- `artifacts/rpi4-virtual-camera-wayland.metrics.txt`

## Comment 8 - 최종 상태 및 후속 작업

Phase 1 목표인 가상 V4L2 camera 생성, synthetic frame 공급, V4L2 consumer
읽기, Weston/Wayland 출력 및 15 FPS 화면 녹화를 완료했다.

후속 단계에서는 다음 항목을 별도로 진행한다.

- 일반 camera application에서 `/dev/video10` 선택
- camera application 사진 촬영 및 파일 저장
- camera application 영상 녹화 및 재생
- 실제 USB/UVC camera passthrough
- 필요 시 QEMU UVC device model 또는 USB gadget 방식 검토

