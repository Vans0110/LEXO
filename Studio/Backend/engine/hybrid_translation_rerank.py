from __future__ import annotations

from dataclasses import dataclass

from .semantic_translation_rerank import SemanticTranslationReranker
from .structural_translation_rerank import StructuralTranslationReranker


@dataclass(frozen=True)
class HybridRerankResult:
    selected: str
    score: float
    explanation: dict


class HybridTranslationReranker:
    def __init__(self) -> None:
        self.semantic = SemanticTranslationReranker()
        self.structural = StructuralTranslationReranker()

    def select(self, source_text: str, target_lang: str, candidates: list[str]) -> HybridRerankResult:
        clean_candidates = [candidate.strip() for candidate in candidates if candidate and candidate.strip()]
        if not clean_candidates:
            return HybridRerankResult("", 0.0, {"reason": "no_candidates"})

        semantic = self.semantic.select(source_text, clean_candidates)
        structural = self.structural.select(source_text, target_lang, clean_candidates)
        semantic_scores = {
            item["text"]: float(item["score"])
            for item in semantic.explanation.get("candidates", [])
        }
        structural_scores = {
            item["text"]: float(item["score"])
            for item in structural.explanation.get("candidates", [])
        }
        semantic_norm = self._normalize(semantic_scores)
        structural_norm = self._normalize(structural_scores)
        ranked = []
        total = max(1, len(clean_candidates) - 1)
        for index, candidate in enumerate(clean_candidates):
            rank_score = 1.0 - (index / total if total else 0.0)
            punctuation_penalty = 0.15 if candidate.lstrip().startswith("-") else 0.0
            score = (
                semantic_norm.get(candidate, 0.0) * 0.42
                + structural_norm.get(candidate, 0.0) * 0.46
                + rank_score * 0.12
                - punctuation_penalty
            )
            ranked.append(
                {
                    "text": candidate,
                    "score": score,
                    "semantic_score": semantic_scores.get(candidate, 0.0),
                    "structural_score": structural_scores.get(candidate, 0.0),
                    "rank_score": rank_score,
                    "punctuation_penalty": punctuation_penalty,
                }
            )
        ranked.sort(key=lambda item: item["score"], reverse=True)
        selected = ranked[0]
        return HybridRerankResult(
            selected=selected["text"],
            score=float(selected["score"]),
            explanation={
                "source": source_text,
                "target_lang": target_lang,
                "selected": selected["text"],
                "score": selected["score"],
                "semantic_selected": semantic.selected,
                "structural_selected": structural.selected,
                "candidates": ranked,
            },
        )

    def _normalize(self, scores: dict[str, float]) -> dict[str, float]:
        if not scores:
            return {}
        values = list(scores.values())
        low = min(values)
        high = max(values)
        if high <= low:
            return {key: 1.0 for key in scores}
        return {key: (value - low) / (high - low) for key, value in scores.items()}
