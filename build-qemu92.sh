#!/bin/bash
# Compatibility entry point. The fw branch now uses the latest stable QEMU.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
echo "build-qemu92.sh is deprecated; building the configured stable QEMU instead."
exec bash "$ROOT/build-qemu.sh"
