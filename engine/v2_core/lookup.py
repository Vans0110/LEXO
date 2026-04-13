from __future__ import annotations

from .models import LookupResult, LookupSource, LookupStatus, SourceAnalysisResult, SourceUnit, UnitType
from ..lexical_enrichment import direct_meaning_for_word, grammar_hint_for_word


PHRASE_TRANSLATIONS = {
    "wake up": ("просыпаться / просыпается", "фразовый глагол: проснуться или начать бодрствовать"),
    "wakes up": ("просыпается", "фразовый глагол: действие пробуждения"),
    "good morning": ("доброе утро", "устойчивая фраза приветствия"),
    "goodnight": ("спокойной ночи", "устойчивая фраза прощания перед сном"),
    "look at": ("смотреть на", "фразовый блок: направить взгляд на объект"),
    "have to": ("должен / нужно", "устойчивый блок обязательности"),
}
GRAMMAR_EXPLANATIONS = {
    "it is": ("это / это есть", "грамматический блок для сообщения о состоянии или характеристике"),
    "there is": ("есть / имеется", "грамматический блок существования"),
    "going to": ("собираться / намереваться", "грамматический блок ближайшего намерения"),
    "used to": ("раньше обычно", "грамматический блок привычного прошлого"),
    "do not": ("не", "грамматический блок отрицания"),
}
META_EXPLANATIONS = {
    "chapter": "мета-блок главы",
    "time": "мета-блок времени",
    "punctuation": "пунктуационный маркер",
}
LEXICAL_TRANSLATIONS = {
    "tom": "Том",
    "luna": "Луна",
    "anna": "Анна",
    "breakfast": "завтрак",
    "cat": "кот",
    "dog": "собака",
    "meow": "мяу",
    "sun": "солнце",
    "bright": "яркий / яркое",
    "happy": "счастливый / счастлив",
    "friendly": "дружелюбный",
    "kitchen": "кухня",
    "flowers": "цветы",
    "flower": "цветок",
    "trees": "деревья",
    "tree": "дерево",
    "toast": "тост",
    "eggs": "яйца",
    "egg": "яйцо",
    "juice": "сок",
    "orange": "апельсиновый / апельсин",
    "park": "парк",
    "home": "дом",
    "book": "книга",
    "sofa": "диван",
    "window": "окно",
    "garden": "сад",
    "friend": "друг",
    "day": "день",
    "beautiful": "красивый",
    "morning": "утро",
    "new": "новый",
    "sunny": "солнечный",
    "special": "особенный",
    "saturday": "суббота",
    "afternoon": "день / после полудня",
    "hill": "холм",
    "says": "говорит",
    "makes": "делает / готовит",
    "thinks": "думает",
    "asks": "спрашивает",
    "walk": "идти пешком",
    "walks": "идет пешком",
    "goes": "идет",
    "reads": "читает",
    "sleeps": "спит",
    "wears": "носит",
    "drinks": "пьёт",
    "looks": "смотрит",
    "whispers": "шепчет",
}


class V2LookupResolver:
    """Type-aware lookup resolver for the V2 core.

    This layer intentionally does not depend on target matching. It provides a
    stable lookup/explanation payload even when target coverage is weak or
    absent.
    """

    def resolve_analysis(self, analysis: SourceAnalysisResult) -> dict[str, LookupResult]:
        return {unit.unit_id: self.resolve_unit(unit) for unit in analysis.units}

    def resolve_unit(self, unit: SourceUnit) -> LookupResult:
        if unit.attached_to_unit_id:
            return LookupResult(
                unit_id=unit.unit_id,
                status=LookupStatus.GUESSED,
                base_translation="",
                alt_translations=[],
                explanation="токен принадлежит owner unit и не должен объясняться отдельно",
                source=LookupSource.PATTERN_RULE,
            )

        if unit.type == UnitType.PHRASE:
            return self._resolve_phrase(unit)
        if unit.type == UnitType.GRAMMAR:
            return self._resolve_grammar(unit)
        if unit.type == UnitType.FUNCTION:
            return self._resolve_function(unit)
        if unit.type == UnitType.META:
            return self._resolve_meta(unit)
        return self._resolve_lexical(unit)

    def _resolve_phrase(self, unit: SourceUnit) -> LookupResult:
        key = unit.source_text.lower()
        translation, explanation = PHRASE_TRANSLATIONS.get(key, ("", "устойчивый или составной блок"))
        status = LookupStatus.FOUND if translation else LookupStatus.MISSING
        return LookupResult(
            unit_id=unit.unit_id,
            status=status,
            base_translation=translation,
            alt_translations=[],
            explanation=explanation,
            source=LookupSource.PHRASE_DICT,
        )

    def _resolve_grammar(self, unit: SourceUnit) -> LookupResult:
        key = unit.source_text.lower()
        translation, explanation = GRAMMAR_EXPLANATIONS.get(key, ("", "грамматическая схема, смысл которой задаётся конструкцией"))
        status = LookupStatus.FOUND if translation else LookupStatus.GUESSED
        return LookupResult(
            unit_id=unit.unit_id,
            status=status,
            base_translation=translation,
            alt_translations=[],
            explanation=explanation,
            source=LookupSource.GRAMMAR_RULES,
        )

    def _resolve_function(self, unit: SourceUnit) -> LookupResult:
        word = {
            "text": unit.source_text,
            "surface_text": unit.source_text,
            "normalized_text": unit.source_text.lower(),
            "pos": self._pos_for_function(unit.source_text.lower()),
        }
        translation = str(direct_meaning_for_word(word) or "")
        explanation = str(grammar_hint_for_word(word) or "служебное слово, которое лучше объяснять, а не переводить буквально")
        return LookupResult(
            unit_id=unit.unit_id,
            status=LookupStatus.FOUND if translation or explanation else LookupStatus.MISSING,
            base_translation=translation,
            alt_translations=[],
            explanation=explanation,
            source=LookupSource.FUNCTION_RULES,
        )

    def _resolve_meta(self, unit: SourceUnit) -> LookupResult:
        meta_kind = str(unit.metadata.get("meta_kind") or "")
        explanation = META_EXPLANATIONS.get(meta_kind, "мета-единица текста")
        translation = self._meta_translation(unit.source_text, meta_kind)
        return LookupResult(
            unit_id=unit.unit_id,
            status=LookupStatus.FOUND if explanation else LookupStatus.GUESSED,
            base_translation=translation,
            alt_translations=[],
            explanation=explanation,
            source=LookupSource.PATTERN_RULE,
        )

    def _resolve_lexical(self, unit: SourceUnit) -> LookupResult:
        key = unit.source_text.lower()
        translation = LEXICAL_TRANSLATIONS.get(key, "")
        if translation:
            return LookupResult(
                unit_id=unit.unit_id,
                status=LookupStatus.FOUND,
                base_translation=translation,
                alt_translations=[],
                explanation="лексическая единица",
                source=LookupSource.LEMMA_DICT,
            )
        return LookupResult(
            unit_id=unit.unit_id,
            status=LookupStatus.MISSING,
            base_translation="",
            alt_translations=[],
            explanation="лексическая единица без готового lookup; нужен словарь или curated lookup",
            source=LookupSource.LEMMA_DICT,
        )

    def _pos_for_function(self, normalized: str) -> str:
        if normalized in {"the", "a", "an"}:
            return "DET"
        if normalized in {"in", "on", "to", "of", "at", "for", "with"}:
            return "ADP"
        if normalized in {"is", "are", "was", "were", "am", "be"}:
            return "AUX"
        if normalized in {"he", "she", "it", "they", "we", "i", "you"}:
            return "PRON"
        return "PART"

    def _meta_translation(self, source_text: str, meta_kind: str) -> str:
        normalized = source_text.strip()
        if meta_kind == "chapter":
            parts = normalized.split(maxsplit=1)
            if len(parts) == 2:
                return f"Глава {parts[1]}"
            return "Глава"
        if meta_kind == "time":
            upper = normalized.upper()
            if upper.endswith(" AM"):
                return f"{normalized[:-3].strip()} утра"
            if upper.endswith(" PM"):
                return f"{normalized[:-3].strip()} вечера"
            return normalized
        return ""
