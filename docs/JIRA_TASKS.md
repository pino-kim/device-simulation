# RPi4 Yocto Wrynose/QEMU 호스트 자동화 작업

## EPIC: Docker 없는 RPi4 이미지 빌드 및 QEMU T1~T3 검증

### BSP-01 호스트 빌드 환경 기준 확정

- [ ] Ubuntu 24.04 필수 패키지 설치
- [ ] CPU, 메모리, 디스크 요구사항 확인
- [x] Yocto/BitBake를 일반 사용자로 실행
- [x] Python `pexpect`, `sfdisk`, `debugfs` 확인

완료 조건:

- 필수 명령과 라이브러리 사전 점검 통과
- Docker 없이 모든 스크립트를 실행할 수 있음

### BSP-02 Yocto Wrynose LTS 소스 준비 자동화

- [x] Wrynose 6.0.2 BitBake/OE-Core/meta-yocto 공식 아카이브 준비
- [x] `meta-raspberrypi` `wrynose` 준비
- [x] 소스 버전과 commit 출력
- [x] 기존 소스 재사용 시 불필요한 clone 방지

완료 조건:

- `setup-yocto.sh` 한 번으로 호환 레이어가 준비됨
- Yocto core와 BSP 레이어가 동일한 Wrynose 계열임

### BSP-03 RPi4 이미지 호스트 빌드

- [x] `MACHINE=raspberrypi4-64` 설정
- [x] `core-image-base` 빌드
- [x] 다운로드/sstate 캐시 경로 고정
- [x] WIC, 커널 Image, BCM2711 DTB 산출물 확인
- [x] 자동 테스트용 serial console 및 root login 설정

완료 조건:

- `build-image.sh`가 오류 없이 종료됨
- `Image`, `bcm2711-rpi-4-b.dtb`, `.wic`가 생성됨

### BSP-04 QEMU 테스트용 커널 레이어 구성

- [x] 별도 `meta-device-simulation` 레이어 생성
- [x] virtio-blk, virtio-pci, 9p 설정 built-in 적용
- [x] 특정 커널 버전에 종속되지 않는 bbappend 적용
- [x] 최종 커널 config 검증

완료 조건:

- T1/T2에서 WIC rootfs와 9p 공유를 마운트할 수 있음
- 설정이 Wrynose 레이어 호환성 검사를 통과함

### BSP-05 Stable QEMU 호스트 빌드

- [x] QEMU `11.0.2` 소스 준비
- [x] `aarch64-softmmu` target 빌드
- [x] libslirp가 있으면 사용자 모드 네트워크 포함, 없으면 네트워크 없이 빌드
- [x] 설치된 QEMU 버전 확인
- [x] `raspi4b` 머신 존재 확인

완료 조건:

- `qemu-install/bin/qemu-system-aarch64` 실행 가능
- `-machine help`에 `raspi4b`가 표시됨

### BSP-06 T1/T2 자동 테스트

- [ ] QEMU `virt`에서 Pi4 커널과 rootfs 부팅
- [ ] serial console root 로그인 자동화
- [ ] virtio-9p로 테스트 바이너리 전달
- [ ] 테스트 결과와 종료 코드 회수
- [ ] 전체 serial log 저장

완료 조건:

- 게스트가 로그인 프롬프트까지 부팅됨
- 테스트 실패가 호스트 프로세스 실패로 전달됨

### BSP-07 T3 raspi4b 자동 테스트

- [x] WIC 크기를 QEMU SD 제약에 맞게 조정
- [x] rootfs 파티션을 동적으로 탐색
- [x] 테스트 파일을 WIC에 주입
- [x] BCM2711 DTB와 `raspi4b` 머신으로 부팅
- [x] MMC rootfs, UART, Device Tree, SoC 노드 확인
- [x] 테스트 결과를 WIC에서 회수

완료 조건:

- QEMU `raspi4b`에서 테스트 전용 init 실행이 성공함
- BCM2711 모델과 MMC 장치가 게스트에서 확인됨
- 테스트 결과 및 종료 코드가 호스트에 회수됨

### BSP-08 문서화 및 CI 준비

- [ ] 전체 재현 명령 README 반영
- [ ] 프로덕션 이미지에서 test-only root login features 제거 조건 명시
- [ ] QEMU 미구현 장치와 T4 실물 테스트 범위 명시
- [ ] 빌드 산출물과 캐시 Git 제외
- [ ] CI timeout 및 artifact 보존 정책 정의

완료 조건:

- 신규 개발자가 README 순서만으로 빌드와 테스트 가능
- T1~T4 범위와 한계가 문서에 명확히 구분됨

## 주요 리스크

- x86_64 호스트에서 ARM64는 TCG로 실행되어 T3 부팅이 느림
- QEMU `raspi4b`는 PCIe, GENET Ethernet, PWM을 에뮬레이션하지 않음
- `meta-raspberrypi` Wrynose 변경에 따라 머신명이나 이미지 레이아웃 조정 가능
- T3는 `debugfs`로 WIC를 수정하므로 root 권한이 필요하지 않음
- 테스트 이미지의 root 무비밀번호 로그인은 프로덕션에 적용하면 안 됨
