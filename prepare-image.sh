#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOY="${ROOT}/build/tmp/deploy/images/raspberrypi4-64"
SOURCE="${DEPLOY}/core-image-base-raspberrypi4-64.wic.gz"
TARGET="${ROOT}/rpi4.wic"
TEMP="${TARGET}.tmp"

if [ ! -f "${SOURCE}" ]; then
    echo "Built WIC image not found: ${SOURCE}" >&2
    echo "Run ./build-yocto.sh first." >&2
    exit 1
fi

trap 'rm -f "${TEMP}"' EXIT
gzip -dc "${SOURCE}" > "${TEMP}"
mv "${TEMP}" "${TARGET}"
trap - EXIT

echo "QEMU disk image is ready: ${TARGET}"
ls -lh "${TARGET}"
