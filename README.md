# RPi4 Yocto 이미지 빌드 + QEMU 자동테스트 PoC

라즈베리파이4용 Yocto 이미지를 빌드하고, 실물 보드 없이 **QEMU로 보드 rootfs를 부팅해 앱 바이너리만 교체하며 자동테스트**하는 환경.

## 구성
- `run-build.sh` — Yocto(kirkstone) core-image-base 빌드 (crops/yocto 컨테이너 내부에서 실행)
- `build-qemu.sh` — raspi 지원 확인용 qemu 8.2 소스 빌드 (컨테이너, root)
- `build-kernel-virtio.sh` — 커널에 virtio/9p built-in 추가해 재빌드
- `kernel-overlay/` — 커널 config 프래그먼트(virtio.cfg) + bbappend. 빌드 시 `sources/meta-raspberrypi/recipes-kernel/linux/`에 배치됨
- `poc/` — 자동테스트 PoC
  - `run-poc.sh` — 호스트에서 실행. QEMU 부팅 → 9p 마운트 → 테스트 → result.txt 회수 → 종료
  - `drive.expect` — 부팅/로그인/마운트/실행/종료 자동화
  - `testshare/run-tests.sh` — 게스트에서 실행되는 테스트(여기서 앱 바이너리 호출)

## 사용 (바이너리만 교체해 테스트)
```
cp <새 앱 바이너리> poc/testshare/myapp
bash poc/run-poc.sh
# → poc/testshare/result.txt 로 결과 회수
```

## 핵심 제약/우회 (이 호스트: Ubuntu16.04/Py3.5/Docker1.13/qemu2.5)
1. 빌드는 crops/yocto 컨테이너 + `--security-opt seccomp=unconfined` 필수
2. mainline qemu엔 raspi4b 없음 → qemu 8.2 직접 빌드, `-M virt -cpu cortex-a72`로 부팅
3. 커널에 virtio 활성화(kernel-overlay) 필요 — 아니면 rootfs 마운트 불가
4. qemu(slirp 미포함) → 네트워크 대신 9p로 파일 교환
5. 이미지 inittab에 ttyAMA0 시리얼 getty 추가 필요(프로덕션은 SERIAL_CONSOLES)

## 한계
QEMU virt는 CPU/범용장치만 에뮬 → GPIO·카메라·GPU·센서 등 Pi 고유 HW 의존 테스트는 실물 보드 필요. 앱 로직/유저스페이스/파일시스템 회귀는 이 환경으로 커버.

## 재현 상세
대용량(sources/, build/, qemu-install/, *.wic 등)은 git 제외. 전체 진행 순서는 Jira BSP-17 코멘트 참고.
