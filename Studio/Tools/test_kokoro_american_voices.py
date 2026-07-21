from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


DEFAULT_VOICES = ["af_bella", "af_sarah", "am_adam", "am_michael"]


def _repo_root() -> Path:
    return Path(__file__).resolve().parents[1]


def _read_first_paragraph(path: Path) -> str:
    lines = path.read_text(encoding="utf-8").splitlines()
    paragraphs: list[str] = []
    current: list[str] = []
    for raw_line in lines:
        line = raw_line.strip()
        if line:
            current.append(line)
            continue
        if current:
            paragraphs.append(" ".join(current))
            current = []
    if current:
        paragraphs.append(" ".join(current))

    for paragraph in paragraphs:
        if len(paragraph.split()) >= 8:
            return paragraph
    raise RuntimeError(f"No readable paragraph found in {path}")


def _run_voice(
    python_path: Path,
    runner_path: Path,
    voice: str,
    text: str,
    output_path: Path,
    speed: float,
) -> dict:
    command = [
        str(python_path),
        str(runner_path),
        "--voice",
        voice,
        "--output",
        str(output_path),
        "--text",
        text,
        "--speed",
        str(speed),
    ]
    completed = subprocess.run(
        command,
        cwd=str(_repo_root()),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            f"Kokoro failed for {voice}: "
            f"{completed.stderr.strip() or completed.stdout.strip() or 'unknown error'}"
        )

    payload: dict | None = None
    for line in reversed([item.strip() for item in completed.stdout.splitlines() if item.strip()]):
        try:
            payload = json.loads(line)
            break
        except json.JSONDecodeError:
            continue
    if payload is None:
        raise RuntimeError(f"Kokoro returned no JSON payload for {voice}")
    return payload


def main() -> int:
    root = _repo_root()
    parser = argparse.ArgumentParser()
    parser.add_argument("--book", default=str(root / "Books" / "New Student.txt"))
    parser.add_argument(
        "--out-dir",
        default=str(root / "data" / "tts" / "kokoro_voice_tests" / "new_student_first_paragraph"),
    )
    parser.add_argument("--speed", type=float, default=0.89)
    parser.add_argument("--voices", nargs="*", default=DEFAULT_VOICES)
    args = parser.parse_args()

    book_path = Path(args.book)
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    python_path = root / ".venv_kokoro" / "Scripts" / "python.exe"
    runner_path = root / "engine" / "tts" / "kokoro_runner.py"
    if not python_path.exists():
        raise RuntimeError(f"Kokoro Python not found: {python_path}")
    if not runner_path.exists():
        raise RuntimeError(f"Kokoro runner not found: {runner_path}")

    text = _read_first_paragraph(book_path)
    results = []
    for voice in args.voices:
        output_path = out_dir / f"{voice}.wav"
        payload = _run_voice(python_path, runner_path, voice, text, output_path, args.speed)
        results.append(
            {
                "voice": voice,
                "audio_path": str(output_path),
                "duration_ms": int(payload.get("duration_ms") or 0),
                "timings_count": len(payload.get("timings") or []),
            }
        )
        print(f"{voice}: {output_path}")

    manifest = {
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "book_path": str(book_path),
        "source_text": text,
        "speed": args.speed,
        "voices": results,
    }
    manifest_path = out_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"manifest: {manifest_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
