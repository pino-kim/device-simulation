# 미검증 항목 및 개선 필요 사항

> 보관 문서: Kirkstone/QEMU 8.2·9.2 기준의 미검증 목록이다. 네트워크와
> raspi4b PCIe 등 이후 완료된 항목도 포함하므로 현재 TODO로 사용하지
> 않는다. 현재 제한은 `docs/README.md`와 최신 검증 문서를 확인한다.

## 1. 실제 애플리케이션 테스트 미수행

`poc/testshare/myapp`이 없어서 실제 ARM64 애플리케이션과
`myapp --selftest`는 실행하지 않았다.

raspi4b 하니스에서도 `poc/raspi4b/testfiles/myapp`을 배치하지 않아
실제 애플리케이션 테스트는 수행하지 않았다.

현재 결과의 `PASS`는 QEMU 부팅, 로그인, 9p 마운트, 셸 테스트 및 결과
회수가 성공했다는 의미다.

## 2. 테스트 실패 전파가 엄격하지 않음

현재 `run-tests.sh`는 `myapp`이 없어도 PASS를 출력한다. 또한
`drive.expect`는 다음 파이프라인을 실행한다.

```text
sh /mnt/host/run-tests.sh 2>&1 | tee /mnt/host/result.txt
```

`run-tests.sh` 또는 `myapp`이 실패하더라도 마지막 `tee`가 성공하면
파이프라인이 성공으로 보일 수 있다. Expect 역시 테스트 종료 코드가
아니라 `TESTS_DONE` 문자열을 확인한다.

raspi4b 하니스 역시 `myapp`이 없어도 PASS를 출력하고 실제 테스트
종료 코드를 Expect까지 전달하지 않는다.

CI 품질 게이트로 사용하려면 다음 개선이 필요하다.

- `myapp` 부재를 실패로 처리
- `myapp --selftest` 종료 코드 보존
- 종료 코드를 Expect가 확인
- 실패 시 `RESULT_FAIL`과 non-zero 종료 코드 반환
- 성공할 때만 PASS 출력

## 3. distro 표시가 비어 있음

현재 결과에서 다음 값이 비어 있다.

```text
distro:
```

게스트의 `/etc/os-release` 형식과 현재 `grep PRETTY` 추출 방식을
확인해 수정할 필요가 있다. 부팅 성공 여부에는 영향을 주지 않는다.

## 4. Raspberry Pi 하드웨어 전체 에뮬레이션이 아님

현재는 `-M virt`를 사용한다. 다음 범위는 검증 대상이 아니다.

- BCM2711 전용 주변장치
- GPIO, I2C, SPI 실제 장치
- CSI 카메라
- VideoCore GPU
- Raspberry Pi 펌웨어와 부트로더
- 실제 SD 컨트롤러
- Bluetooth 및 Wi-Fi 하드웨어
- HAT와 외부 센서

부팅 중 RPi 전용 서비스가 `virt` 장치 트리에 없는 항목을 찾으면서
경고를 출력하지만 부팅과 현재 테스트에는 영향을 주지 않았다.

## 5. QEMU 다운로드 무결성

QEMU 버전과 URL은 8.2.0으로 고정돼 있지만 tarball SHA256 검사는 아직
없다. 공급망 검증을 위해 checksum 고정이 필요하다.

## 6. 빌드 도구 버전

QEMU 빌드에서 다음 명령을 사용한다.

```text
pip3 install --upgrade meson ninja
```

Meson과 Ninja 버전이 고정돼 있지 않아 시점에 따라 빌드 환경이 달라질
수 있다. 검증된 버전으로 고정하는 것이 바람직하다.

## 7. 컨테이너 이미지 digest

다음 이미지는 tag로만 지정돼 있다.

```text
crops/yocto:ubuntu-22.04-base
qemu-runner:latest
```

완전한 재현성이 필요하면 이미지 digest를 고정해야 한다.

## 8. 네트워크

현재 QEMU 8.2 빌드는 slirp를 포함하지 않으며 PoC 명령도 게스트
네트워크를 사용하지 않는다. 파일 교환은 9p로 수행한다. 네트워크
기능은 별도로 검증하지 않았다.

## 9. 신규 호스트 재현성

현재 호스트에서 전체 빌드와 실제 부팅은 성공했다. 완전히 새로운
호스트와 빈 캐시에서 다음 전체 절차를 연속 수행하는 검증은 아직
별도로 수행하지 않았다.

```text
bootstrap → Yocto build → WIC prepare → QEMU build → boot/test
```
