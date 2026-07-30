# Raspberry Pi 4 PCIe/GENET patch series

- Upstream discussion: https://patchew.org/QEMU/20260725004219.66222-1-marcelomanzo@gmail.com/
- Downloaded and reviewed: 2026-07-30
- Target verified by this project: QEMU 11.0.2

Patches `0001` through `0019` preserve Marcelo Manzo's Patchew series as
individual Git-format patches.  `0020` is a project-local compatibility fix
for the Yocto Wrynose Raspberry Pi kernel, which waits for the complete
TDMA/RDMA disabled mask.

Validation status:

- all 20 patches apply to a clean QEMU 11.0.2 source tree;
- `qemu-system-aarch64` builds successfully;
- the `raspi4b` guest probes GENET and reports a 1 Gbps full-duplex link;
- TX DMA initializes and TX descriptors are consumed without NETDEV WATCHDOG;
- bidirectional TAP ping is not yet complete because TAP frames do not reach
  the GENET receive callback.

The upstream functional test in patch `0019` validates probe and `LOWER_UP`;
it does not transmit packets or verify ping.
