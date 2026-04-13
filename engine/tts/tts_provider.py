from __future__ import annotations

import json
import subprocess
import wave
from abc import ABC, abstractmethod
from pathlib import Path

from ..config import KOKORO_PYTHON, KOKORO_RUNNER, tts_mode
from .tts_models import GeneratedAudio


class TtsProvider(ABC):
    engine_id: str

    @abstractmethod
    def synthesize(
        self,
        text: str,
        voice_id: str,
        output_path: Path,
        rate: float = 1.0,
    ) -> GeneratedAudio:
        raise NotImplementedError

    @abstractmethod
    def list_profiles(self) -> list[dict]:
        raise NotImplementedError


class MockTtsProvider(TtsProvider):
    engine_id = "mock_tts"

    def list_profiles(self) -> list[dict]:
        return [
            {
                "id": "mock_en_default",
                "engine_id": self.engine_id,
                "voice_id": "mock_en_default",
                "display_name": "Mock English",
                "lang": "en",
                "is_enabled": 1,
            }
        ]

    def synthesize(
        self,
        text: str,
        voice_id: str,
        output_path: Path,
        rate: float = 1.0,
    ) -> GeneratedAudio:
        output_path.write_text(
            f"mock_tts\nvoice={voice_id}\ntext={text}\n",
            encoding="utf-8",
        )
        duration_ms = max(800, len(text) * 45)
        return GeneratedAudio(audio_path=str(output_path), duration_ms=duration_ms, timings=[])


class KokoroProvider(TtsProvider):
    engine_id = "kokoro"

    def __init__(
        self,
        runner_python: Path = KOKORO_PYTHON,
        runner_script: Path = KOKORO_RUNNER,
    ) -> None:
        self.runner_python = Path(runner_python)
        self.runner_script = Path(runner_script)

    def list_profiles(self) -> list[dict]:
        return [
            {
                "id": "kokoro_af_heart",
                "engine_id": self.engine_id,
                "voice_id": "af_heart",
                "display_name": "Kokoro AF Heart",
                "lang": "en",
                "is_enabled": 1,
            }
        ]

    def synthesize(
        self,
        text: str,
        voice_id: str,
        output_path: Path,
        rate: float = 1.0,
    ) -> GeneratedAudio:
        self._ensure_runtime()
        output_path.parent.mkdir(parents=True, exist_ok=True)
        command = [
            str(self.runner_python),
            str(self.runner_script),
            "--voice",
            voice_id,
            "--output",
            str(output_path),
            "--text",
            text,
            "--speed",
            f"{rate:.3f}",
        ]
        completed = subprocess.run(
            command,
            cwd=str(self.runner_script.parent.parent.parent),
            capture_output=True,
            text=True,
            check=False,
        )
        if completed.returncode != 0:
            raise RuntimeError(
                "Kokoro runner failed: "
                f"{completed.stderr.strip() or completed.stdout.strip() or 'unknown error'}"
            )
        payload = _parse_kokoro_payload(completed.stdout, output_path)
        timings = list(payload.get("timings") or [])
        timings_path = output_path.with_suffix(".timings.json")
        timings_path.write_text(
            json.dumps(timings, ensure_ascii=False, indent=2),
            encoding="utf-8",
        )
        return GeneratedAudio(
            audio_path=payload["audio_path"],
            duration_ms=int(payload["duration_ms"]),
            timings_path=str(timings_path),
            timings=timings,
        )

    def _ensure_runtime(self) -> None:
        if not self.runner_python.exists():
            raise RuntimeError(
                f"Kokoro Python runtime not found: {self.runner_python}. "
                "Run scripts\\setup_kokoro.cmd with Python 3.10-3.12."
            )
        if not self.runner_script.exists():
            raise RuntimeError(f"Kokoro runner script not found: {self.runner_script}")


def create_default_tts_provider() -> TtsProvider:
    if tts_mode() == "kokoro" and KOKORO_PYTHON.exists() and KOKORO_RUNNER.exists():
        return KokoroProvider()
    return MockTtsProvider()


def _parse_kokoro_payload(stdout: str, output_path: Path) -> dict:
    text = (stdout or "").strip()
    if text:
        lines = [line.strip() for line in text.splitlines() if line.strip()]
        for line in reversed(lines):
            try:
                return json.loads(line)
            except json.JSONDecodeError:
                continue
    if output_path.exists():
        with wave.open(str(output_path), "rb") as wav_file:
            frames = wav_file.getnframes()
            framerate = wav_file.getframerate() or 24000
        return {
            "audio_path": str(output_path),
            "duration_ms": int(frames / framerate * 1000),
            "timings": [],
        }
    raise ValueError("Kokoro runner returned no parseable payload")
