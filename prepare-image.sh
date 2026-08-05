#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEPLOY="${ROOT}/build/tmp/deploy/images/raspberrypi4-64"
SOURCE=$(find "$DEPLOY" -maxdepth 1 -type l \
    -name 'core-image-base-raspberrypi4-64*.wic.bz2' -print -quit)
TARGET="${ROOT}/rpi4.wic"
TEMP="${TARGET}.tmp"

if [ -z "$SOURCE" ] || [ ! -e "$SOURCE" ]; then
    echo "Built WIC image not found under: ${DEPLOY}" >&2
    echo "Run ./build-yocto.sh first." >&2
    exit 1
fi

trap 'rm -f "${TEMP}"' EXIT
bzip2 -dc "$SOURCE" > "$TEMP"
mv "$TEMP" "$TARGET"
trap - EXIT

echo "QEMU disk image is ready: ${TARGET}"
ls -lh "$TARGET"
