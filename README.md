# RunPod Diskless Deployment: Phi-1.5 + Open WebUI (Transformers Only)

This repo runs:
- `phi-server`: FastAPI server with Hugging Face `transformers` inference for `microsoft/phi-1_5` on GPU.
- `openwebui`: official Open WebUI container for browser chat.

Design choice: **diskless / ephemeral**.
- No Docker volume mounts.
- No dependence on `/workspace`.
- Model and dependencies may be re-downloaded on each pod start.
- Open WebUI data/settings/chat history are ephemeral.

## 1) RunPod setup

Use a GPU pod with Docker support. Recommended:
- **GPU**: RTX A5000
- **Template/base**: an Ubuntu/CUDA/PyTorch image where Docker can run (for example a RunPod PyTorch CUDA 12.x template).

Expose these **public TCP ports** in RunPod:
- `8000` (Phi OpenAI-compatible API)
- `8080` (Open WebUI)

Optional env vars for the pod:
- `OPENAI_API_KEY` (if set, API calls must send `Authorization: Bearer <key>`)
- `HF_TOKEN` (only needed if Hugging Face access/auth is required)
- `WEBUI_SECRET_KEY` (recommended for Open WebUI session security)

## 2) Start the stack

```bash
git clone <your-repo-url>
cd serve-phi
chmod +x scripts/bootstrap.sh scripts/healthcheck.sh
./scripts/bootstrap.sh
```

The script installs Docker/Compose only if missing, then runs:
- `docker compose up -d --build`

## 3) Verify services

```bash
./scripts/healthcheck.sh
```

Manual checks:
```bash
curl -H "Authorization: Bearer ${OPENAI_API_KEY:-local-dev-key}" http://localhost:8000/v1/models
curl -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${OPENAI_API_KEY:-local-dev-key}" \
  http://localhost:8000/v1/chat/completions \
  -d '{"model":"microsoft/phi-1_5","messages":[{"role":"user","content":"hello"}],"max_tokens":16}'
curl -I http://localhost:8080
```

## 4) Open WebUI from phone

1. In RunPod, copy your pod public IP (or public endpoint host).
2. Open on iPhone/Android browser: `http://<public-ip>:8080`
3. Log into Open WebUI.

This compose file preconfigures Open WebUI with:
- Base URL: `http://phi-server:8000/v1`
- API key: `${OPENAI_API_KEY}` if set, else `local-dev-key`

If you need to set it manually in UI:
1. Open **Admin Panel**.
2. Go to **Settings** -> **Connections** (or **Models / OpenAI** depending on version).
3. Set:
   - OpenAI API Base URL: `http://phi-server:8000/v1`
   - API Key: any string if no server key is enforced, or exact `OPENAI_API_KEY` value if enforced.
4. Save and refresh model list.

## 5) Stop/start commands

From repo root:
```bash
docker compose up -d --build
docker compose logs -f phi-server
docker compose logs -f openwebui
docker compose down
```

## 6) Architecture notes

- Inference stack is strictly Hugging Face `transformers` + `torch` (`model.generate()`).
- No quantization, no vLLM, no llama.cpp, no TensorRT-LLM, no ONNX/OpenVINO, no bitsandbytes/GPTQ/AWQ/GGUF.
- Model loading uses:
  - `trust_remote_code=True`
  - `torch_dtype=bfloat16` if supported, otherwise `float16`
  - `.to("cuda")` and `model.eval()`

Supported API endpoints:
- `GET /v1/models`
- `POST /v1/chat/completions`
- `POST /v1/completions` (basic compatibility)

## 7) Troubleshooting

- `trust_remote_code` errors:
  - Ensure outbound internet is available from the pod and Hugging Face is reachable.
  - Confirm the container logs: `docker compose logs -f phi-server`.

- Hugging Face auth / 401:
  - Set `HF_TOKEN` in pod environment, then restart:
    - `docker compose down && docker compose up -d --build`

- API returns 401:
  - If `OPENAI_API_KEY` is set, every API call must send:
    - `Authorization: Bearer <OPENAI_API_KEY>`

- VRAM / OOM:
  - Reduce `max_tokens` in requests.
  - Keep concurrency low (single-user/small batch).
  - RTX A5000 is typically sufficient for Phi-1.5 FP16 inference.

- WebUI cannot connect to backend:
  - Confirm `phi-server` is healthy:
    - `curl http://localhost:8000/health`
  - Confirm `openwebui` can resolve `phi-server` on compose network:
    - `docker compose exec openwebui getent hosts phi-server`
  - Re-check Open WebUI base URL is exactly:
    - `http://phi-server:8000/v1`

- Cannot access from phone:
  - Verify RunPod public port `8080` is enabled and mapped.
  - Use `http://<public-ip>:8080` (not localhost from phone).
