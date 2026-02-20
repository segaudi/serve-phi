import os
import time
import uuid
from typing import List, Optional, Tuple, Union

import torch
from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel
from transformers import AutoModelForCausalLM, AutoTokenizer


MODEL_ID = os.getenv("MODEL_ID", "microsoft/phi-1_5")
API_KEY = os.getenv("OPENAI_API_KEY", "").strip()
HF_TOKEN = os.getenv("HF_TOKEN", "").strip() or None
WARMUP_ON_STARTUP = os.getenv("WARMUP_ON_STARTUP", "1") == "1"

app = FastAPI(title="Phi OpenAI-Compatible Server", version="0.1.0")

tokenizer = None
model = None
device = None


class ChatMessage(BaseModel):
    role: str
    content: Union[str, List[dict]]


class ChatCompletionsRequest(BaseModel):
    model: str = MODEL_ID
    messages: List[ChatMessage]
    max_tokens: Optional[int] = 256
    max_new_tokens: Optional[int] = None
    temperature: float = 0.7
    top_p: float = 1.0
    stop: Optional[Union[str, List[str]]] = None


class CompletionsRequest(BaseModel):
    model: str = MODEL_ID
    prompt: Union[str, List[str]]
    max_tokens: int = 256
    temperature: float = 0.7
    top_p: float = 1.0
    stop: Optional[Union[str, List[str]]] = None


async def require_api_key(authorization: Optional[str] = Header(default=None)) -> None:
    if not API_KEY:
        return

    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(status_code=401, detail="Missing Bearer token")

    presented = authorization.split(" ", 1)[1].strip()
    if presented != API_KEY:
        raise HTTPException(status_code=401, detail="Invalid API key")


def _normalize_content(content: Union[str, List[dict]]) -> str:
    if isinstance(content, str):
        return content

    chunks: List[str] = []
    for item in content:
        if isinstance(item, dict) and item.get("type") == "text":
            chunks.append(str(item.get("text", "")))
        elif isinstance(item, dict) and "text" in item:
            chunks.append(str(item.get("text", "")))
    return "\n".join(chunks).strip()


def _role_tag(role: str) -> str:
    role_norm = (role or "user").lower()
    if role_norm == "system":
        return "[SYSTEM]"
    if role_norm == "assistant":
        return "[ASSISTANT]"
    return "[USER]"


def build_chat_prompt(messages: List[ChatMessage]) -> str:
    lines: List[str] = []
    for msg in messages:
        lines.append(f"{_role_tag(msg.role)}\n{_normalize_content(msg.content).strip()}\n")
    lines.append("[ASSISTANT]\n")
    return "".join(lines)


def apply_stop_strings(text: str, stop: Optional[Union[str, List[str]]]) -> Tuple[str, bool]:
    if not stop:
        return text, False

    stops = [stop] if isinstance(stop, str) else stop
    cut_at = None
    for marker in stops:
        if not marker:
            continue
        idx = text.find(marker)
        if idx != -1 and (cut_at is None or idx < cut_at):
            cut_at = idx

    if cut_at is None:
        return text, False
    return text[:cut_at], True


def _token_count(text: str) -> int:
    return len(tokenizer(text, add_special_tokens=False).input_ids)


def generate_text(
    prompt: str,
    max_new_tokens: int,
    temperature: float,
    top_p: float,
    stop: Optional[Union[str, List[str]]] = None,
):
    encoded = tokenizer(prompt, return_tensors="pt")
    input_ids = encoded["input_ids"].to(device)
    attention_mask = encoded.get("attention_mask")
    if attention_mask is not None:
        attention_mask = attention_mask.to(device)

    do_sample = temperature > 0.0
    generate_kwargs = {
        "input_ids": input_ids,
        "attention_mask": attention_mask,
        "max_new_tokens": max_new_tokens,
        "do_sample": do_sample,
        "top_p": top_p if do_sample else 1.0,
        "temperature": temperature if do_sample else 1.0,
        "pad_token_id": tokenizer.eos_token_id,
        "eos_token_id": tokenizer.eos_token_id,
    }

    with torch.inference_mode():
        output_ids = model.generate(**generate_kwargs)

    new_token_ids = output_ids[0, input_ids.shape[-1] :]
    raw_text = tokenizer.decode(new_token_ids, skip_special_tokens=True)
    final_text, hit_stop = apply_stop_strings(raw_text, stop)

    prompt_tokens = int(input_ids.shape[-1])
    completion_tokens = _token_count(final_text)
    usage = {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "total_tokens": prompt_tokens + completion_tokens,
    }
    finish_reason = "stop" if hit_stop else ("length" if len(new_token_ids) >= max_new_tokens else "stop")
    return final_text, finish_reason, usage


@app.on_event("startup")
def load_model() -> None:
    global tokenizer, model, device

    if not torch.cuda.is_available():
        raise RuntimeError("CUDA GPU is required. No CUDA device detected.")

    device = torch.device("cuda")
    dtype = torch.bfloat16 if torch.cuda.is_bf16_supported() else torch.float16

    tokenizer = AutoTokenizer.from_pretrained(
        MODEL_ID,
        trust_remote_code=True,
        token=HF_TOKEN,
    )
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    model = AutoModelForCausalLM.from_pretrained(
        MODEL_ID,
        torch_dtype=dtype,
        trust_remote_code=True,
        token=HF_TOKEN,
    )
    model.to(device)
    model.eval()

    if WARMUP_ON_STARTUP:
        warmup_prompt = "[USER]\nhello\n[ASSISTANT]\n"
        try:
            generate_text(
                prompt=warmup_prompt,
                max_new_tokens=8,
                temperature=0.0,
                top_p=1.0,
                stop=None,
            )
        except Exception:
            pass


@app.get("/health")
async def health() -> dict:
    return {"status": "ok", "model": MODEL_ID}


@app.get("/v1/models", dependencies=[Depends(require_api_key)])
async def list_models() -> dict:
    return {
        "object": "list",
        "data": [
            {
                "id": MODEL_ID,
                "object": "model",
                "created": 0,
                "owned_by": "microsoft",
            }
        ],
    }


@app.post("/v1/chat/completions", dependencies=[Depends(require_api_key)])
async def chat_completions(req: ChatCompletionsRequest) -> dict:
    if not req.messages:
        raise HTTPException(status_code=400, detail="messages must not be empty")

    max_new_tokens = req.max_new_tokens or req.max_tokens or 256
    max_new_tokens = max(1, min(max_new_tokens, 2048))
    prompt = build_chat_prompt(req.messages)

    try:
        text, finish_reason, usage = generate_text(
            prompt=prompt,
            max_new_tokens=max_new_tokens,
            temperature=req.temperature,
            top_p=req.top_p,
            stop=req.stop,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=f"Generation failed: {exc}") from exc

    created = int(time.time())
    return {
        "id": f"chatcmpl-{uuid.uuid4().hex}",
        "object": "chat.completion",
        "created": created,
        "model": req.model or MODEL_ID,
        "choices": [
            {
                "index": 0,
                "message": {"role": "assistant", "content": text},
                "finish_reason": finish_reason,
            }
        ],
        "usage": usage,
    }


@app.post("/v1/completions", dependencies=[Depends(require_api_key)])
async def completions(req: CompletionsRequest) -> dict:
    prompt_input = req.prompt[0] if isinstance(req.prompt, list) else req.prompt
    max_new_tokens = max(1, min(req.max_tokens, 2048))
    prompt = f"[USER]\n{prompt_input}\n[ASSISTANT]\n"

    try:
        text, finish_reason, usage = generate_text(
            prompt=prompt,
            max_new_tokens=max_new_tokens,
            temperature=req.temperature,
            top_p=req.top_p,
            stop=req.stop,
        )
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=f"Generation failed: {exc}") from exc

    created = int(time.time())
    return {
        "id": f"cmpl-{uuid.uuid4().hex}",
        "object": "text_completion",
        "created": created,
        "model": req.model or MODEL_ID,
        "choices": [
            {
                "index": 0,
                "text": text,
                "finish_reason": finish_reason,
            }
        ],
        "usage": usage,
    }
