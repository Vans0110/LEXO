from __future__ import annotations

import html
import json
import os
import re
from pathlib import Path
from urllib import parse, request

from .google_translation_usage import GoogleTranslationUsageTracker


GOOGLE_TRANSLATE_URL = "https://translation.googleapis.com/language/translate/v2"
MAX_BATCH_SEGMENTS = 128
RECOMMENDED_BATCH_CHARACTERS = 5_000
ALLOWED_PUNCTUATION = ".,!?"


def normalize_google_translation_source(text: str) -> str:
    cleaned = "".join(
        char
        for char in str(text or "")
        if char.isalnum() or char.isspace() or char in ALLOWED_PUNCTUATION
    )
    return re.sub(r"\s+", " ", cleaned).strip()


class GoogleTranslator:
    def __init__(
        self,
        target_lang: str,
        api_key: str | None = None,
        timeout_seconds: float = 30.0,
        usage_tracker: GoogleTranslationUsageTracker | None = None,
    ) -> None:
        self.target_lang = str(target_lang or "").strip().lower()
        self.api_key = str(
            api_key
            if api_key is not None
            else os.getenv("LEXO_GOOGLE_TRANSLATE_API_KEY", "")
        ).strip()
        self.timeout_seconds = timeout_seconds
        self.usage_tracker = usage_tracker
        self.provider_name = f"google-cloud-translation-v2:{self.target_lang}"
        self._error = ""

    @property
    def is_available(self) -> bool:
        return bool(self.api_key and self.target_lang)

    @property
    def error(self) -> str:
        return self._error

    def translate_segments(self, segments: list[str]) -> list[str]:
        translated = ["" for _ in segments]
        if not self.is_available or not segments:
            return translated

        active_items = [
            (index, normalize_google_translation_source(segment))
            for index, segment in enumerate(segments)
        ]
        active_items = [item for item in active_items if item[1]]
        try:
            for batch in self._batches(active_items):
                batch_texts = [item[1] for item in batch]
                self._assert_can_spend(batch_texts)
                batch_translations = self._translate_batch(batch_texts)
                if len(batch_translations) != len(batch):
                    raise RuntimeError(
                        "Google Translation returned a different number of segments"
                    )
                self._record_usage(batch_texts)
                for (index, _), translated_text in zip(batch, batch_translations):
                    translated[index] = translated_text
            return translated
        except Exception as exc:
            self._error = str(exc)
            return ["" for _ in segments]

    def _translate_batch(self, texts: list[str]) -> list[str]:
        url = f"{GOOGLE_TRANSLATE_URL}?{parse.urlencode({'key': self.api_key})}"
        payload = json.dumps(
            {
                "q": texts,
                "source": "en",
                "target": self.target_lang,
                "format": "text",
            },
            ensure_ascii=False,
        ).encode("utf-8")
        http_request = request.Request(
            url,
            data=payload,
            headers={"Content-Type": "application/json; charset=utf-8"},
            method="POST",
        )
        with request.urlopen(http_request, timeout=self.timeout_seconds) as response:
            response_payload = json.loads(response.read().decode("utf-8"))
        translations = response_payload.get("data", {}).get("translations", [])
        return [
            html.unescape(str(item.get("translatedText") or "")).strip()
            for item in translations
        ]

    def _batches(
        self,
        items: list[tuple[int, str]],
    ) -> list[list[tuple[int, str]]]:
        batches: list[list[tuple[int, str]]] = []
        current: list[tuple[int, str]] = []
        current_characters = 0
        for item in items:
            item_characters = len(item[1])
            if current and (
                len(current) >= MAX_BATCH_SEGMENTS
                or current_characters + item_characters > RECOMMENDED_BATCH_CHARACTERS
            ):
                batches.append(current)
                current = []
                current_characters = 0
            current.append(item)
            current_characters += item_characters
        if current:
            batches.append(current)
        return batches

    def _record_usage(self, texts: list[str]) -> None:
        if self.usage_tracker is None:
            return
        self.usage_tracker.record(
            target_lang=self.target_lang,
            character_count=sum(len(text) for text in texts),
            segment_count=len(texts),
        )

    def _assert_can_spend(self, texts: list[str]) -> None:
        if self.usage_tracker is None:
            return
        self.usage_tracker.assert_can_spend(
            additional_characters=sum(len(text) for text in texts),
        )


def default_google_usage_tracker() -> GoogleTranslationUsageTracker:
    return GoogleTranslationUsageTracker(Path(__file__).resolve().parent.parent)
