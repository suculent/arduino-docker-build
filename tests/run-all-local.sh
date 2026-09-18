#!/usr/bin/env bash
#
# Run the build-chain tests against a locally built image.
#   ./tests/run-all-local.sh <image> [target ...]
# e.g.
#   ./tests/run-all-local.sh arduino-docker-build:latest esp8266 esp32
#   ./tests/run-all-local.sh arduino-docker-build:esp32   esp32
#
set -euo pipefail
IMAGE="${1:?usage: run-all-local.sh <image> [target ...]}"
shift
TARGETS=("$@")
[ ${#TARGETS[@]} -gt 0 ] || TARGETS=(esp8266 esp32)

for t in "${TARGETS[@]}"; do
  echo "=== ${IMAGE}: ${t} ==="
  docker run --rm --platform linux/amd64 "$IMAGE" "/opt/tests/build-${t}.sh"
done
echo "All build-chain tests passed for ${IMAGE}"
