#!/usr/bin/env bash
# Yocto Wrynose LTS 릴리스 구성요소를 호스트에 준비한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

YOCTO_VERSION="${YOCTO_VERSION:-6.0.2}"
RPI_BRANCH="${RPI_BRANCH:-wrynose}"
RELEASE_URL="https://downloads.yoctoproject.org/releases/yocto/yocto-$YOCTO_VERSION"
RELEASE_CACHE="$SOURCES_DIR/release-$YOCTO_VERSION"

BITBAKE_ARCHIVE="bitbake-acfe02fa38b5da9e6a36c6cedcf91d4fcbefbfbd.tar.bz2"
OECORE_ARCHIVE="oecore-5d1aa5c806c061a2994f4decb59016610f093213.tar.bz2"
META_YOCTO_ARCHIVE="meta-yocto-24c24cef5d1523fefe43a3e3d34667b37ae551f3.tar.bz2"

require_command git
require_command curl
require_command sha256sum
require_command tar
mkdir -p "$SOURCES_DIR" "$RELEASE_CACHE"

download_release_file() {
    local filename="$1"
    if [[ ! -f "$RELEASE_CACHE/$filename" ]]; then
        curl --fail --location --output "$RELEASE_CACHE/$filename" \
            "$RELEASE_URL/$filename"
    fi
    if [[ ! -f "$RELEASE_CACHE/$filename.sha256sum" ]]; then
        curl --fail --location --output "$RELEASE_CACHE/$filename.sha256sum" \
            "$RELEASE_URL/$filename.sha256sum"
    fi
    (
        cd "$RELEASE_CACHE"
        sha256sum --check "$filename.sha256sum"
    )
}

if [[ ! -f "$POKY_DIR/oe-init-build-env" ]]; then
    download_release_file "$BITBAKE_ARCHIVE"
    download_release_file "$OECORE_ARCHIVE"
    download_release_file "$META_YOCTO_ARCHIVE"

    mkdir -p "$POKY_DIR"
    tar -C "$POKY_DIR" --strip-components=1 -xf "$RELEASE_CACHE/$OECORE_ARCHIVE"
    tar -C "$POKY_DIR" -xf "$RELEASE_CACHE/$BITBAKE_ARCHIVE"

    assembly_dir="$(mktemp -d)"
    trap 'rm -rf "$assembly_dir"' EXIT
    tar -C "$assembly_dir" -xf "$RELEASE_CACHE/$META_YOCTO_ARCHIVE"
    mv "$assembly_dir/meta-yocto/meta-poky" "$POKY_DIR/"
    mv "$assembly_dir/meta-yocto/meta-yocto-bsp" "$POKY_DIR/"
else
    echo "[skip] Yocto core가 이미 존재합니다: $POKY_DIR"
fi

if [[ ! -d "$RPI_LAYER_DIR/.git" ]]; then
    git clone --branch "$RPI_BRANCH" --depth 1 \
        https://git.yoctoproject.org/meta-raspberrypi "$RPI_LAYER_DIR"
else
    echo "[skip] meta-raspberrypi가 이미 존재합니다: $RPI_LAYER_DIR"
fi

echo
echo "Yocto 소스 준비 완료"
echo "Yocto release: $YOCTO_VERSION (Wrynose LTS)"
git -C "$RPI_LAYER_DIR" rev-parse --short HEAD
