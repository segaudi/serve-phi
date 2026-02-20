#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker is required to build this image locally."
  exit 1
fi

IMAGE_TAG="${IMAGE_TAG:-serve-phi-onepod:latest}"

echo "Building one-pod image: ${IMAGE_TAG}"
docker build -t "${IMAGE_TAG}" .

if [[ "${PUSH_IMAGE:-0}" == "1" ]]; then
  echo "Pushing image: ${IMAGE_TAG}"
  docker push "${IMAGE_TAG}"
fi

cat <<EOF
Image build complete.

Next:
1) Push this image to Docker Hub or GHCR (if not already pushed).
2) In RunPod, create a custom template using image: ${IMAGE_TAG}
3) Expose ports 8000 and 8080.
4) Deploy pod and open:
   - Open WebUI: https://<POD_ID>-8080.proxy.runpod.net
   - Phi API:    https://<POD_ID>-8000.proxy.runpod.net/v1/models
EOF
