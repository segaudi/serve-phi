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
  STARTED=0

  if command -v systemctl >/dev/null 2>&1; then
    ${SUDO} systemctl start docker || true
    if docker info >/dev/null 2>&1; then
      STARTED=1
    fi
  else
    if command -v service >/dev/null 2>&1; then
      ${SUDO} service docker start || true
      if docker info >/dev/null 2>&1; then
        STARTED=1
      fi
    fi
  fi

  if [[ "${STARTED}" -eq 0 ]]; then
    if command -v dockerd >/dev/null 2>&1; then
      echo "systemd/service unavailable; launching dockerd directly..."
      ${SUDO} nohup dockerd >/tmp/dockerd.log 2>&1 &

      for _ in $(seq 1 40); do
        if docker info >/dev/null 2>&1; then
          STARTED=1
          break
        fi
        sleep 1
      done
    fi
  fi

  if [[ "${STARTED}" -eq 0 ]]; then
    if command -v dockerd >/dev/null 2>&1; then
      echo "Retrying dockerd with restricted-container flags..."
      ${SUDO} nohup dockerd --storage-driver=vfs --iptables=false --bridge=none >/tmp/dockerd.log 2>&1 &

      for _ in $(seq 1 40); do
        if docker info >/dev/null 2>&1; then
          STARTED=1
          break
        fi
        sleep 1
      done
    fi
  fi

  if [[ "${STARTED}" -eq 0 ]] && ! docker info >/dev/null 2>&1; then
    echo "ERROR: Docker daemon is still not reachable."
    echo "Check /tmp/dockerd.log for details."
    echo "On RunPod, use a template/pod type that supports Docker daemon inside the container."
    exit 1
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
