#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path


MODEL_PATH = Path(__file__).resolve().parents[1] / "data" / "models" / "qwen3-14b" / "original"
DEFAULT_MAX_NEW_TOKENS = 200


def _load_model():
    try:
        from transformers import AutoModelForCausalLM, AutoTokenizer
    except ImportError as exc:
        print("[QWEN] Missing dependencies. Install first:", file=sys.stderr)
        print(
            r".venv\Scripts\python.exe -m pip install torch transformers accelerate sentencepiece safetensors",
            file=sys.stderr,
        )
        print(f"[QWEN] Import error details: {exc!r}", file=sys.stderr)
        raise SystemExit(1) from exc

    if not MODEL_PATH.exists():
        print(f"[QWEN] Model path not found: {MODEL_PATH}", file=sys.stderr)
        raise SystemExit(1)

    print(f"[QWEN] Loading tokenizer from: {MODEL_PATH}")
    tokenizer = AutoTokenizer.from_pretrained(MODEL_PATH, trust_remote_code=True)

    print("[QWEN] Loading model. This may take a while...")
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_PATH,
        torch_dtype="auto",
        device_map="auto",
        trust_remote_code=True,
    )
    print("[QWEN] Model ready.")
    return tokenizer, model


def _generate(tokenizer, model, prompt: str, max_new_tokens: int = DEFAULT_MAX_NEW_TOKENS) -> str:
    inputs = tokenizer(prompt, return_tensors="pt").to(model.device)
    output = model.generate(
        **inputs,
        max_new_tokens=max_new_tokens,
        do_sample=False,
    )
    text = tokenizer.decode(output[0], skip_special_tokens=True)
    if text.startswith(prompt):
        text = text[len(prompt) :].lstrip()
    return text.strip()


def main() -> int:
    tokenizer, model = _load_model()
    print("[QWEN] Enter prompt. Empty line or 'exit' closes the session.")
    while True:
        try:
            prompt = input("\nQWEN> ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\n[QWEN] Exit.")
            return 0
        if not prompt or prompt.lower() in {"exit", "quit"}:
            print("[QWEN] Exit.")
            return 0
        try:
            answer = _generate(tokenizer, model, prompt)
        except Exception as exc:
            print(f"[QWEN] Generation error: {exc}", file=sys.stderr)
            continue
        print("\n" + answer)


if __name__ == "__main__":
    raise SystemExit(main())
