# RunPod One-Pod Deployment: Phi-1.5 + Open WebUI (Transformers Only)

This repo is now a **single-container** deployment for RunPod Pods:
- `phi-server` (FastAPI + Hugging Face Transformers) on port `8000`
- Open WebUI on port `8080`

Both run in one container, so this works with RunPod Pods without Docker Compose / Docker-in-Docker.

## What this image does

- Loads `microsoft/phi-1_5` with:
  - `trust_remote_code=True`
  - `torch_dtype=bfloat16` if supported, else `float16`
  - model moved to CUDA and used via `model.generate()`
- Exposes OpenAI-compatible endpoints:
  - `GET /v1/models`
  - `POST /v1/chat/completions`
  - `POST /v1/completions`
- Starts Open WebUI in the same container, preconfigured to use:
  - `http://127.0.0.1:8000/v1`

No persistent volumes are required. Everything is ephemeral by default.

## 1) Build and push image

From your own machine (or CI):

```bash
git clone <your-repo-url>
cd serve-phi

# Example image tag (use your own registry/repo)
export IMAGE_TAG=ghcr.io/<your-user-or-org>/serve-phi-onepod:latest

chmod +x scripts/bootstrap.sh scripts/healthcheck.sh
IMAGE_TAG="${IMAGE_TAG}" ./scripts/bootstrap.sh

# Push (or run bootstrap with PUSH_IMAGE=1)
docker push "${IMAGE_TAG}"
```

If using Docker Hub:
```bash
export IMAGE_TAG=docker.io/<dockerhub-user>/serve-phi-onepod:latest
docker build -t "${IMAGE_TAG}" .
docker push "${IMAGE_TAG}"
```

## 2) Create RunPod custom template

In RunPod Console:
1. Go to **Templates** -> **Create Template**.
2. Set **Container Image** to your pushed `IMAGE_TAG`.
3. Expose ports:
   - `8080` for Open WebUI
   - `8000` for direct API testing
4. Add env vars (recommended):
   - `OPENAI_API_KEY=<your-key>` (if omitted, defaults to `local-dev-key`)
   - `HF_TOKEN=<optional, only if needed for model access>`
   - `WEBUI_SECRET_KEY=<long-random-string>`
   - `MODEL_ID=microsoft/phi-1_5` (optional; default already set)
   - `WARMUP_ON_STARTUP=1` (optional; default already set)

## 3) Deploy pod

1. Create pod from that template.
2. Choose GPU: **RTX A5000** (target).
3. Wait until container status is running.

## 4) Access from phone

Use RunPod proxy URLs:
- Open WebUI: `https://<POD_ID>-8080.proxy.runpod.net`
- API: `https://<POD_ID>-8000.proxy.runpod.net/v1/models`

If you configured public TCP/IP mapping, use the mapped host/port shown in RunPod Connect.

## 5) Health checks

Inside the pod shell:

```bash
./scripts/healthcheck.sh
```

Or against proxy endpoint:

```bash
export OPENAI_API_KEY=<your-key>
export BASE_URL="https://<POD_ID>-8000.proxy.runpod.net"
export WEBUI_URL="https://<POD_ID>-8080.proxy.runpod.net"
./scripts/healthcheck.sh
```

## 6) API examples

```bash
curl -H "Authorization: Bearer ${OPENAI_API_KEY:-local-dev-key}" \
  https://<POD_ID>-8000.proxy.runpod.net/v1/models

curl -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${OPENAI_API_KEY:-local-dev-key}" \
  https://<POD_ID>-8000.proxy.runpod.net/v1/chat/completions \
  -d '{"model":"microsoft/phi-1_5","messages":[{"role":"user","content":"hello"}],"max_tokens":32}'
```

## 7) Notes and troubleshooting

- `401 Unauthorized`:
  - Use `Authorization: Bearer <OPENAI_API_KEY>`.
  - If you did not set `OPENAI_API_KEY`, default key is `local-dev-key`.

- Hugging Face auth issues:
  - Set `HF_TOKEN` and redeploy pod.

- OOM/VRAM pressure:
  - Lower `max_tokens`.
  - Keep concurrent requests low.

- Open WebUI cannot list model:
  - Ensure `phi-server` is up (`/health`).
  - In Open WebUI admin settings, OpenAI endpoint should be `http://127.0.0.1:8000/v1`.

- Cold start latency:
  - First request can be slower because model is loaded at startup and warmup may run.
