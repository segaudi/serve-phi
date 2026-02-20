#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

SUDO=""
if [[ "${EUID}" -ne 0 ]]; then
  if command -v sudo >/dev/null 2>&1; then
    SUDO="sudo"
  else
    echo "This script needs root privileges to install Docker. Re-run as root."
    exit 1
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Installing Docker..."
  ${SUDO} apt-get update
  ${SUDO} apt-get install -y ca-certificates curl gnupg lsb-release
  curl -fsSL https://get.docker.com | ${SUDO} sh
fi

if ! docker compose version >/dev/null 2>&1; then
  if ! command -v docker-compose >/dev/null 2>&1; then
    echo "Docker Compose not found. Installing compose plugin..."
    ${SUDO} apt-get update
    ${SUDO} apt-get install -y docker-compose-plugin
  fi
fi

if ! docker info >/dev/null 2>&1; then
  echo "Starting Docker daemon..."
  if command -v systemctl >/dev/null 2>&1; then
    ${SUDO} systemctl start docker || true
  else
    ${SUDO} service docker start || true
  fi
fi

if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD=(docker compose)
else
  COMPOSE_CMD=(docker-compose)
fi

echo "Building and starting services..."
"${COMPOSE_CMD[@]}" up -d --build

echo "Services started."
echo "Open WebUI: http://<RUNPOD_PUBLIC_IP>:8080"
echo "Phi API:    http://<RUNPOD_PUBLIC_IP>:8000/v1/models"
