# main 브랜치 대비 변경 사항

> 보관 문서: 2026-08-02 당시 Kirkstone/QEMU 8.2·9.2 기반 브랜치 비교
> 기록이다. 현재 `fw`의 Wrynose 6.0.2/QEMU 11.0.3 구성 설명으로
> 사용하지 않는다. 최신 사용법과 검증 결과는 `docs/README.md`에서 찾는다.

작성일: 2026-08-02

비교 기준: `main` (`cd2d55f`) → `fw` (`9ad5eb7`)

이 문서는 `git diff main...fw`를 기준으로 `fw` 브랜치가 추가한 기능과
외부 호스트에서의 재현 조건을 정리한다. 문서 커밋 이후에는 `fw`의 최신
커밋 해시가 달라질 수 있다.

## 요약

`main`은 초기 프로젝트 구성을 제공한다. `fw`는 Raspberry Pi 4용 Yocto
이미지 빌드, QEMU `virt`/`raspi4b` 실행, 자동 테스트, 검증 기록 및
컨테이너화된 테스트 러너를 추가한다.

비교 시점 기준 변경 규모는 22개 파일, 1,749줄 추가, 25줄 삭제다.

## 기능별 차이

| 영역 | main | fw |
|---|---|---|
| Yocto 준비 | 없음 | kirkstone 소스 고정 및 부트스트랩 스크립트 |
| 이미지 빌드 | 없음 | `raspberrypi4-64`용 `core-image-base` 컨테이너 빌드 |
| 커널 설정 | 없음 | virtio block/PCI/9p 및 시리얼 콘솔 설정 레이어 |
| QEMU virt | 없음 | QEMU 8.2 빌드와 자동 부팅/테스트 하니스 |
| QEMU raspi4b | 기본 PoC만 존재 | QEMU 9.2 검증, 자동 테스트 및 대화형 콘솔 |
| 테스트 컨테이너 | 없음 | 표준/레거시 Dockerfile과 자동 이미지 빌드 |
| 검증 자료 | 없음 | 명령, 실행 로그, 제약 및 검증 보고서 |

## 주요 파일

- 빌드: `bootstrap-yocto.sh`, `build-yocto.sh`, `run-build.sh`,
  `prepare-image.sh`, `build-qemu.sh`
- Yocto 레이어: `meta-device-simulation/`
- 테스트 러너: `Dockerfile.test`, `Dockerfile.test.legacy`,
  `build-test-image.sh`, `.dockerignore`
- 테스트 하니스: `poc/run-poc.sh`, `poc/raspi4b/run-poc-raspi4b.sh`,
  `poc/raspi4b/run-console.sh`
- 당시 검증 문서: 현재 `docs/archive/kirkstone/`에 보관

## Ubuntu 24.04 외부 호스트 호환성

Ubuntu 24.04 x86_64 호스트와 현재 Docker Engine 환경에서는 실행할 수
있다. 테스트 컨테이너는 호스트 배포판에 의존하지 않고 Ubuntu 22.04로
고정되므로, Ubuntu 22.04에서 빌드한 QEMU 실행 파일의 glibc 및 공유
라이브러리 호환성을 유지한다.

필수 조건은 다음과 같다.

- x86_64 Linux 호스트
- Docker Engine (`ubuntu:22.04` 이미지를 처리할 수 있는 현재 버전 권장)
- Yocto 및 QEMU 소스를 내려받을 네트워크
- Yocto 빌드 산출물을 위한 충분한 디스크와 메모리
- raspi4b 이미지 주입 테스트에서 `--privileged` 컨테이너 실행 권한

외부 호스트의 기본 실행 순서는 다음과 같다.

```bash
./bootstrap-yocto.sh
./build-yocto.sh
./prepare-image.sh

docker run --rm --user 0 --security-opt seccomp=unconfined \
  -v "$PWD":/workdir -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh

./build-test-image.sh
bash poc/run-poc.sh
```

`build-test-image.sh`는 일반 Docker 환경에서 `Dockerfile.test`를 사용한다.
Docker 1.x에서는 이 저장소가 개발된 레거시 호스트를 위해
`Dockerfile.test.legacy`를 선택한다. 레거시 경로는 로컬에 미리 준비된
`qemu-runner:latest`가 필요하므로 외부 환경에서는 표준 경로를 사용해야
한다. 필요하면 다음처럼 Dockerfile을 명시할 수 있다.

```bash
TEST_DOCKERFILE=Dockerfile.test ./build-test-image.sh
```

## 확인된 범위와 남은 검증

현재 개발 호스트에서는 다음 항목을 확인했다.

- Docker 버전 자동 감지 및 레거시 Dockerfile 선택
- 테스트 이미지 빌드 성공
- 컨테이너 내부 QEMU 8.2.0 실행
- 컨테이너 내부 QEMU 9.2.0 실행
- 변경된 셸 스크립트 문법 및 `git diff --check`

Ubuntu 24.04 실호스트에서의 전체 Yocto 빌드와 게스트 부팅은 이 저장소의
현재 개발 호스트에서 직접 실행한 결과가 아니므로, 외부 호스트 CI 또는
별도 장비에서 한 번 더 검증해야 한다.

## 비교 명령

최신 차이는 다음 명령으로 다시 확인한다.

```bash
git log --oneline main..fw
git diff --stat main...fw
git diff --name-status main...fw
```
