# QEMU raspi4b PCIe/GENET 시험 이식

## 출처와 적용 범위

- Patchew 시리즈: https://patchew.org/QEMU/20260725004219.66222-1-marcelomanzo@gmail.com/
- 대상: QEMU 11.0.2
- 적용: Patchew 19개 패치 전체와 프로젝트 로컬 DMA 상태 호환성 패치
- 관리: `qemu-patches/20260725-rpi4-pcie-genet/`의 개별 Git-format 패치

이 코드는 아직 upstream에 병합된 기능이 아니다. 시리즈의 functional
test는 GENET probe와 `LOWER_UP`만 확인하며 실제 패킷 왕복은 확인하지 않는다.

## 검토 중 확인한 문제

1. Patchew 19개 패치가 깨끗한 QEMU 11.0.2에 변경 없이 적용됨을 확인함.
2. 원본 GENET 모델은 TDMA status의 disabled bit를 이전 enable 값으로
   계산함.
3. Linux 6.18 드라이버는 DMA bit와 모든 ring-buffer bit가 disabled
   상태인지 확인하지만 원본 모델은 bit 0만 갱신함.
4. RDMA control write에 대응하는 status 갱신이 구현되지 않음.

2~4번을 로컬 20번 패치로 수정하여 TDMA/RDMA status가 control enable
mask의 반대 상태를 반환하게 함.

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

전용 TAP을 생성하고 Host와 Guest의 양방향 ping을 자동 검증하려면 다음을
실행한다. TAP 생성 때문에 sudo 권한이 필요하다.

```bash
./test-rpi4-tap-ping.sh
```

TAP 시험은 원본과 콘솔 DTB를 변경하지 않는다. Patchew 시리즈의 PHY
autonegotiation 수정으로 원본 MDIO 구성에서 1Gbps full-duplex Link Up을
확인한다.

Guest MAC은 `52:54:00:12:34:56`으로 고정하고 Host에 정적 neighbor를
설정한다. 테스트는 실패해도 로그를 남기며 성공으로 오인하지 않는다.

## 현재 한계

- PCIe root complex enumeration, GENET probe, Link Up 및 TX descriptor
  회수까지 검증함.
- TAP에서 QEMU GENET receive callback이 발생하지 않아 양방향 ping은
  현재 실패함.
- GENET migration state, endian이 다른 호스트 및 장시간 부하를 검증하지 않음.
- PCIe 하위 xHCI 모델은 이 패치에 포함되지 않아 실제 Pi 4 USB 토폴로지를
  완전하게 재현하지 않음.
