from __future__ import annotations

import importlib
from abc import ABC, abstractmethod
from pathlib import Path

from .config import NLLB_CT2_DIR, NLLB_ORIGINAL_DIR, translator_mode
from .didactic_rules import apply_didactic_post_edit, resolve_didactic_translation


DEFAULT_MODEL_NAME = "mock-local-translation"
NLLB_MODEL_NAME = "facebook/nllb-200-distilled-600M"
NLLB_LANG_CODES = {
    "en": "eng_Latn",
    "ru": "rus_Cyrl",
}


class TranslationProvider(ABC):
    model_name: str

    @abstractmethod
    def translate_segments(
        self,
        segments: list[str],
        source_lang: str,
        target_lang: str,
    ) -> list[str]:
        raise NotImplementedError


class MockProvider(TranslationProvider):
    model_name = DEFAULT_MODEL_NAME

    def translate_segments(
        self,
        segments: list[str],
        source_lang: str,
        target_lang: str,
    ) -> list[str]:
        return [f"[{target_lang}] {segment}" for segment in segments]


class NllbProvider(TranslationProvider):
    model_name = NLLB_MODEL_NAME

    def __init__(
        self,
        ct2_model_dir: Path = NLLB_CT2_DIR,
        tokenizer_dir: Path = NLLB_ORIGINAL_DIR,
    ) -> None:
        self.ct2_model_dir = Path(ct2_model_dir)
        self.tokenizer_dir = Path(tokenizer_dir)
        self._validate_dirs()

        ctranslate2 = _import_required_module("ctranslate2")
        transformers = _import_required_module("transformers")

        self._translator = ctranslate2.Translator(str(self.ct2_model_dir))
        self._tokenizer = transformers.AutoTokenizer.from_pretrained(str(self.tokenizer_dir))

    def _validate_dirs(self) -> None:
        if not self.ct2_model_dir.exists():
            raise RuntimeError(
                f"NLLB CT2 model directory not found: {self.ct2_model_dir}. "
                "Run setup_nllb.cmd first."
            )
        if not self.tokenizer_dir.exists():
            raise RuntimeError(
                f"NLLB tokenizer directory not found: {self.tokenizer_dir}. "
                "Run setup_nllb.cmd first."
            )

    def translate_segments(
        self,
        segments: list[str],
        source_lang: str,
        target_lang: str,
    ) -> list[str]:
        if not segments:
            return []

        src_lang = _resolve_nllb_lang(source_lang)
        tgt_lang = _resolve_nllb_lang(target_lang)

        tokenizer = self._tokenizer
        tokenizer.src_lang = src_lang
        target_prefix = [[tgt_lang] for _ in segments]

        tokenized = tokenizer(segments)
        source_tokens = [
            tokenizer.convert_ids_to_tokens(ids)
            for ids in tokenized["input_ids"]
        ]
        results = self._translator.translate_batch(
            source_tokens,
            target_prefix=target_prefix,
            max_batch_size=8,
        )

        translated: list[str] = []
        for result in results:
            output_tokens = result.hypotheses[0]
            output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
            text = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
            translated.append(text)
        return translated


def create_default_provider() -> TranslationProvider:
    mode = translator_mode()
    if mode == "nllb":
        return NllbProvider()
    return MockProvider()


def translate_segment_batch(
    provider: TranslationProvider,
    segments: list[dict],
    source_lang: str,
    target_lang: str,
) -> list[dict]:
    unresolved_indexes: list[int] = []
    unresolved_texts: list[str] = []
    results: list[dict] = []

    for index, segment in enumerate(segments):
        source_text = str(segment.get("source_text") or "").strip()
        preset_text = str(segment.get("target_text") or "").strip()
        preset_kind = str(segment.get("translation_kind") or "").strip()
        if preset_text:
            results.append(
                {
                    "target_text": preset_text,
                    "translation_kind": preset_kind or "rule_exact",
                }
            )
            continue

        didactic_text = resolve_didactic_translation(source_text, source_lang, target_lang)
        if didactic_text is not None:
            results.append(
                {
                    "target_text": didactic_text,
                    "translation_kind": "rule_exact",
                }
            )
            continue

        unresolved_indexes.append(index)
        unresolved_texts.append(source_text)
        results.append({})

    if unresolved_texts:
        translated = provider.translate_segments(unresolved_texts, source_lang, target_lang)
        for unresolved_index, source_text, translated_text in zip(
            unresolved_indexes,
            unresolved_texts,
            translated,
            strict=True,
        ):
            cleaned = apply_didactic_post_edit(
                source_segment=source_text,
                translated_segment=translated_text,
                source_lang=source_lang,
                target_lang=target_lang,
            ).strip()
            results[unresolved_index] = {
                "target_text": cleaned,
                "translation_kind": "provider_fallback",
            }

    return results


def _resolve_nllb_lang(lang: str) -> str:
    normalized = (lang or "").strip().lower()
    if normalized not in NLLB_LANG_CODES:
        raise ValueError(
            f"Unsupported NLLB language code: {lang}. "
            f"Supported codes: {', '.join(sorted(NLLB_LANG_CODES))}"
        )
    return NLLB_LANG_CODES[normalized]


def _import_required_module(name: str):
    try:
        return importlib.import_module(name)
    except ImportError as exc:
        raise RuntimeError(
            f"Required Python package '{name}' is not installed. "
            "Create the project venv and run setup_nllb.cmd."
        ) from exc
