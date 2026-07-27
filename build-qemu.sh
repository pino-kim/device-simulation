#!/usr/bin/env bash
# 호스트에서 Raspberry Pi 4 모델을 포함한 stable QEMU를 빌드한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

ARCHIVE="$PROJECT_ROOT/qemu-$QEMU_VERSION.tar.xz"
SOURCE="$PROJECT_ROOT/qemu-$QEMU_VERSION"
BUILD="$PROJECT_ROOT/qemu-$QEMU_VERSION-build"
URL="https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz"

for command in curl tar python3 ninja pkg-config gcc; do
    require_command "$command"
done

if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --continue-at - --output "$ARCHIVE" "$URL"
fi

if [[ ! -d "$SOURCE" ]]; then
    tar -C "$PROJECT_ROOT" -xf "$ARCHIVE"
fi

mkdir -p "$BUILD"
cd "$BUILD"
"$SOURCE/configure" \
    --target-list=aarch64-softmmu \
    --prefix="$QEMU_PREFIX" \
    --enable-slirp \
    --disable-docs \
    --disable-gtk \
    --disable-sdl \
    --disable-vnc
ninja -j "${QEMU_BUILD_JOBS:-$(nproc)}"
ninja install

"$QEMU_BIN" --version | head -n 1
"$QEMU_BIN" -machine help | grep -q '^raspi4b ' ||
    die "빌드된 QEMU에 raspi4b 머신이 없습니다."
echo "QEMU 설치 완료: $QEMU_PREFIX"
