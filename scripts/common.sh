#!/usr/bin/env bash

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES_DIR="${SOURCES_DIR:-$PROJECT_ROOT/sources}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_ROOT/build}"
POKY_DIR="${POKY_DIR:-$SOURCES_DIR/poky}"
RPI_LAYER_DIR="${RPI_LAYER_DIR:-$SOURCES_DIR/meta-raspberrypi}"
CUSTOM_LAYER_DIR="$PROJECT_ROOT/meta-device-simulation"
DEPLOY_DIR="$BUILD_DIR/tmp/deploy/images/raspberrypi4-64"
QEMU_VERSION="${QEMU_VERSION:-11.0.2}"
QEMU_PREFIX="${QEMU_PREFIX:-$PROJECT_ROOT/qemu-install}"
QEMU_BIN="${QEMU_BIN:-$QEMU_PREFIX/bin/qemu-system-aarch64}"

die() {
    echo "ERROR: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "필수 명령을 찾을 수 없습니다: $1"
}

find_single_artifact() {
    local pattern="$1"
    local result
    result="$(find "$DEPLOY_DIR" -maxdepth 1 -type f -name "$pattern" ! -type l | sort | tail -n 1)"
    [[ -n "$result" ]] || die "빌드 산출물을 찾을 수 없습니다: $DEPLOY_DIR/$pattern"
    printf '%s\n' "$result"
}
