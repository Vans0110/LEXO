from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
import sys


try:  # pragma: no cover - import path depends on runtime env
    import pymorphy3  # type: ignore[import-not-found]
except Exception:  # pragma: no cover
    windows_site_packages = Path(__file__).resolve().parent.parent / ".venv" / "Lib" / "site-packages"
    if windows_site_packages.exists():
        sys.path.insert(0, str(windows_site_packages))
    try:
        import pymorphy3  # type: ignore[import-not-found]
    except Exception:  # pragma: no cover
        pymorphy3 = None


RU_WORD_RE = re.compile(r"[А-Яа-яЁё-]+")
RU_DIRECTIONAL_TITLE_WORDS = {"домой", "сюда", "туда", "вверх", "вниз"}
RU_TRANSPORT_WORDS = {"ездит", "поехал", "поехала", "едет"}
RU_HABITUAL_MOTION_WORDS = {"ходит", "ходить"}
RU_SPEECH_VERBS = {
    "говорит",
    "говорил",
    "говорила",
    "сказал",
    "сказала",
    "сказали",
    "спросил",
    "спросила",
    "спрашивает",
    "прошептал",
    "прошептала",
    "шепчет",
    "ответил",
    "ответила",
    "отвечает",
    "думает",
    "подумал",
    "подумала",
}
TARGET_SPEAKER_AFTER_VERB_RE = re.compile(
    r"(?:говорит|говорила|сказал|сказала|спросил|спросила|шепчет|прошептал|прошептала|ответил|ответила|думает|подумал|подумала)\s+([А-ЯЁ][а-яё-]+)"
)
TARGET_SPEAKER_BEFORE_VERB_RE = re.compile(
    r"([А-ЯЁ][а-яё-]+)\s+(?:говорит|говорила|сказал|сказала|спросил|спросила|шепчет|прошептал|прошептала|ответил|ответила|думает|подумал|подумала)"
)
QUOTED_TEXT_RE = re.compile(r"[\"«](.*?)[\"»]")


@dataclass(frozen=True)
class RuToken:
    text: str
    normalized: str
    is_capitalized: bool
    is_known: bool
    normal_form: str
    pos: str
    grammemes: frozenset[str]


@dataclass(frozen=True)
class RuTextAnalysis:
    text: str
    tokens: tuple[RuToken, ...]
    quoted_texts: tuple[str, ...]
    speaker_name: str
    speaker_gender: str


def evaluate_ru_quality(target_text: str, source_text: str, segment_type: str) -> dict:
    analysis = analyze_ru_text(target_text)
    flags: list[str] = []
    score = 1.0

    spelling_flags = _detect_spelling_like_errors(analysis, source_text)
    if spelling_flags:
        flags.extend(spelling_flags)
        score -= 0.65

    agreement_flags = _detect_predicative_gender_errors(analysis)
    if agreement_flags:
        flags.extend(agreement_flags)
        score -= 0.45

    return {
        "ru_quality_score": max(0.0, round(score, 4)),
        "ru_quality_flags": sorted(set(flags)),
    }


def evaluate_title_target_shape(target_text: str, segment_type: str) -> dict:
    if segment_type not in {"heading_title", "heading_chapter"}:
        return {"ru_quality_score": 1.0, "ru_quality_flags": []}
    target_tokens = {token.normalized for token in analyze_ru_text(target_text).tokens}
    if target_tokens & RU_DIRECTIONAL_TITLE_WORDS:
        return {"ru_quality_score": 0.45, "ru_quality_flags": ["target_directional_title"]}
    return {"ru_quality_score": 1.0, "ru_quality_flags": []}


def evaluate_ru_motion_drift(source_text: str, target_text: str) -> dict:
    source_lower = source_text.lower()
    target_tokens = {token.normalized for token in analyze_ru_text(target_text).tokens}
    flags: list[str] = []
    score = 1.0

    if "go" in source_lower or "goes" in source_lower or "went" in source_lower:
        if target_tokens & RU_TRANSPORT_WORDS:
            flags.append("target_motion_transport_drift")
            score -= 0.5
        elif target_tokens & RU_HABITUAL_MOTION_WORDS:
            flags.append("target_habitual_motion_drift")
            score -= 0.3

    return {
        "ru_quality_score": max(0.0, round(score, 4)),
        "ru_quality_flags": sorted(set(flags)),
    }


def evaluate_ru_speaker_gender(source_text: str, target_text: str) -> dict:
    analysis = analyze_ru_text(target_text)
    if _detect_predicative_gender_errors(analysis):
        return {"ru_quality_score": 0.55, "ru_quality_flags": ["ru_gender_mismatch"]}
    return {"ru_quality_score": 1.0, "ru_quality_flags": []}


def analyze_ru_text(text: str) -> RuTextAnalysis:
    raw_tokens = RU_WORD_RE.findall(text)
    tokens = tuple(
        _build_ru_token(token)
        for token in raw_tokens
    )
    quoted_texts = tuple(match.group(1).strip() for match in QUOTED_TEXT_RE.finditer(text) if match.group(1).strip())
    speaker_name = _extract_speaker_name(text)
    speaker_gender = _infer_name_gender(speaker_name)
    return RuTextAnalysis(
        text=text,
        tokens=tokens,
        quoted_texts=quoted_texts,
        speaker_name=speaker_name,
        speaker_gender=speaker_gender,
    )


def _extract_speaker_name(text: str) -> str:
    match = TARGET_SPEAKER_AFTER_VERB_RE.search(text)
    if match is not None:
        return str(match.group(1) or "")
    match = TARGET_SPEAKER_BEFORE_VERB_RE.search(text)
    if match is not None:
        return str(match.group(1) or "")
    return ""


def _infer_name_gender(name: str) -> str:
    normalized = name.strip().lower()
    if not normalized:
        return "unknown"
    token = _build_ru_token(name)
    if "femn" in token.grammemes:
        return "feminine"
    if "masc" in token.grammemes:
        return "masculine"
    if normalized.endswith(("а", "я")):
        return "feminine"
    return "unknown"


def _detect_spelling_like_errors(analysis: RuTextAnalysis, source_text: str) -> list[str]:
    flags: list[str] = []
    unknown_tokens = [
        token
        for token in analysis.tokens
        if not token.is_known and len(token.normalized) >= 4 and not token.is_capitalized
    ]
    if unknown_tokens:
        flags.append("ru_spelling_error")
    return flags


def _detect_predicative_gender_errors(analysis: RuTextAnalysis) -> list[str]:
    if analysis.speaker_gender != "feminine":
        return []
    if not analysis.quoted_texts:
        return []

    for quoted_text in analysis.quoted_texts:
        quoted_analysis = analyze_ru_text(quoted_text)
        quoted_tokens = list(quoted_analysis.tokens)
        if not quoted_tokens:
            continue
        normalized = [token.normalized for token in quoted_tokens]
        if "я" in normalized:
            for index, token in enumerate(normalized[:-1]):
                if token == "я" and _is_masculine_predicate_token(quoted_tokens[index + 1]):
                    return ["ru_gender_mismatch"]
        if _is_masculine_predicate_token(quoted_tokens[0]):
            return ["ru_gender_mismatch"]
    return []


def _build_ru_token(token: str) -> RuToken:
    normalized = token.lower()
    is_capitalized = bool(token[:1]) and token[:1].isupper()
    pos = ""
    grammemes: frozenset[str] = frozenset()
    normal_form = normalized
    is_known = True
    if _morph() is not None:
        parse = _morph().parse(token)[0]
        normal_form = str(parse.normal_form or normalized)
        pos = str(parse.tag.POS or "")
        grammemes = frozenset(str(item) for item in parse.tag.grammemes)
        is_known = bool(_morph().word_is_known(token))
    return RuToken(
        text=token,
        normalized=normalized,
        is_capitalized=is_capitalized,
        is_known=is_known,
        normal_form=normal_form,
        pos=pos,
        grammemes=grammemes,
    )


def _is_masculine_predicate_token(token: RuToken) -> bool:
    if token.pos in {"ADJF", "ADJS", "PRTS"} and "masc" in token.grammemes and "femn" not in token.grammemes:
        return True
    if token.normalized == "рад":
        return True
    return False


_MORPH = None


def _morph():
    global _MORPH
    if _MORPH is None and pymorphy3 is not None:  # pragma: no branch
        _MORPH = pymorphy3.MorphAnalyzer()
    return _MORPH
