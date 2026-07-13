from __future__ import annotations

import re
from functools import lru_cache
from pathlib import Path
from typing import Any

from .config import NLLB33_CT2_DIR, NLLB33_ORIGINAL_DIR
from .tokenization import WORD_RE


DECODE_OPTIONS = {
    "beam_size": 4,
    "patience": 1,
    "length_penalty": 1.0,
    "repetition_penalty": 1.05,
    "no_repeat_ngram_size": 0,
    "disable_unk": True,
    "replace_unknowns": True,
    "max_decoding_length": 100,
    "sampling_topk": 1,
    "sampling_topp": 1.0,
    "sampling_temperature": 1.0,
}

SEGMENT_BEAM_SIZE = 4
DICTIONARY_ALTERNATIVES = 10
SOURCE_LANG = "eng_Latn"
TARGET_LANGS = {
    "ru": "rus_Cyrl",
    "uk": "ukr_Cyrl",
}
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


class NllbTranslator:
    def __init__(
        self,
        target_lang: str,
        ct2_model_dir: Path = NLLB33_CT2_DIR,
        tokenizer_dir: Path = NLLB33_ORIGINAL_DIR,
    ) -> None:
        self.target_lang = str(target_lang or "").strip().lower()
        self.target_token = TARGET_LANGS.get(self.target_lang, self.target_lang)
        self.provider_name = f"facebook/nllb-200-3.3B:{self.target_lang}"
        self.ct2_model_dir = Path(ct2_model_dir)
        self.tokenizer_dir = Path(tokenizer_dir)
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
            source_tokens = [
                tokenizer.convert_ids_to_tokens(tokenizer.encode(source))
                for source in active_inputs
            ]
            options = dict(DECODE_OPTIONS)
            options["beam_size"] = max(int(options.get("beam_size") or 1), SEGMENT_BEAM_SIZE)
            results = self._translator.translate_batch(
                source_tokens,
                target_prefix=[[self.target_token] for _ in source_tokens],
                max_batch_size=4,
                num_hypotheses=1,
                **options,
            )
            for (index, source, _translation_input), result in zip(active_items, results):
                candidates: list[str] = []
                seen: set[str] = set()
                for output_tokens in result.hypotheses:
                    text = self._decode_output(tokenizer, output_tokens)
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
            source_tokens = [tokenizer.convert_ids_to_tokens(tokenizer.encode(source))]
            options = dict(DECODE_OPTIONS)
            raw_hypotheses = max(max_alternatives * 2, DICTIONARY_ALTERNATIVES)
            options["beam_size"] = max(int(options.get("beam_size") or 1), raw_hypotheses)
            results = self._translator.translate_batch(
                source_tokens,
                target_prefix=[[self.target_token]],
                max_batch_size=1,
                num_hypotheses=raw_hypotheses,
                **options,
            )
            seen: set[str] = set()
            translated: list[str] = []
            for output_tokens in results[0].hypotheses:
                candidate = self._decode_output(tokenizer, output_tokens)
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

    def translate_segment_candidates(self, text: str, max_candidates: int = 10) -> list[str]:
        if not self.is_available or self._translator is None or self._tokenizer is None:
            return []
        source = self._normalize_translation_source(text)
        if not source:
            return []
        terminal_punctuation = ""
        punctuation_match = re.search(r"([.!?]+)$", source)
        if punctuation_match is not None:
            terminal_punctuation = punctuation_match.group(1)
            source = source[: punctuation_match.start()].rstrip()

        try:
            tokenizer = self._tokenizer
            source_tokens = [tokenizer.convert_ids_to_tokens(tokenizer.encode(source))]
            options = dict(DECODE_OPTIONS)
            raw_hypotheses = max(max_candidates * 4, max_candidates)
            options["beam_size"] = max(int(options.get("beam_size") or 1), raw_hypotheses)
            results = self._translator.translate_batch(
                source_tokens,
                target_prefix=[[self.target_token]],
                max_batch_size=1,
                num_hypotheses=raw_hypotheses,
                **options,
            )
            seen: set[str] = set()
            translated: list[str] = []
            for output_tokens in results[0].hypotheses:
                candidate = self._clean_decoded_candidate(self._decode_output(tokenizer, output_tokens))
                if terminal_punctuation and candidate and not re.search(r"[.!?]+$", candidate):
                    candidate = f"{candidate}{terminal_punctuation}"
                key = self._candidate_key(candidate)
                if candidate and key not in seen:
                    seen.add(key)
                    translated.append(candidate)
            return translated[:max_candidates]
        except Exception as exc:
            self._error = str(exc)
            return []

    def _clean_decoded_candidate(self, text: str) -> str:
        cleaned = re.sub(r"\s+([,.!?])", r"\1", str(text or "").strip())
        return re.sub(r"\s+", " ", cleaned).strip()

    def _candidate_key(self, text: str) -> str:
        normalized = self._clean_decoded_candidate(text).lower()
        return normalized.strip(" \t\r\n.,;:!?")

    def _decode_output(self, tokenizer: Any, output_tokens: list[str]) -> str:
        tokens = list(output_tokens)
        if tokens and tokens[0] == self.target_token:
            tokens = tokens[1:]
        output_ids = tokenizer.convert_tokens_to_ids(tokens)
        return tokenizer.decode(output_ids, skip_special_tokens=True).strip()

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
        if self.target_token not in TARGET_LANGS.values():
            self._error = f"NLLB target language is not configured: {self.target_lang}"
            return
        if not self.ct2_model_dir.exists():
            self._error = f"NLLB CT2 model directory not found: {self.ct2_model_dir}"
            return
        if not self.tokenizer_dir.exists():
            self._error = f"NLLB tokenizer directory not found: {self.tokenizer_dir}"
            return
        try:
            import ctranslate2
            import transformers

            self._translator = ctranslate2.Translator(str(self.ct2_model_dir))
            self._tokenizer = transformers.AutoTokenizer.from_pretrained(
                str(self.tokenizer_dir),
                src_lang=SOURCE_LANG,
                local_files_only=True,
            )
        except Exception as exc:
            self._translator = None
            self._tokenizer = None
            self._error = str(exc)
