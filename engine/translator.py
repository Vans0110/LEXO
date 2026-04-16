from __future__ import annotations

import importlib
import re
from abc import ABC, abstractmethod
from pathlib import Path

from .config import (
    M2M100_CT2_DIR,
    M2M100_ORIGINAL_DIR,
    MADLAD_CT2_DIR,
    MADLAD_ORIGINAL_DIR,
    NLLB33_CT2_DIR,
    NLLB33_ORIGINAL_DIR,
    NLLB_CT2_DIR,
    NLLB_ORIGINAL_DIR,
    translator_mode,
)
from .didactic_rules import resolve_didactic_translation


DEFAULT_MODEL_NAME = "mock-local-translation"
NLLB_MODEL_NAME = "facebook/nllb-200-distilled-600M"
NLLB33_MODEL_NAME = "facebook/nllb-200-3.3B"
M2M100_MODEL_NAME = "facebook/m2m100_1.2B"
MADLAD_MODEL_NAME = "google/madlad400-10b-mt"
NLLB_LANG_CODES = {
    "en": "eng_Latn",
    "ru": "rus_Cyrl",
}
M2M100_LANG_CODES = {
    "en": "en",
    "ru": "ru",
}
MADLAD_LANG_CODES = {
    "en": "en",
    "ru": "ru",
}
CHAPTER_TITLE_RE = re.compile(
    r"^\s*Chapter\s+(?P<number>\d+|one|two|three|four|five|six|seven|eight|nine|ten)\s*:\s*(?P<title>.+?)\s*$",
    flags=re.IGNORECASE,
)
NUMBER_WORDS = {
    "one": "1",
    "two": "2",
    "three": "3",
    "four": "4",
    "five": "5",
    "six": "6",
    "seven": "7",
    "eight": "8",
    "nine": "9",
    "ten": "10",
}
LITERAL_DECODE_OPTIONS = {
    "beam_size": 1,
    "length_penalty": 1.2,
    "repetition_penalty": 1.0,
    "no_repeat_ngram_size": 0,
    "disable_unk": True,
    "max_decoding_length": 96,
    "sampling_topk": 1,
    "sampling_topp": 1.0,
    "sampling_temperature": 1.0,
}
NLLB33_BASE_DECODE_OPTIONS = {
    "beam_size": 4,
    "length_penalty": 1.0,
    "repetition_penalty": 1.15,
    "no_repeat_ngram_size": 3,
    "disable_unk": True,
    "sampling_topk": 1,
    "sampling_topp": 1.0,
    "sampling_temperature": 1.0,
}
NLLB33_RETRY_DECODE_OPTIONS = {
    "beam_size": 5,
    "length_penalty": 0.9,
    "repetition_penalty": 1.35,
    "no_repeat_ngram_size": 4,
    "disable_unk": True,
    "sampling_topk": 1,
    "sampling_topp": 1.0,
    "sampling_temperature": 1.0,
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
            **LITERAL_DECODE_OPTIONS,
        )

        translated: list[str] = []
        for result in results:
            output_tokens = result.hypotheses[0]
            output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
            text = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
            translated.append(text)
        return translated


class Nllb33Provider(TranslationProvider):
    model_name = NLLB33_MODEL_NAME

    def __init__(
        self,
        ct2_model_dir: Path = NLLB33_CT2_DIR,
        tokenizer_dir: Path = NLLB33_ORIGINAL_DIR,
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
                f"NLLB 3.3B CT2 model directory not found: {self.ct2_model_dir}. "
                "Convert the NLLB 3.3B model first."
            )
        if not self.tokenizer_dir.exists():
            raise RuntimeError(
                f"NLLB 3.3B tokenizer directory not found: {self.tokenizer_dir}. "
                "Download the NLLB 3.3B model first."
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

        translated: list[str] = []
        for segment in segments:
            translated_text = self._translate_single_segment(
                segment=segment,
                src_lang=src_lang,
                tgt_lang=tgt_lang,
                retry=False,
            )
            if _is_degraded_translation(segment, translated_text):
                retried_text = self._translate_single_segment(
                    segment=segment,
                    src_lang=src_lang,
                    tgt_lang=tgt_lang,
                    retry=True,
                )
                if not _is_degraded_translation(segment, retried_text):
                    translated_text = retried_text
            translated.append(translated_text)
        return translated

    def _translate_single_segment(
        self,
        *,
        segment: str,
        src_lang: str,
        tgt_lang: str,
        retry: bool,
    ) -> str:
        tokenizer = self._tokenizer
        tokenizer.src_lang = src_lang
        tokenized = tokenizer([segment])
        source_tokens = [tokenizer.convert_ids_to_tokens(tokenized["input_ids"][0])]
        results = self._translator.translate_batch(
            source_tokens,
            target_prefix=[[tgt_lang]],
            max_batch_size=1,
            **_build_nllb33_decode_options(segment, retry=retry),
        )
        output_tokens = results[0].hypotheses[0]
        output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
        return tokenizer.decode(output_ids, skip_special_tokens=True).strip()


class MadladProvider(TranslationProvider):
    model_name = MADLAD_MODEL_NAME

    def __init__(
        self,
        ct2_model_dir: Path = MADLAD_CT2_DIR,
        tokenizer_dir: Path = MADLAD_ORIGINAL_DIR,
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
                f"MADLAD CT2 model directory not found: {self.ct2_model_dir}. "
                "Convert the MADLAD model first."
            )
        if not self.tokenizer_dir.exists():
            raise RuntimeError(
                f"MADLAD tokenizer directory not found: {self.tokenizer_dir}. "
                "Download the MADLAD model first."
            )

    def translate_segments(
        self,
        segments: list[str],
        source_lang: str,
        target_lang: str,
    ) -> list[str]:
        if not segments:
            return []

        target_prefix = _resolve_madlad_lang(target_lang)
        prefixed_segments = [f"<2{target_prefix}> {segment}".strip() for segment in segments]

        tokenizer = self._tokenizer
        tokenized = tokenizer(prefixed_segments)
        source_tokens = [
            tokenizer.convert_ids_to_tokens(ids)
            for ids in tokenized["input_ids"]
        ]
        results = self._translator.translate_batch(
            source_tokens,
            max_batch_size=4,
            **LITERAL_DECODE_OPTIONS,
        )

        translated: list[str] = []
        for result in results:
            output_tokens = result.hypotheses[0]
            output_ids = tokenizer.convert_tokens_to_ids(output_tokens)
            text = tokenizer.decode(output_ids, skip_special_tokens=True).strip()
            translated.append(text)
        return translated


class M2M100Provider(TranslationProvider):
    model_name = M2M100_MODEL_NAME

    def __init__(
        self,
        ct2_model_dir: Path = M2M100_CT2_DIR,
        tokenizer_dir: Path = M2M100_ORIGINAL_DIR,
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
                f"M2M100 CT2 model directory not found: {self.ct2_model_dir}. "
                "Convert the M2M100 model first."
            )
        if not self.tokenizer_dir.exists():
            raise RuntimeError(
                f"M2M100 tokenizer directory not found: {self.tokenizer_dir}. "
                "Download the M2M100 model first."
            )

    def translate_segments(
        self,
        segments: list[str],
        source_lang: str,
        target_lang: str,
    ) -> list[str]:
        if not segments:
            return []

        src_lang = _resolve_m2m100_lang(source_lang)
        tgt_lang = _resolve_m2m100_lang(target_lang)

        tokenizer = self._tokenizer
        tokenizer.src_lang = src_lang
        target_token_id = tokenizer.get_lang_id(tgt_lang)
        target_prefix_token = tokenizer.convert_ids_to_tokens(target_token_id)
        target_prefix = [[target_prefix_token] for _ in segments]

        tokenized = tokenizer(segments)
        source_tokens = [
            tokenizer.convert_ids_to_tokens(ids)
            for ids in tokenized["input_ids"]
        ]
        results = self._translator.translate_batch(
            source_tokens,
            target_prefix=target_prefix,
            max_batch_size=8,
            **LITERAL_DECODE_OPTIONS,
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
    if mode == "nllb33":
        return Nllb33Provider()
    if mode == "nllb":
        return NllbProvider()
    if mode == "m2m100":
        return M2M100Provider()
    if mode == "madlad":
        return MadladProvider()
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
        chapter_heading = _resolve_chapter_heading_parts(source_text)
        if chapter_heading is not None:
            unresolved_indexes.append(index)
            unresolved_texts.append(chapter_heading["title"])
            results.append(
                {
                    "_chapter_heading": chapter_heading,
                    "_translation_kind": preset_kind or "rule_exact",
                }
            )
            continue
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
            pending = results[unresolved_index]
            chapter_heading = pending.get("_chapter_heading")
            if chapter_heading is not None:
                translated_title = translated_text.strip()
                results[unresolved_index] = {
                    "target_text": _build_translated_chapter_heading(
                        chapter_heading["number"],
                        translated_title,
                    ),
                    "translation_kind": str(pending.get("_translation_kind") or "rule_exact"),
                }
            else:
                results[unresolved_index] = {
                    "target_text": translated_text.strip(),
                    "translation_kind": "provider_fallback",
                }

    return results


def _resolve_chapter_heading_parts(source_text: str) -> dict[str, str] | None:
    match = CHAPTER_TITLE_RE.match(source_text)
    if match is None:
        return None
    number_raw = str(match.group("number") or "").strip().lower()
    title = str(match.group("title") or "").strip()
    if not title:
        return None
    return {
        "number": NUMBER_WORDS.get(number_raw, number_raw),
        "title": title,
    }


def _build_translated_chapter_heading(number: str, translated_title: str) -> str:
    clean_title = translated_title.strip()
    if not clean_title:
        return f"Глава {number}"
    return f"Глава {number}: {clean_title}"


def _build_nllb33_decode_options(segment: str, *, retry: bool) -> dict[str, int | float | bool]:
    words = re.findall(r"[A-Za-zА-Яа-яЁё0-9]+", segment)
    word_count = len(words)
    if word_count <= 2:
        max_decoding_length = 8
    elif word_count <= 4:
        max_decoding_length = 12
    elif word_count <= 8:
        max_decoding_length = 20
    else:
        max_decoding_length = min(32, word_count * 2 + 6)
    options = dict(NLLB33_RETRY_DECODE_OPTIONS if retry else NLLB33_BASE_DECODE_OPTIONS)
    options["max_decoding_length"] = max_decoding_length
    return options


def _is_degraded_translation(source_text: str, translated_text: str) -> bool:
    translated = translated_text.strip()
    if not translated:
        return True
    source_words = re.findall(r"[A-Za-zА-Яа-яЁё0-9]+", source_text.lower())
    target_words = re.findall(r"[A-Za-zА-Яа-яЁё0-9]+", translated.lower())
    if not target_words:
        return True
    if len(target_words) >= max(6, len(source_words) * 3):
        return True
    repeated_uniques = len(set(target_words))
    if len(target_words) >= 4 and repeated_uniques <= max(1, len(target_words) // 5):
        return True
    if _has_repeated_ngram(target_words, 1, threshold=4):
        return True
    if _has_repeated_ngram(target_words, 2, threshold=3):
        return True
    latin_target_words = [word for word in target_words if re.search(r"[a-z]", word)]
    if len(source_words) >= 2 and len(latin_target_words) >= max(2, len(target_words) - 1):
        return True
    return False


def _has_repeated_ngram(words: list[str], size: int, *, threshold: int) -> bool:
    if len(words) < size * threshold:
        return False
    best_run = 1
    last_ngram: tuple[str, ...] | None = None
    current_run = 1
    for index in range(0, len(words) - size + 1, size):
        ngram = tuple(words[index : index + size])
        if len(ngram) < size:
            break
        if ngram == last_ngram:
            current_run += 1
            best_run = max(best_run, current_run)
        else:
            current_run = 1
            last_ngram = ngram
    return best_run >= threshold


def _resolve_nllb_lang(lang: str) -> str:
    normalized = (lang or "").strip().lower()
    if normalized not in NLLB_LANG_CODES:
        raise ValueError(
            f"Unsupported NLLB language code: {lang}. "
            f"Supported codes: {', '.join(sorted(NLLB_LANG_CODES))}"
        )
    return NLLB_LANG_CODES[normalized]


def _resolve_m2m100_lang(lang: str) -> str:
    normalized = (lang or "").strip().lower()
    if normalized not in M2M100_LANG_CODES:
        raise ValueError(
            f"Unsupported M2M100 language code: {lang}. "
            f"Supported codes: {', '.join(sorted(M2M100_LANG_CODES))}"
        )
    return M2M100_LANG_CODES[normalized]


def _resolve_madlad_lang(lang: str) -> str:
    normalized = (lang or "").strip().lower()
    if normalized not in MADLAD_LANG_CODES:
        raise ValueError(
            f"Unsupported MADLAD language code: {lang}. "
            f"Supported codes: {', '.join(sorted(MADLAD_LANG_CODES))}"
        )
    return MADLAD_LANG_CODES[normalized]


def _import_required_module(name: str):
    try:
        return importlib.import_module(name)
    except ImportError as exc:
        raise RuntimeError(
            f"Required Python package '{name}' is not installed. "
            "Create the project venv and run setup_nllb.cmd."
        ) from exc
