# RPi4 Yocto 이미지 빌드 + QEMU 자동테스트 PoC

라즈베리파이4용 Yocto 이미지를 빌드하고, 실물 보드 없이 **QEMU로 보드 rootfs를 부팅해 앱 바이너리만 교체하며 자동테스트**하는 환경.

## 구성
- `run-build.sh` — Yocto(kirkstone) core-image-base 빌드 (crops/yocto 컨테이너 내부에서 실행)
- `build-qemu.sh` — qemu 8.2 소스 빌드 (컨테이너, root)
- `build-qemu92.sh` — qemu 9.2 빌드. **raspi4b(BCM2711) 머신 포함** → T3(SoC 레벨 커널 테스트)용. slirp 포함
- `build-kernel-virtio.sh` — 커널에 virtio/9p built-in 추가해 재빌드
- `Dockerfile.test` — QEMU 자동테스트에 필요한 expect/런타임 도구 이미지
- `build-test-image.sh` — 테스트 러너 이미지 빌드
- `kernel-overlay/` — 커널 config 프래그먼트(virtio.cfg) + bbappend. 빌드 시 `sources/meta-raspberrypi/recipes-kernel/linux/`에 배치됨
- `poc/` — 자동테스트 PoC
  - `run-poc.sh` — 호스트에서 실행. QEMU 부팅 → 9p 마운트 → 테스트 → result.txt 회수 → 종료
  - `drive.expect` — 부팅/로그인/마운트/실행/종료 자동화
  - `testshare/run-tests.sh` — 게스트에서 실행되는 테스트(여기서 앱 바이너리 호출)
  - `raspi4b/` — **T3 하니스**(BCM2711 SoC). raspi4b엔 9p가 없어 SD rootfs에 바이너리 주입 → 부팅·실행 → 결과 회수. `run-poc-raspi4b.sh`, `drive.expect`, `testfiles/`

## 사용 (바이너리만 교체해 테스트)
```
./build-test-image.sh  # 최초 1회. 생략해도 run-poc.sh가 자동 빌드
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

## QEMU 8.2 빌드와 virt 부팅

QEMU는 테스트 러너 이미지에 포함되지 않는다. 기존 빌드
스크립트를 crops 컨테이너에서 실행해 프로젝트의 `qemu-install/`에
설치한다.

테스트 러너 이미지는 다음과 같이 준비한다. `run-poc.sh`와 raspi4b
하니스는 이미지가 없을 때 이 명령을 자동 실행한다.

```
./build-test-image.sh
```

일반 호스트에서는 `Dockerfile.test`가 Ubuntu 22.04 기반 테스트 환경을
직접 구성한다. 이 프로젝트의 레거시 Docker 1.13 호스트에서는 빌드
스크립트가 `Dockerfile.test.legacy`를 자동 선택하며, 기존 Ubuntu 22.04
기반 `qemu-runner:latest`의 필수 명령과 공유 라이브러리를 검증한다.

Ubuntu 24.04 호스트에서도 Docker Engine이 최신 Ubuntu 이미지를 지원하면
동일하게 실행할 수 있다. 호스트가 x86_64여야 현재 QEMU 바이너리와
호환되며, 전체 테스트 전 `bootstrap-yocto.sh`, `build-yocto.sh`, QEMU
빌드 및 `prepare-image.sh` 단계의 산출물이 필요하다.

```
docker run --rm --user 0 --security-opt seccomp=unconfined \
  -v "$PWD":/workdir -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh
```

빌드 결과와 `virt` 머신 지원은 다음과 같이 확인한다.

```
docker run --rm --security-opt seccomp=unconfined \
  -v "$PWD":/workdir device-simulation-test:latest \
  /workdir/qemu-install/bin/qemu-system-aarch64 --version

docker run --rm --security-opt seccomp=unconfined \
  -v "$PWD":/workdir device-simulation-test:latest \
  /workdir/qemu-install/bin/qemu-system-aarch64 -machine help
```

`rpi4.wic`까지 준비한 뒤 기존 자동화 하니스를 실행한다.

```
bash poc/run-poc.sh
```

실제 QEMU 명령은 `poc/drive.expect`에 있으며 `-M virt`,
`-cpu cortex-a72`, virtio block, virtio 9p를 사용한다. 성공하면
로그에 `RESULT_OK`가 출력되고 게스트 테스트 결과가
`poc/testshare/result.txt`로 회수된다.

## 핵심 제약/우회 (이 호스트: Ubuntu16.04/Py3.5/Docker1.13/qemu2.5)
1. 빌드는 crops/yocto 컨테이너 + `--security-opt seccomp=unconfined` 필수
2. mainline qemu엔 raspi4b 없음 → qemu 8.2 직접 빌드, `-M virt -cpu cortex-a72`로 부팅
3. 커널에 virtio 활성화(kernel-overlay) 필요 — 아니면 rootfs 마운트 불가
4. qemu(slirp 미포함) → 네트워크 대신 9p로 파일 교환
5. 이미지 inittab에 ttyAMA0 시리얼 getty 추가 필요(프로덕션은 SERIAL_CONSOLES)

## 한계
QEMU virt는 CPU/범용장치만 에뮬 → GPIO·카메라·GPU·센서 등 Pi 고유 HW 의존 테스트는 실물 보드 필요. 앱 로직/유저스페이스/파일시스템 회귀는 이 환경으로 커버.

## raspi4b 대화형 콘솔

QEMU 9.2와 `rpi4.wic`이 준비된 상태에서 다음 명령으로 Raspberry Pi
4B 시리얼 콘솔에 직접 접속한다.

```
bash poc/raspi4b/run-console.sh
```

최초 실행 시 원본 `rpi4.wic`을 보존하고 전용 512MiB 이미지
`poc/raspi4b/rpi4b-console.wic`을 생성한다. 이후 변경 사항은 이
콘솔용 이미지에 유지된다. 원본에서 다시 시작하려면 다음을 사용한다.

```
bash poc/raspi4b/run-console.sh --fresh
```

로그인 계정은 `root`이며 비밀번호는 없다. 정상 종료는 root 셸에서
`poweroff`를 실행한다. `Ctrl-a h`는 QEMU 키 도움말, `Ctrl-a c`는
시리얼 콘솔과 QEMU monitor 전환, `Ctrl-a x`는 강제 종료다.

## 재현 상세
대용량(sources/, build/, qemu-install/, *.wic 등)은 git 제외. 전체 진행 순서는 Jira BSP-17 코멘트 참고.
