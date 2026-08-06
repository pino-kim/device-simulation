# Raspberry Pi 4 PCIe/GENET patch series

- Upstream discussion: https://patchew.org/QEMU/20260725004219.66222-1-marcelomanzo@gmail.com/
- Downloaded and reviewed: 2026-07-30
- Original target verified by this project: QEMU 11.0.2
- Current `fw` target: QEMU 11.0.3

Patches `0001` through `0019` preserve Marcelo Manzo's Patchew series as
individual Git-format patches. Patches `0020` through `0024` are
project-local compatibility, PCIe mapping and GENET RX fixes.

Validation status:

- all 24 patches apply to clean QEMU 11.0.2 and 11.0.3 source trees;
- `qemu-system-aarch64` builds successfully;
- the `raspi4b` guest probes GENET and reports a 1 Gbps full-duplex link;
- TX DMA initializes and TX descriptors are consumed without NETDEV WATCHDOG;
- unfiltered packets use Linux's enabled logical RX queue 0;
- Guest-to-Host and Host-to-Guest TAP ping both pass.

The upstream functional test in patch `0019` validates probe and `LOWER_UP`;
it does not transmit packets or verify ping.
