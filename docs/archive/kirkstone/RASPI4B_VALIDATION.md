# QEMU raspi4b 검수 보고서

> 보관 문서: Yocto Kirkstone, Linux 5.15.92 및 QEMU 9.2.0을 대상으로 한
> 2026-07-31 검수 결과다. 현재 Wrynose 6.0.2/Linux 6.18.33/QEMU 11.0.3
> 검증 결과와 혼용하지 않는다.

## 1. 검수 기준

- 검수일: 2026-07-31
- QEMU: 9.2.0
- 머신: `raspi4b` (Raspberry Pi 4B revision 1.5)
- 커널: Yocto Linux 5.15.92-v8
- DTB: `bcm2711-rpi-4-b.dtb`
- 디스크: 512MiB로 확장한 WIC SD 이미지
- 하니스: `poc/raspi4b/run-poc-raspi4b.sh`

## 2. 종합 판정

다음 전체 흐름을 실제 실행으로 검증했다.

```text
QEMU 9.2 빌드
  → raspi4b 머신 확인
  → WIC를 512MiB SD 이미지로 준비
  → rootfs에 테스트 파일 주입
  → Raspberry Pi 4B/BCM2711 부팅
  → root 로그인 및 테스트 실행
  → SD rootfs에 결과 기록
  → 정상 poweroff
  → 호스트에서 결과 회수
```

최종 결과:

```text
RESULT_OK: raspi4b PoC done
PASS: T3 raspi4b 테스트 통과
```

## 3. QEMU 빌드와 머신 지원

`build-qemu92.sh`의 전체 2964개 빌드 단계와 설치가 완료됐다.

```text
Run-time dependency slirp found: YES 4.6.1
QEMU emulator version 9.2.0
raspi4b  Raspberry Pi 4B (revision 1.5)
```

설치 파일:

```text
qemu92-install/bin/qemu-system-aarch64
```

`qemu-runner:latest`에는 Expect와 libslirp가 있고 QEMU 실행 파일은
없다. 프로젝트의 `qemu92-install/`을 컨테이너의 `/workdir` 아래에
연결해 QEMU 9.2 버전과 `raspi4b` 머신 지원을 다시 확인했다.

## 4. SD 이미지와 테스트 주입

기존 `rpi4.wic`을 복제하고 QEMU raspi4b SD 크기 조건에 맞춰
512MiB로 확장했다.

```text
rpi4.wic
  → poc/raspi4b/rpi4b-test.wic
  → truncate -s 512M
```

두 번째 파티션 시작 위치:

```text
155648 sectors × 512 bytes = 79691776 bytes
```

하니스는 이 오프셋으로 rootfs를 loop mount하고 다음 경로에 테스트를
주입했다.

```text
/home/root/hosttest/
```

`raspi4b` 경로에서는 9p 대신 부팅 전·후 SD rootfs를 직접 마운트해
테스트 파일과 결과를 교환한다.

## 5. 실제 QEMU 구성

핵심 실행 옵션:

```text
-M raspi4b
-cpu cortex-a72
-m 2G
-nographic
-no-reboot
-kernel Image-raspberrypi4-64.bin
-dtb bcm2711-rpi-4-b.dtb
-drive file=rpi4b-test.wic,format=raw,if=sd
-append "console=ttyAMA0,115200 earlycon=pl011,0xfe201000
         root=/dev/mmcblk1p2 rootwait rw"
```

`virt` 부팅과 달리 BCM2711 DTB, RPi4 PL011 주소, SD/MMC rootfs 경로를
사용한다.

## 6. 실제 게스트 증적

커널과 아키텍처:

```text
Linux raspberrypi4-64 5.15.92-v8 ... aarch64 GNU/Linux
```

장치 트리 모델:

```text
Raspberry Pi 4 Model B
```

확인된 BCM2711 관련 노드:

```text
dma-ranges
dma@7e007000
gpio@7e200000
gpiomem
mailbox@7e00b840
mailbox@7e00b880
mmc@7e202000
mmc@7e300000
mmcnr@7e300000
serial@7e201000
serial@7e201400
serial@7e201600
serial@7e201800
serial@7e201a00
serial@7e215040
```

확인된 SD/MMC 장치:

```text
/dev/mmcblk1
/dev/mmcblk1p1
/dev/mmcblk1p2
```

정상 종료:

```text
EXT4-fs (mmcblk1p2): re-mounted
reboot: Power down
RESULT_OK: raspi4b PoC done
```

## 7. 회수한 테스트 결과

```text
=== [raspi4b/T3] 게스트 자동테스트 시작 ===
uname   : Linux raspberrypi4-64 5.15.92-v8 ... aarch64 GNU/Linux
machine : Raspberry Pi 4 Model B
-- SoC 커널 노드(BCM2711 확인) --
dma-ranges dma@7e007000 gpio@7e200000 gpiomem mailbox@7e00b840 ...
-- MMC/블록 디바이스 --
/dev/mmcblk1 /dev/mmcblk1p1 /dev/mmcblk1p2
(myapp 없음 — testfiles/에 바이너리를 두면 여기서 실행)
PASS: T3 raspi4b 테스트 통과
=== 종료 ===
```

## 8. 적용한 수정

기존 하니스에 고정된 `/data/yocto-rpi4` 경로가 있어 현재 프로젝트
위치에서는 그대로 실행할 수 없었다. 스크립트 자신의 위치를 기준으로
프로젝트 루트를 계산하도록 수정했다.

```bash
BASE=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
```

`qemu-runner:latest`에 QEMU 9.2가 들어 있다는 잘못된 주석도 QEMU는
`qemu92-install/`에서 마운트한다는 설명으로 수정했다.

## 9. 검증 한계

- `myapp`을 배치하지 않아 실제 애플리케이션 self-test는 미수행
- 현재 테스트는 `myapp`이 없어도 PASS를 출력
- 테스트 종료 코드가 Expect까지 엄격히 전파되지 않음
- GPIO 등 주변장치 노드의 존재는 확인했지만 기능적 I/O는 미검증
- 실제 Raspberry Pi 펌웨어 부팅 과정은 미검증
- 네트워크 기능은 미검증

## 10. 결론

QEMU 9.2 `raspi4b` 머신을 이용한 BCM2711 수준 부팅, SD/MMC rootfs,
테스트 주입·실행·회수 하니스는 현재 환경에서 정상 동작한다.

이 PASS는 Raspberry Pi 4B 장치 트리와 SD/MMC 경로를 포함한 부팅
smoke test 결과이며 실제 애플리케이션이나 모든 주변장치 기능의
검증을 의미하지 않는다.

## 11. 대화형 콘솔 검증

`poc/raspi4b/run-console.sh --fresh`로 별도의 512MiB 콘솔용 SD
이미지를 만들고 대화형 터미널에서 직접 로그인했다.

```text
raspberrypi4-64 login: root
root@raspberrypi4-64:~#
```

로그인 후 실제 확인 결과:

```text
$ uname -m
aarch64

$ cat /proc/device-tree/model
Raspberry Pi 4 Model B

$ ls /dev/mmcblk*
/dev/mmcblk1 /dev/mmcblk1p1 /dev/mmcblk1p2
```

root 셸에서 `poweroff`를 실행했으며 다음 로그와 QEMU 종료 코드 0을
확인했다.

```text
EXT4-fs (mmcblk1p2): re-mounted
kvm: exiting hardware virtualization
reboot: Power down
```
