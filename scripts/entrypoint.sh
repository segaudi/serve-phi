#!/usr/bin/env bash
set -euo pipefail

PHI_PID=""
WEBUI_PID=""

cleanup() {
  if [[ -n "${WEBUI_PID}" ]]; then
    kill "${WEBUI_PID}" 2>/dev/null || true
  fi
  if [[ -n "${PHI_PID}" ]]; then
    kill "${PHI_PID}" 2>/dev/null || true
  fi
}

trap cleanup SIGINT SIGTERM EXIT

export OPENAI_API_KEY="${OPENAI_API_KEY:-local-dev-key}"
export ENABLE_OPENAI_API="${ENABLE_OPENAI_API:-true}"
export OPENAI_API_BASE_URL="${OPENAI_API_BASE_URL:-http://127.0.0.1:8000/v1}"
export OPENAI_API_BASE_URLS="${OPENAI_API_BASE_URLS:-http://127.0.0.1:8000/v1}"
export WEBUI_AUTH="${WEBUI_AUTH:-False}"

echo "Starting phi-server on :8000..."
/opt/phi-venv/bin/python -m uvicorn app:app --app-dir /app/phi_server --host 0.0.0.0 --port 8000 &
PHI_PID=$!

sleep 2
if ! kill -0 "${PHI_PID}" >/dev/null 2>&1; then
  echo "phi-server failed to start."
  wait "${PHI_PID}" || true
  exit 1
fi

echo "Starting Open WebUI on :8080..."
if [[ -x /app/backend/start.sh ]]; then
  /app/backend/start.sh &
elif command -v open-webui >/dev/null 2>&1; then
  open-webui serve --host 0.0.0.0 --port 8080 &
else
  echo "Open WebUI launcher not found."
  exit 1
fi
WEBUI_PID=$!

wait -n "${PHI_PID}" "${WEBUI_PID}"
STATUS=$?
echo "A service exited; shutting down."
cleanup
wait || true
exit "${STATUS}"
