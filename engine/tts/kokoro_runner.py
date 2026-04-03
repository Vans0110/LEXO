from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np
import soundfile as sf
from kokoro import KPipeline


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--voice", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--text", required=True)
    parser.add_argument("--speed", type=float, default=1.0)
    args = parser.parse_args()

    pipeline = KPipeline(lang_code="a")
    generated_audio: list[np.ndarray] = []
    for _, _, audio in pipeline(args.text, voice=args.voice, speed=args.speed):
        generated_audio.append(np.asarray(audio))

    if not generated_audio:
        raise RuntimeError("Kokoro returned no audio chunks")

    combined = np.concatenate(generated_audio)
    output_path = Path(args.output)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    sf.write(str(output_path), combined, 24000)

    payload = {
        "audio_path": str(output_path),
        "duration_ms": int(len(combined) / 24000 * 1000),
    }
    print(json.dumps(payload, ensure_ascii=False))


if __name__ == "__main__":
    main()
