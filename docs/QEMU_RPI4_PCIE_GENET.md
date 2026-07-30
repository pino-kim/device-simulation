# QEMU raspi4b PCIe/GENET 시험 이식

## 출처와 적용 범위

- QEMU 이슈: https://gitlab.com/qemu-project/qemu/-/issues/2547
- WIP v6: https://patchew.org/QEMU/20240226000259.2752893-1-sergey.kambalin@auriga.com/
- 대상: QEMU 11.0.2
- 적용: v6의 PCIe 13~15번 및 GENET 19~29번에 해당하는 장치 모델
- 제외: 이미 upstream에 반영된 raspi4b 기반부, RNG200, thermal, 테스트 코드

이 코드는 upstream에서 완성 또는 병합된 기능이 아니다. QEMU v6 시리즈
작성자도 GENET 통합 테스트가 개발 중이라고 명시했다.

## 검토 중 확인한 문제

1. QEMU 11.0.2에서 이동한 헤더 경로와 reset/property API를 사용하도록
   변경함.
2. 원본 PCIe 리뷰에서 지적된 주석과 타입 등록 방식은 기능에 직접 영향을
   주지 않아 이번 시험 이식에서는 최소 변경만 수행함.
3. 원본 GENET 모델은 TDMA status의 disabled bit를 이전 enable 값으로
   계산함.
4. Linux 6.18 드라이버는 DMA bit와 모든 ring-buffer bit가 disabled
   상태인지 확인하지만 원본 모델은 bit 0만 갱신함.
5. RDMA control write에 대응하는 status 갱신이 구현되지 않음.

3~5번을 수정하여 TDMA/RDMA status가 control enable mask의 반대 상태를
반환하게 하고 reset 직후 모든 DMA/ring을 disabled 상태로 초기화함.

## 재현

```bash
./build-qemu.sh
./test-rpi4-network.sh
```

성공 조건은 다음과 같다.

```text
brcm-pcie ... PCI host bridge to bus 0000:00
bcmgenet ... GENET 5.0
bcmgenet ... eth0: Link is Down
```

소켓 peer를 붙이지 않은 smoke test에서는 `Link is Down`이 정상이다.
`failed to initialize DMA`가 없어야 한다.

대화형 시험:

```bash
RPI4_NET_MODE=socket RESET_WIC=1 ./run-rpi4-console.sh
```

slirp를 포함해 QEMU를 빌드한 호스트의 사용자 네트워크 시험:

```bash
RPI4_NET_MODE=user RESET_WIC=1 ./run-rpi4-console.sh
```

## 현재 한계

- PCIe root complex enumeration과 GENET `eth0` probe까지 검증함.
- socket backend의 실제 frame TX/RX와 slirp 외부 통신은 아직 검증하지 않음.
- GENET migration state, endian이 다른 호스트 및 장시간 부하를 검증하지 않음.
- PCIe 하위 xHCI 모델은 이 패치에 포함되지 않아 실제 Pi 4 USB 토폴로지를
  완전하게 재현하지 않음.
