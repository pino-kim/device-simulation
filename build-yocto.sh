#!/bin/bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${YOCTO_CONTAINER_IMAGE:-crops/yocto:ubuntu-22.04-base}

if [ ! -f "${ROOT}/sources/oe-core/oe-init-build-env" ]; then
    echo "Yocto sources are missing. Run ./bootstrap-yocto.sh first." >&2
    exit 1
fi

docker run --rm \
    --security-opt seccomp=unconfined \
    --user "$(id -u):$(id -g)" \
    -e HOME=/tmp/yocto-home \
    -v "${ROOT}:/workdir" \
    -w /workdir \
    "${IMAGE}" \
    bash -c 'mkdir -p "$HOME" && exec bash /workdir/run-build.sh'
