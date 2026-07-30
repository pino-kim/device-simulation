#!/usr/bin/env bash
# Verify the BCM2838 PCIe root complex with a virtio-net-pci TAP endpoint.

set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"

export RPI4_NET_DEVICE=virtio-net-pci
export GUEST_IFACE="${GUEST_IFACE:-eth0}"
export TAP_IF="${TAP_IF:-rpi4pcie0}"
export HOST_CIDR="${HOST_CIDR:-192.168.78.1/24}"
export GUEST_CIDR="${GUEST_CIDR:-192.168.78.2/24}"
export GUEST_MAC="${GUEST_MAC:-52:54:00:12:34:78}"
export LOG="${LOG:-$PROJECT_ROOT/poc/raspi4b/pcie-network.log}"

exec "$PROJECT_ROOT/test-rpi4-tap-ping.sh" "$@"
