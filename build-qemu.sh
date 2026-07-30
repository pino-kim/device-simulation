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

RASPI4_NET_PATCH_DIR="$PROJECT_ROOT/qemu-patches/20260725-rpi4-pcie-genet"
RASPI4_NET_PATCH_STAMP="$SOURCE/.device-simulation-patchew-20260725"
RASPI4_NET_LOCAL_STAMP="$SOURCE/.device-simulation-genet-dma-status-v1"
RASPI4_PCIE_CFG_STAMP="$SOURCE/.device-simulation-pcie-config-v1"
RASPI4_PCIE_MMIO_STAMP="$SOURCE/.device-simulation-pcie-mmio-v1"
RASPI4_PCIE_HOOKS_STAMP="$SOURCE/.device-simulation-pcie-config-hooks-v1"
RASPI4_GENET_RX_STAMP="$SOURCE/.device-simulation-genet-rx-v1"
shopt -s nullglob
RASPI4_NET_PATCHES=("$RASPI4_NET_PATCH_DIR"/*.patch)
shopt -u nullglob
[[ ${#RASPI4_NET_PATCHES[@]} -eq 24 ]] ||
    die "PCIe/GENET 패치 24개를 찾을 수 없습니다: $RASPI4_NET_PATCH_DIR"

if [[ -f "$RASPI4_NET_PATCH_STAMP" ]]; then
    echo "Patchew Raspberry Pi 4 PCIe/GENET 패치가 이미 적용되어 있습니다."
else
    for raspi4_net_patch in "${RASPI4_NET_PATCHES[@]:0:19}"; do
        if ! patch --batch --forward --dry-run --silent -d "$SOURCE" -p1 \
            < "$raspi4_net_patch"; then
            die "Patchew 패치를 QEMU $QEMU_VERSION 소스에 적용할 수 없습니다: $(basename "$raspi4_net_patch")"
        fi
        echo "적용: $(basename "$raspi4_net_patch")"
        patch --batch --forward --silent -d "$SOURCE" -p1 \
            < "$raspi4_net_patch"
    done
    touch "$RASPI4_NET_PATCH_STAMP"
fi

if [[ -f "$RASPI4_PCIE_MMIO_STAMP" ]]; then
    echo "PCIe MMIO 변환 패치가 이미 적용되어 있습니다."
else
    raspi4_net_patch="${RASPI4_NET_PATCHES[21]}"
    if ! patch --batch --forward --dry-run --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"; then
        die "PCIe MMIO 패치를 적용할 수 없습니다: $(basename "$raspi4_net_patch")"
    fi
    echo "적용: $(basename "$raspi4_net_patch")"
    patch --batch --forward --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"
    touch "$RASPI4_PCIE_MMIO_STAMP"
fi

if [[ -f "$RASPI4_PCIE_CFG_STAMP" ]]; then
    echo "PCIe Root Port config-space 패치가 이미 적용되어 있습니다."
else
    raspi4_net_patch="${RASPI4_NET_PATCHES[20]}"
    if ! patch --batch --forward --dry-run --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"; then
        die "PCIe config-space 패치를 적용할 수 없습니다: $(basename "$raspi4_net_patch")"
    fi
    echo "적용: $(basename "$raspi4_net_patch")"
    patch --batch --forward --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"
    touch "$RASPI4_PCIE_CFG_STAMP"
fi

if [[ -f "$RASPI4_PCIE_HOOKS_STAMP" ]]; then
    echo "PCIe Root Port config hook 패치가 이미 적용되어 있습니다."
else
    raspi4_net_patch="${RASPI4_NET_PATCHES[22]}"
    if ! patch --batch --forward --dry-run --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"; then
        die "PCIe config hook 패치를 적용할 수 없습니다: $(basename "$raspi4_net_patch")"
    fi
    echo "적용: $(basename "$raspi4_net_patch")"
    patch --batch --forward --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"
    touch "$RASPI4_PCIE_HOOKS_STAMP"
fi

if [[ -f "$RASPI4_NET_LOCAL_STAMP" ]]; then
    echo "GENET DMA 상태 호환성 패치가 이미 적용되어 있습니다."
else
    raspi4_net_patch="${RASPI4_NET_PATCHES[19]}"
    if ! patch --batch --forward --dry-run --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"; then
        die "GENET DMA 상태 패치를 적용할 수 없습니다: $(basename "$raspi4_net_patch")"
    fi
    echo "적용: $(basename "$raspi4_net_patch")"
    patch --batch --forward --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"
    touch "$RASPI4_NET_LOCAL_STAMP"
fi

if [[ -f "$RASPI4_GENET_RX_STAMP" ]]; then
    echo "GENET 기본 RX ring 패치가 이미 적용되어 있습니다."
else
    raspi4_net_patch="${RASPI4_NET_PATCHES[23]}"
    if ! patch --batch --forward --dry-run --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"; then
        die "GENET 기본 RX ring 패치를 적용할 수 없습니다: $(basename "$raspi4_net_patch")"
    fi
    echo "적용: $(basename "$raspi4_net_patch")"
    patch --batch --forward --silent -d "$SOURCE" -p1 \
        < "$raspi4_net_patch"
    touch "$RASPI4_GENET_RX_STAMP"
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
