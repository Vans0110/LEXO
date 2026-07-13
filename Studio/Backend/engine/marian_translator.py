from __future__ import annotations

import re
from pathlib import Path
from functools import lru_cache
from typing import Any

from .config import MARIAN_OPUS_CT2_DIR, MARIAN_OPUS_ORIGINAL_DIR
from .tokenization import WORD_RE


DECODE_OPTIONS = {
    "beam_size": 3,
    "patience": 1,
    "length_penalty": 1.05,
    "repetition_penalty": 1.03,
    "no_repeat_ngram_size": 0,
    "disable_unk": True,
    "replace_unknowns": True,
    "max_decoding_length": 80,
    "sampling_topk": 1,
    "sampling_topp": 1.0,
    "sampling_temperature": 1.0,
}

SEGMENT_ALTERNATIVES = 10
TRANSLATION_ALLOWED_CHARS_RE = re.compile(r"[^0-9A-Za-z\s,.!?'’]+")
POSSESSIVE_MARKERS = {"'s", "’s"}
POSSESSIVE_OWNER_POS = {"NOUN", "PROPN"}


@lru_cache(maxsize=1)
def _load_en_model() -> Any | None:
    try:
        import spacy
    except Exception:
        return None
    try:
        return spacy.load("en_core_web_sm")
    except Exception:
        return None


class MarianTranslator:
    provider_name = "Helsinki-NLP/opus-mt-en-ru"

    def __init__(
        self,
        ct2_model_dir: Path = MARIAN_OPUS_CT2_DIR,
        tokenizer_dir: Path = MARIAN_OPUS_ORIGINAL_DIR,
        provider_name: str | None = None,
    ) -> None:
        self.ct2_model_dir = Path(ct2_model_dir)
        self.tokenizer_dir = Path(tokenizer_dir)
        if provider_name is not None:
            self.provider_name = provider_name
        self._translator = None
        self._tokenizer = None
        self._error = ""

    @property
    def is_available(self) -> bool:
        if self._translator is not None and self._tokenizer is not None:
            return True
        self._ensure_loaded()
        return self._translator is not None and self._tokenizer is not None

    @property
    def error(self) -> str:
        return self._error

    def translate_segments(self, segments: list[str]) -> list[str]:
        if not self.is_available or self._translator is None or self._tokenizer is None:
            return ["" for _ in segments]
        if not segments:
            return []

        try:
            tokenizer = self._tokenizer
            translation_inputs = [
                self._normalize_translation_source(segment)
                for segment in segments
            ]
            translated: list[str] = ["" for _ in segments]
            active_items = [
                (index, source, translation_input)
                for index, (source, translation_input) in enumerate(zip(segments, translation_inputs))
                if translation_input
            ]
            if not active_items:
                return translated
            active_inputs = [item[2] for item in active_items]
            tokenized = tokenizer(active_inputs)
            source_tokens = [
                tokenizer.convert_ids_to_tokens(ids)
                for ids in tokenized["input_ids"]
            ]
            options = dict(DECODE_OPTIONS)
            options["beam_size"] = max(int(options.get("beam_size") or 1), SEGMENT_ALTERNATIVES)
            results = self._translator.translate_batch(
                source_tokens,
                max_batch_size=8,
                num_hypotheses=SEGMENT_ALTERNATIVES,
                **options,
            )
            for (index, source, _translation_input), result in zip(active_items, results):
                candidates: list[str] = []
                seen: set[str] = set()
                for output_tokens in result.hypotheses:
                    output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
                    text = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
                    key = text.lower()
                    if text and key not in seen:
                        seen.add(key)
                        candidates.append(text)
                translated[index] = self._select_learning_literal_candidate(source, candidates)
            return translated
        except Exception as exc:
            self._error = str(exc)
            return ["" for _ in segments]

    def translate_alternatives(self, text: str, max_alternatives: int = 10) -> list[str]:
        if not self.is_available or self._translator is None or self._tokenizer is None:
            return []
        source = self._normalize_translation_source(text)
        if not source:
            return []

        try:
            tokenizer = self._tokenizer
            tokenized = tokenizer([source])
            source_tokens = [
                tokenizer.convert_ids_to_tokens(ids)
                for ids in tokenized["input_ids"]
            ]
            options = dict(DECODE_OPTIONS)
            raw_hypotheses = max(max_alternatives * 2, max_alternatives)
            options["beam_size"] = max(int(options.get("beam_size") or 1), raw_hypotheses)
            results = self._translator.translate_batch(
                source_tokens,
                max_batch_size=1,
                num_hypotheses=raw_hypotheses,
                **options,
            )
            seen: set[str] = set()
            translated: list[str] = []
            for output_tokens in results[0].hypotheses:
                output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
                candidate = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
                candidate = candidate.strip(" \t\r\n.,;:!?")
                if any("a" <= char.lower() <= "z" for char in candidate):
                    continue
                key = candidate.lower()
                if candidate and key not in seen:
                    seen.add(key)
                    translated.append(candidate)
            return translated[:max_alternatives]
        except Exception as exc:
            self._error = str(exc)
            return []

    def _select_learning_literal_candidate(self, source: str, candidates: list[str]) -> str:
        if not candidates:
            return ""
        source_count = max(1, len(self._word_tokens(source)))
        ranked = sorted(
            enumerate(candidates),
            key=lambda item: self._learning_literal_score(source_count, item[1]),
            reverse=True,
        )
        return ranked[0][1]

    def _learning_literal_score(self, source_count: int, candidate: str) -> float:
        target_count = len(self._word_tokens(candidate))
        if target_count <= 0:
            return -1000.0
        ratio = target_count / max(1, source_count)
        closeness = max(0.0, 1.0 - abs(1.0 - ratio))
        compression_penalty = max(0.0, 0.85 - ratio) * 2.5
        excessive_length_penalty = max(0.0, ratio - 1.35) * 1.5
        latin_noise_penalty = 0.25 if any("a" <= char.lower() <= "z" for char in candidate) else 0.0
        return closeness - compression_penalty - excessive_length_penalty - latin_noise_penalty

    def _word_tokens(self, text: str) -> list[str]:
        return WORD_RE.findall(str(text or ""))

    def _normalize_translation_source(self, text: str) -> str:
        source = str(text or "")
        nlp = _load_en_model()
        if nlp is None:
            return self._clean_translation_source(source)
        doc = nlp(source)
        if len(doc) < 2:
            return self._clean_translation_source(source)
        pieces: list[str] = []
        changed = False
        previous = None
        for token in doc:
            marker = token.text.lower()
            if (
                previous is not None
                and marker in POSSESSIVE_MARKERS
                and str(previous.pos_ or "") in POSSESSIVE_OWNER_POS
            ):
                pieces.append("s" + token.whitespace_)
                changed = True
            else:
                pieces.append(token.text_with_ws)
            previous = token
        normalized = "".join(pieces) if changed else source
        return self._clean_translation_source(normalized)

    def _clean_translation_source(self, text: str) -> str:
        cleaned = TRANSLATION_ALLOWED_CHARS_RE.sub(" ", str(text or ""))
        return re.sub(r"\s+", " ", cleaned).strip()

    def _ensure_loaded(self) -> None:
        if self._translator is not None and self._tokenizer is not None:
            return
        if not self.ct2_model_dir.exists():
            self._error = f"Marian CT2 model directory not found: {self.ct2_model_dir}"
            return
        if not self.tokenizer_dir.exists():
            self._error = f"Marian tokenizer directory not found: {self.tokenizer_dir}"
            return
        try:
            import ctranslate2
            import transformers

            self._translator = ctranslate2.Translator(str(self.ct2_model_dir))
            self._tokenizer = transformers.AutoTokenizer.from_pretrained(str(self.tokenizer_dir))
        except Exception as exc:
            self._translator = None
            self._tokenizer = None
            self._error = str(exc)
