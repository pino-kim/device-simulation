# QEMU 11.0.3 Raspberry Pi 4 PCIe/GENET review

## Scope

This review covers the 24 patches stored under
`qemu-patches/20260725-rpi4-pcie-genet`, their integration into the `fw`
container build, and runtime validation with the Wrynose 6.0.2 Raspberry Pi 4
image.

Tested components:

- QEMU 11.0.3, `raspi4b` revision 1.5
- Yocto Wrynose 6.0.2
- Linux 6.18.33-v8
- `bcm2711-rpi-4-b-qemu-console.dtb`
- UUID-portable `core-image-base` WIC

## Patch review

### Upstream proposal: patches 0001 through 0019

The first 19 patches preserve the proposed QEMU BCM2838 implementation as
individual mail patches. They add:

- the BCM2838 PCIe root complex and host bridge;
- PCIe MMIO regions, interrupts and raspi4b machine integration;
- the BCM2838 GENET device and register layout;
- MDIO and PHY state;
- GENET TX and RX descriptor DMA;
- interrupt and trace support;
- raspi4b functional test coverage.

The upstream functional test checks probe and carrier state. It does not prove
guest-to-host or host-to-guest packet delivery.

### Project fixes: patches 0020 through 0024

`0020` mirrors all DMA enable and ring-enable bits into the disabled-status
mask. Linux 6.18 checks the complete mask when stopping TDMA and RDMA.

`0021` maps host accesses for the root port's PCI configuration space.

`0022` translates the downstream PCIe MMIO window so a device BAR is reachable
at the address programmed by Linux.

`0023` preserves inherited PCIe root-port configuration callbacks. Calling the
plain PCI defaults prevented bridge window updates and caused an external abort
when a downstream virtio BAR was accessed. This patch was refreshed against
QEMU 11.0.3; the full series now applies with `--fuzz=0`.

`0024` sends unfiltered GENET traffic to logical RX ring 0 instead of inactive
register ring 16. It also adds RX DMA and IRQ traces used to diagnose packet
delivery.

## Build integration

`build-qemu.sh` retains the existing Ubuntu 22.04 container workflow and the
slirp/libusb build features. It now:

1. extracts a pristine QEMU 11.0.3 archive;
2. requires exactly 24 ordered patch files;
3. applies every patch with forward-only and zero-fuzz policy;
4. aborts on missing patches or a context mismatch;
5. configures, builds and installs `aarch64-softmmu` to `qemu-install`.

The patched build completed all 3,227 Ninja steps and installed
`qemu-system-aarch64`. The binary reported QEMU 11.0.3 and the `raspi4b`
revision 1.5 machine.

## Runtime validation

### Console and image regression

The original raspi4b T3 harness was rerun with the patched QEMU. Linux booted,
`/boot` mounted by filesystem UUID, the PL011 `ttyAMA0` login accepted input,
the guest test completed, and systemd powered off cleanly. Result:

```text
RESULT_OK: raspi4b PoC done
PASS: T3 raspi4b 테스트 통과
```

Poweroff completed at approximately 18.6 seconds, confirming that the former
`/dev/mmcblk0p1` 90-second wait did not regress.

### PCIe and GENET smoke test

`test-rpi4-network.sh` used a socket backend and verified the following guest
messages:

```text
brcm-pcie fd500000.pcie: PCI host bridge to bus 0000:00
brcm-pcie fd500000.pcie: link up, 2.5 GT/s PCIe x1 (!SSC)
bcmgenet fd580000.ethernet: GENET 5.0 EPHY: 0x0000
bcmgenet fd580000.ethernet eth0: Link is Up - 1Gbps/Full
```

No `failed to initialize DMA` message was observed. Result:

```text
PASS: raspi4b PCIe host bridge와 GENET eth0 초기화
```

### Native GENET TAP test

The test ran in an isolated user/network namespace with:

- host: `192.168.76.1/24`
- guest: `192.168.76.2/24`
- device: QEMU `bcm2838-genet`

Guest-to-host ping completed inside the guest automation. Host-to-guest ping
returned three of three replies with zero packet loss. Result:

```text
PASS: Guest(192.168.76.2) <-> Host(192.168.76.1) 양방향 ping
```

This validates MDIO/link state, TX descriptor consumption, RX ring 0, DMA to
guest memory and GENET interrupt delivery.

### PCIe virtio-net TAP test

The second namespace test attached `virtio-net-pci` behind `pcie.1`:

- host: `192.168.78.1/24`
- guest: `192.168.78.2/24`
- device: `virtio-net-pci,bus=pcie.1`

Both ping directions passed, with three of three host-to-guest replies and zero
packet loss:

```text
PASS: Guest(192.168.78.2) <-> Host(192.168.78.1) 양방향 ping
```

This specifically validates downstream PCI configuration access, bridge MMIO
window programming, BAR access and packet delivery through a PCIe endpoint.

## Known limitations

- QEMU still disables the unimplemented BCM2711 RNG200 and thermal nodes.
- The upstream functional test from patch 0019 was compiled into the source
  tree but was not run as part of this validation.
- The namespace tests validate host/guest L2 and IPv4 connectivity, not host
  NAT or Internet access.
- Physical PCIe passthrough is outside the scope of the emulated root complex.

## Reproduction

```sh
docker run --rm --user 0 --security-opt seccomp=unconfined \
  -v "$PWD":/workdir -w /workdir \
  crops/yocto:ubuntu-22.04-base \
  bash /workdir/build-qemu.sh

bash poc/raspi4b/run-poc-raspi4b.sh
BOOT_TIMEOUT=20 RPI4_NET_SOCKET=listen=:23460 ./test-rpi4-network.sh

unshare --user --map-root-user --net \
  env BOOT_TIMEOUT=90 ./test-rpi4-tap-ping.sh

unshare --user --map-root-user --net \
  env BOOT_TIMEOUT=90 ./test-rpi4-pcie-network.sh
```
