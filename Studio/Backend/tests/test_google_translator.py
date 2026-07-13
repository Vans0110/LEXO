from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from engine.google_translation_usage import GoogleTranslationUsageTracker
from engine.google_translator import (
    GoogleTranslator,
    normalize_google_translation_source,
)


class FakeResponse:
    def __init__(self, payload: dict) -> None:
        self.payload = payload

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, exc_type, exc, traceback) -> None:
        return None

    def read(self) -> bytes:
        return json.dumps(self.payload).encode("utf-8")


class GoogleTranslatorTest(unittest.TestCase):
    def test_removes_disallowed_symbols_without_inserting_spaces(self) -> None:
        source = "“Hello,” said Emma — it’s 8:30."
        self.assertEqual(
            normalize_google_translation_source(source),
            "Hello, said Emma its 830.",
        )

    def test_keeps_only_requested_punctuation(self) -> None:
        source = "Wait; (really)? Yes: now!"
        self.assertEqual(
            normalize_google_translation_source(source),
            "Wait really? Yes now!",
        )

    @patch("engine.google_translator.request.urlopen")
    def test_translates_cleaned_segments_once_without_candidates(self, urlopen) -> None:
        urlopen.return_value = FakeResponse(
            {
                "data": {
                    "translations": [
                        {"translatedText": "Привет, Эмма!"},
                        {"translatedText": "Это 830."},
                    ]
                }
            }
        )
        translator = GoogleTranslator("ru", api_key="test-key")

        translated = translator.translate_segments(
            ["“Hello,” Emma!", "It’s 8:30."]
        )

        self.assertEqual(translated, ["Привет, Эмма!", "Это 830."])
        self.assertFalse(hasattr(translator, "translate_segment_candidates"))
        sent_payload = json.loads(urlopen.call_args.args[0].data.decode("utf-8"))
        self.assertEqual(sent_payload["q"], ["Hello, Emma!", "Its 830."])
        self.assertEqual(sent_payload["source"], "en")
        self.assertEqual(sent_payload["target"], "ru")
        self.assertEqual(sent_payload["format"], "text")

    @patch("engine.google_translator.request.urlopen")
    def test_records_successful_google_usage_after_cleaning(self, urlopen) -> None:
        urlopen.return_value = FakeResponse(
            {
                "data": {
                    "translations": [
                        {"translatedText": "Привет"},
                        {"translatedText": "Это 830."},
                    ]
                }
            }
        )

        class Tracker:
            def __init__(self) -> None:
                self.records = []

            def assert_can_spend(self, **kwargs) -> None:
                return None

            def record(self, **kwargs) -> None:
                self.records.append(kwargs)

        tracker = Tracker()
        translator = GoogleTranslator("ru", api_key="test-key", usage_tracker=tracker)

        translator.translate_segments(["“Hello!”", "It’s 8:30."])

        self.assertEqual(
            tracker.records,
            [
                {
                    "target_lang": "ru",
                    "character_count": len("Hello!") + len("Its 830."),
                    "segment_count": 2,
                }
            ],
        )

    @patch("engine.google_translator.request.urlopen")
    def test_blocks_request_when_usage_limit_would_be_exceeded(self, urlopen) -> None:
        class Tracker:
            def assert_can_spend(self, **kwargs) -> None:
                raise RuntimeError("limit exceeded")

            def record(self, **kwargs) -> None:
                raise AssertionError("usage must not be recorded")

        translator = GoogleTranslator("ru", api_key="test-key", usage_tracker=Tracker())

        translated = translator.translate_segments(["Hello!"])

        self.assertEqual(translated, [""])
        self.assertEqual(str(translator.error), "limit exceeded")
        urlopen.assert_not_called()

    def test_warning_threshold_does_not_block_requests(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            tracker = GoogleTranslationUsageTracker(Path(temp_dir))
            tracker.record(target_lang="ru", character_count=4710, segment_count=1)

            tracker.assert_can_spend(additional_characters=1656)

            summary = tracker.summary()
            self.assertEqual(summary["safety_limit"], 5000)
            self.assertEqual(summary["warning_threshold"], 5000)
            self.assertEqual(summary["free_character_limit"], 500000)
            self.assertEqual(summary["block_character_limit"], 495000)
            self.assertEqual(summary["remaining_before_safety_limit"], 290)
            self.assertEqual(summary["remaining_before_warning_threshold"], 290)

    def test_blocks_request_when_monthly_block_limit_would_be_exceeded(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            tracker = GoogleTranslationUsageTracker(Path(temp_dir))
            tracker.record(target_lang="ru", character_count=494900, segment_count=1)

            with self.assertRaisesRegex(RuntimeError, "monthly block limit"):
                tracker.assert_can_spend(additional_characters=101)


if __name__ == "__main__":
    unittest.main()
