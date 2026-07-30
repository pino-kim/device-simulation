#!/usr/bin/env bash
# 호스트에서 Raspberry Pi 4 모델을 포함한 stable QEMU를 빌드한다.

set -euo pipefail
source "$(cd "$(dirname "$0")" && pwd)/scripts/common.sh"

ARCHIVE="$PROJECT_ROOT/qemu-$QEMU_VERSION.tar.xz"
SOURCE="$PROJECT_ROOT/qemu-$QEMU_VERSION"
BUILD="$PROJECT_ROOT/qemu-$QEMU_VERSION-build"
URL="https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz"

for command in curl tar patch python3 pkg-config gcc; do
    require_command "$command"
done

if command -v ninja >/dev/null 2>&1; then
    NINJA_BIN="$(command -v ninja)"
elif [[ -x "$BUILD_DIR/tmp/sysroots-components/x86_64/ninja-native/usr/bin/ninja" ]]; then
    NINJA_BIN="$BUILD_DIR/tmp/sysroots-components/x86_64/ninja-native/usr/bin/ninja"
    export PATH="$(dirname "$NINJA_BIN"):$PATH"
    echo "Yocto가 빌드한 Ninja를 재사용합니다: $NINJA_BIN"
else
    die "Ninja를 찾을 수 없습니다. 먼저 ./build-image.sh를 실행하거나 ninja-build를 설치하십시오."
fi

if [[ ! -f "$ARCHIVE" ]]; then
    curl --fail --location --continue-at - --output "$ARCHIVE" "$URL"
fi

if [[ ! -d "$SOURCE" ]]; then
    tar -C "$PROJECT_ROOT" -xf "$ARCHIVE"
fi

RASPI4_NET_PATCH="$PROJECT_ROOT/qemu-patches/0001-raspi4b-pcie-genet-wip-v6-qemu-11.patch"
if [[ -f "$RASPI4_NET_PATCH" ]]; then
    if patch --batch --forward --dry-run --silent -d "$SOURCE" -p1 \
        < "$RASPI4_NET_PATCH"; then
        echo "Raspberry Pi 4 PCIe/GENET 시험 패치를 적용합니다."
        patch --batch --forward --silent -d "$SOURCE" -p1 \
            < "$RASPI4_NET_PATCH"
    elif patch --batch --dry-run --silent --reverse -d "$SOURCE" -p1 \
        < "$RASPI4_NET_PATCH"; then
        echo "Raspberry Pi 4 PCIe/GENET 시험 패치가 이미 적용되어 있습니다."
    else
        die "PCIe/GENET 패치를 QEMU $QEMU_VERSION 소스에 적용할 수 없습니다."
    fi
fi

mkdir -p "$BUILD"
cd "$BUILD"
SLIRP_OPTION="--disable-slirp"
if pkg-config --exists slirp; then
    SLIRP_OPTION="--enable-slirp"
else
    echo "libslirp 개발 패키지가 없어 사용자 모드 네트워크 없이 빌드합니다."
    echo "현재 T1/T2/T3 시리얼·디스크 검증에는 네트워크가 필요하지 않습니다."
fi
"$SOURCE/configure" \
    --target-list=aarch64-softmmu \
    --prefix="$QEMU_PREFIX" \
    "$SLIRP_OPTION" \
    --disable-docs \
    --disable-gtk \
    --disable-sdl \
    --disable-vnc
"$NINJA_BIN" -j "${QEMU_BUILD_JOBS:-$(nproc)}"
"$NINJA_BIN" install

"$QEMU_BIN" --version | head -n 1
"$QEMU_BIN" -machine help | grep -q '^raspi4b ' ||
    die "빌드된 QEMU에 raspi4b 머신이 없습니다."
echo "QEMU 설치 완료: $QEMU_PREFIX"
