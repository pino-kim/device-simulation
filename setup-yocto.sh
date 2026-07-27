#!/usr/bin/env bash
# Yocto Wrynose LTS 소스를 호스트에 준비한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

POKY_TAG="${POKY_TAG:-yocto-6.0.2}"
RPI_BRANCH="${RPI_BRANCH:-wrynose}"

require_command git
mkdir -p "$SOURCES_DIR"

if [[ ! -d "$POKY_DIR/.git" ]]; then
    git clone --branch "$POKY_TAG" --depth 1 \
        https://git.yoctoproject.org/poky "$POKY_DIR"
else
    echo "[skip] poky가 이미 존재합니다: $POKY_DIR"
fi

if [[ ! -d "$RPI_LAYER_DIR/.git" ]]; then
    git clone --branch "$RPI_BRANCH" --depth 1 \
        https://git.yoctoproject.org/meta-raspberrypi "$RPI_LAYER_DIR"
else
    echo "[skip] meta-raspberrypi가 이미 존재합니다: $RPI_LAYER_DIR"
fi

echo
echo "Yocto 소스 준비 완료"
git -C "$POKY_DIR" describe --always --tags
git -C "$RPI_LAYER_DIR" rev-parse --short HEAD
