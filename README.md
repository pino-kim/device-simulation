# RPi4 Yocto 이미지 빌드 + QEMU 자동테스트 PoC

라즈베리파이4용 Yocto 이미지를 빌드하고, 실물 보드 없이 **QEMU로 보드 rootfs를 부팅해 앱 바이너리만 교체하며 자동테스트**하는 환경.

## 구성
- `run-build.sh` — Yocto(kirkstone) core-image-base 빌드 (crops/yocto 컨테이너 내부에서 실행)
- `build-qemu.sh` — qemu 8.2 소스 빌드 (컨테이너, root)
- `build-qemu92.sh` — qemu 9.2 빌드. **raspi4b(BCM2711) 머신 포함** → T3(SoC 레벨 커널 테스트)용. slirp 포함
- `build-kernel-virtio.sh` — 커널에 virtio/9p built-in 추가해 재빌드
- `kernel-overlay/` — 커널 config 프래그먼트(virtio.cfg) + bbappend. 빌드 시 `sources/meta-raspberrypi/recipes-kernel/linux/`에 배치됨
- `poc/` — 자동테스트 PoC
  - `run-poc.sh` — 호스트에서 실행. QEMU 부팅 → 9p 마운트 → 테스트 → result.txt 회수 → 종료
  - `drive.expect` — 부팅/로그인/마운트/실행/종료 자동화
  - `testshare/run-tests.sh` — 게스트에서 실행되는 테스트(여기서 앱 바이너리 호출)
  - `raspi4b/` — **T3 하니스**(BCM2711 SoC). raspi4b엔 9p가 없어 SD rootfs에 바이너리 주입 → 부팅·실행 → 결과 회수. `run-poc-raspi4b.sh`, `drive.expect`, `testfiles/`

## 사용 (바이너리만 교체해 테스트)
```
cp <새 앱 바이너리> poc/testshare/myapp
bash poc/run-poc.sh
# → poc/testshare/result.txt 로 결과 회수
```

## Yocto 최초 빌드

### 준비된 구성

- 호스트: x86_64 Linux, Docker
- 컨테이너: `crops/yocto:ubuntu-22.04-base`
- Yocto: kirkstone (`poky`, `meta-raspberrypi`, `meta-openembedded`)
- 타깃: `MACHINE = "raspberrypi4-64"`
- 이미지: `core-image-base`

소스 커밋은 `bootstrap-yocto.sh`에 고정돼 있다. 대용량 소스와 빌드
산출물은 Git에 포함하지 않는다.

### 1. 소스 준비

```
./bootstrap-yocto.sh
```

다음 저장소를 `sources/` 아래에 내려받는다.

- `https://git.yoctoproject.org/poky`
- `https://github.com/agherzan/meta-raspberrypi.git`
- `https://git.openembedded.org/meta-openembedded`

### 2. 이미지 빌드

```
./build-yocto.sh
```

현재 프로젝트를 컨테이너의 `/workdir`에 연결하고 `run-build.sh`를
실행한다. `meta-device-simulation/` 레이어가 다음 설정을 적용한다.

- QEMU `virt` 부팅용 virtio block/PCI
- 호스트 파일 공유용 virtio 9p
- `ttyAMA0` 시리얼 getty
- PoC용 root 무비밀번호 로그인
- `wic.bz2`, `wic.gz` 이미지 생성

주요 산출물:

```
build/tmp/deploy/images/raspberrypi4-64/
├── Image-raspberrypi4-64.bin
├── bcm2711-rpi-4-b.dtb
├── core-image-base-raspberrypi4-64.wic.bz2
└── core-image-base-raspberrypi4-64.wic.gz
```

### 3. QEMU용 디스크 준비

```
./prepare-image.sh
```

압축된 WIC를 프로젝트 루트의 `rpi4.wic`으로 푼다. 이 파일은 QEMU
하니스가 사용하는 쓰기 가능한 작업 이미지이며 Git에서 제외된다.

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
