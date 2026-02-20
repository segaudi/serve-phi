FROM ghcr.io/open-webui/open-webui:main

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    HF_HOME=/tmp/huggingface \
    MODEL_ID=microsoft/phi-1_5 \
    WARMUP_ON_STARTUP=1 \
    ENABLE_OPENAI_API=true \
    OPENAI_API_BASE_URL=http://127.0.0.1:8000/v1 \
    OPENAI_API_BASE_URLS=http://127.0.0.1:8000/v1

WORKDIR /app

COPY phi_server /app/phi_server
COPY scripts/entrypoint.sh /app/scripts/entrypoint.sh

RUN python3 -m venv /opt/phi-venv && \
    /opt/phi-venv/bin/python -m pip install --upgrade pip && \
    /opt/phi-venv/bin/python -m pip install --extra-index-url https://download.pytorch.org/whl/cu121 -r /app/phi_server/requirements.txt && \
    chmod +x /app/scripts/entrypoint.sh

EXPOSE 8000 8080

CMD ["/app/scripts/entrypoint.sh"]
