#!/usr/bin/env bash
set -euo pipefail

API_KEY="${OPENAI_API_KEY:-local-dev-key}"

echo "Checking /v1/models..."
curl -sS -f \
  -H "Authorization: Bearer ${API_KEY}" \
  http://localhost:8000/v1/models
echo
echo

echo "Checking /v1/chat/completions..."
curl -sS -f \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${API_KEY}" \
  http://localhost:8000/v1/chat/completions \
  -d '{
    "model": "microsoft/phi-1_5",
    "messages": [
      {"role": "system", "content": "You are concise."},
      {"role": "user", "content": "Reply with the word: ready"}
    ],
    "max_tokens": 12,
    "temperature": 0.0
  }'
echo
echo

echo "Checking Open WebUI on :8080..."
curl -sS -f http://localhost:8080 >/dev/null
echo "Open WebUI is reachable."
