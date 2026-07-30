#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCES="${ROOT}/sources"

POKY_REV=393064579dfdd0ed2d4ed4c27d238d7d2292c08b
META_RPI_REV=255500dd9f6a01a3445ac491d1abc401801e3bad
META_OE_REV=ce8539c941f6fcbecaca4d16640ac105c0595589

clone_at_revision() {
    local url=$1
    local directory=$2
    local revision=$3

    if [ ! -d "${directory}/.git" ]; then
        git clone --branch kirkstone --single-branch "${url}" "${directory}"
    fi

    git -C "${directory}" checkout "${revision}"
}

mkdir -p "${SOURCES}"
clone_at_revision https://git.yoctoproject.org/poky \
    "${SOURCES}/poky" "${POKY_REV}"
clone_at_revision https://github.com/agherzan/meta-raspberrypi.git \
    "${SOURCES}/meta-raspberrypi" "${META_RPI_REV}"
clone_at_revision https://git.openembedded.org/meta-openembedded \
    "${SOURCES}/meta-openembedded" "${META_OE_REV}"

echo "Yocto kirkstone sources are ready in ${SOURCES}"
