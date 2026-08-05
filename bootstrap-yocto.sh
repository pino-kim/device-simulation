#!/bin/bash
# Prepare the official Yocto Wrynose release without cloning poky.git.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCES="${ROOT}/sources"
YOCTO_VERSION=${YOCTO_VERSION:-6.0.2}
RPI_BRANCH=${RPI_BRANCH:-wrynose}
RELEASE_URL="https://downloads.yoctoproject.org/releases/yocto/yocto-${YOCTO_VERSION}"
RELEASE_DIR="${SOURCES}/release-${YOCTO_VERSION}"
OECORE_DIR="${SOURCES}/oe-core"
META_YOCTO_DIR="${SOURCES}/meta-yocto"
META_RPI_DIR="${SOURCES}/meta-raspberrypi"

BITBAKE_ARCHIVE=bitbake-acfe02fa38b5da9e6a36c6cedcf91d4fcbefbfbd.tar.bz2
OECORE_ARCHIVE=oecore-5d1aa5c806c061a2994f4decb59016610f093213.tar.bz2
META_YOCTO_ARCHIVE=meta-yocto-24c24cef5d1523fefe43a3e3d34667b37ae551f3.tar.bz2

for command in curl git sha256sum tar; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Required command not found: $command" >&2
        exit 1
    }
done

mkdir -p "$SOURCES" "$RELEASE_DIR"

download_release_file() {
    local filename=$1
    if [ ! -f "$RELEASE_DIR/$filename" ]; then
        curl --fail --location --output "$RELEASE_DIR/$filename" \
            "$RELEASE_URL/$filename"
    fi
    if [ ! -f "$RELEASE_DIR/$filename.sha256sum" ]; then
        curl --fail --location --output "$RELEASE_DIR/$filename.sha256sum" \
            "$RELEASE_URL/$filename.sha256sum"
    fi
    (cd "$RELEASE_DIR" && sha256sum --check "$filename.sha256sum")
}

download_release_file "$BITBAKE_ARCHIVE"
download_release_file "$OECORE_ARCHIVE"
download_release_file "$META_YOCTO_ARCHIVE"

if [ ! -f "$OECORE_DIR/oe-init-build-env" ]; then
    mkdir -p "$OECORE_DIR"
    tar -C "$OECORE_DIR" --strip-components=1 \
        -xf "$RELEASE_DIR/$OECORE_ARCHIVE"
    tar -C "$OECORE_DIR" -xf "$RELEASE_DIR/$BITBAKE_ARCHIVE"
fi

if [ ! -d "$META_YOCTO_DIR/meta-poky" ]; then
    mkdir -p "$META_YOCTO_DIR"
    tar -C "$META_YOCTO_DIR" --strip-components=1 \
        -xf "$RELEASE_DIR/$META_YOCTO_ARCHIVE"
fi

if [ ! -d "$META_RPI_DIR/.git" ]; then
    git clone --branch "$RPI_BRANCH" --depth 1 \
        https://git.yoctoproject.org/meta-raspberrypi "$META_RPI_DIR"
fi

echo "Yocto ${YOCTO_VERSION} Wrynose sources are ready."
echo "OE-Core: $OECORE_DIR"
echo "BitBake: $OECORE_DIR/bitbake"
echo "meta-yocto: $META_YOCTO_DIR"
git -C "$META_RPI_DIR" rev-parse --short HEAD
