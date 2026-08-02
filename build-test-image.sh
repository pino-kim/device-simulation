#!/bin/bash
# Build the reproducible runtime image used by both QEMU test harnesses.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
IMAGE=${TEST_CONTAINER_IMAGE:-device-simulation-test:latest}
DOCKERFILE=${TEST_DOCKERFILE:-}

if [ -z "$DOCKERFILE" ]; then
    SERVER_VERSION=$(docker version --format '{{.Server.Version}}')
    case "$SERVER_VERSION" in
        1.*)
            DOCKERFILE=Dockerfile.test.legacy
            echo "Legacy Docker ${SERVER_VERSION}: using ${DOCKERFILE}"
            ;;
        *)
            DOCKERFILE=Dockerfile.test
            ;;
    esac
fi

case "$DOCKERFILE" in
    /*) ;;
    *) DOCKERFILE="${ROOT}/${DOCKERFILE}" ;;
esac

if [ ! -f "$DOCKERFILE" ]; then
    echo "Test Dockerfile not found: $DOCKERFILE" >&2
    exit 1
fi

docker build -f "$DOCKERFILE" -t "$IMAGE" "$ROOT"
