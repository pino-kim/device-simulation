# 검수 및 재현 명령

모든 명령은 프로젝트 루트에서 실행한다.

## 1. Yocto 소스 준비

```bash
./bootstrap-yocto.sh
```

## 2. Yocto 이미지 빌드

```bash
./build-yocto.sh
```

## 3. QEMU용 WIC 준비

```bash
./prepare-image.sh
```

## 4. QEMU 8.2 빌드

기존 `build-qemu.sh`는 컨테이너 안의 `/workdir`을 기준으로 작성돼
있으므로 다음과 같이 실행한다.

```bash
docker run --rm --user 0 --security-opt seccomp=unconfined \
  -v "$PWD":/workdir \
  -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh
```

## 5. QEMU 버전 확인

먼저 테스트 러너 이미지를 빌드한다.

```bash
./build-test-image.sh
```

```bash
docker run --rm --security-opt seccomp=unconfined \
  -v "$PWD":/workdir \
  device-simulation-test:latest \
  /workdir/qemu-install/bin/qemu-system-aarch64 --version
```

기대 결과:

```text
QEMU emulator version 8.2.0
```

## 6. virt 머신 확인

```bash
docker run --rm --security-opt seccomp=unconfined \
  -v "$PWD":/workdir \
  device-simulation-test:latest \
  /workdir/qemu-install/bin/qemu-system-aarch64 -machine help
```

기대 항목:

```text
virt       QEMU 8.2 ARM Virtual Machine (alias of virt-8.2)
virt-8.2   QEMU 8.2 ARM Virtual Machine
```

## 7. 실제 부팅 및 자동 테스트

```bash
bash poc/run-poc.sh
```

기대 결과:

```text
MOUNT_OK
TESTS_DONE
RESULT_OK: PoC done -> poc/testshare/result.txt
```

결과 파일:

```text
poc/testshare/result.txt
```

## 8. 애플리케이션을 포함한 실행

ARM64 실행 파일을 다음 위치에 둔다.

```bash
cp <ARM64 실행 파일> poc/testshare/myapp
chmod +x poc/testshare/myapp
bash poc/run-poc.sh
```

현재 테스트 스크립트는 다음 명령으로 애플리케이션을 호출한다.

```text
/mnt/host/myapp --selftest
```

## 9. 정적 검사

```bash
bash -n \
  bootstrap-yocto.sh \
  build-yocto.sh \
  build-qemu.sh \
  build-test-image.sh \
  prepare-image.sh \
  poc/run-poc.sh \
  poc/testshare/run-tests.sh

git diff --check
git status --short
```
