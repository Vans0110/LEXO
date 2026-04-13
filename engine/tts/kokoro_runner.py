from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

import numpy as np
import soundfile as sf
from kokoro import KPipeline


def _serialize_timings(tokens: list[Any] | None, chunk_offset_s: float) -> list[dict]:
    if not tokens:
        return []
    timings: list[dict] = []
    for index, token in enumerate(tokens):
        text = str(getattr(token, "text", "") or "")
        if not text:
            continue
        start_ts = getattr(token, "start_ts", None)
        end_ts = getattr(token, "end_ts", None)
        if start_ts is None or end_ts is None:
            continue
        try:
            start_value = float(start_ts) + chunk_offset_s
            end_value = float(end_ts) + chunk_offset_s
        except (TypeError, ValueError):
            continue
        timings.append(
            {
                "index": index,
                "text": text,
                "start": round(start_value, 4),
                "end": round(end_value, 4),
                "whitespace": str(getattr(token, "whitespace", "") or ""),
                "phonemes": str(getattr(token, "phonemes", "") or ""),
            }
        )
    return timings


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--voice", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--text", required=True)
    parser.add_argument("--speed", type=float, default=1.0)
    args = parser.parse_args()

    pipeline = KPipeline(lang_code="a")
    generated_audio: list[np.ndarray] = []
    timings: list[dict] = []
    offset_s = 0.0
    for result in pipeline(args.text, voice=args.voice, speed=args.speed):
        audio = result.audio
        if audio is None:
            continue
        chunk_audio = np.asarray(audio)
        generated_audio.append(chunk_audio)
        timings.extend(_serialize_timings(getattr(result, "tokens", None), offset_s))
        offset_s += len(chunk_audio) / 24000

    if not generated_audio:
        raise RuntimeError("Kokoro returned no audio chunks")

    combined = np.concatenate(generated_audio)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(output_path), combined, 24000)

    payload = {
        "audio_path": str(output_path),
        "duration_ms": int(len(combined) / 24000 * 1000),
        "timings": timings,
    }
    print(json.dumps(payload, ensure_ascii=True))


if __name__ == "__main__":
    main()
