from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Any

import torch
import torch.nn.functional as F

from .config import MULTILINGUAL_E5_SMALL_DIR


@dataclass(frozen=True)
class SemanticRerankResult:
    selected: str
    score: float
    explanation: dict


@lru_cache(maxsize=1)
def _load_e5() -> tuple[Any, Any] | None:
    if not MULTILINGUAL_E5_SMALL_DIR.exists():
        return None
    try:
        from transformers import AutoModel, AutoTokenizer

        tokenizer = AutoTokenizer.from_pretrained(
            str(MULTILINGUAL_E5_SMALL_DIR),
            local_files_only=True,
        )
        model = AutoModel.from_pretrained(
            str(MULTILINGUAL_E5_SMALL_DIR),
            local_files_only=True,
        )
        model.eval()
        return tokenizer, model
    except Exception:
        return None


class SemanticTranslationReranker:
    @property
    def is_available(self) -> bool:
        return _load_e5() is not None

    def select(self, source_text: str, candidates: list[str]) -> SemanticRerankResult:
        clean_candidates = [candidate.strip() for candidate in candidates if candidate and candidate.strip()]
        if not clean_candidates:
            return SemanticRerankResult("", 0.0, {"reason": "no_candidates"})
        loaded = _load_e5()
        if loaded is None:
            return SemanticRerankResult(clean_candidates[0], 0.0, {"reason": "model_unavailable"})

        source_embedding = self._embed([f"query: {source_text}"])
        candidate_embeddings = self._embed([f"passage: {candidate}" for candidate in clean_candidates])
        scores = (candidate_embeddings @ source_embedding.T).squeeze(1)
        ranked = sorted(
            [
                {
                    "text": candidate,
                    "score": float(score),
                    "rank": index,
                }
                for index, (candidate, score) in enumerate(zip(clean_candidates, scores))
            ],
            key=lambda item: (item["score"], -item["rank"]),
            reverse=True,
        )
        selected = ranked[0]
        return SemanticRerankResult(
            selected=selected["text"],
            score=selected["score"],
            explanation={
                "source": source_text,
                "model": "intfloat/multilingual-e5-small",
                "selected": selected["text"],
                "score": selected["score"],
                "candidates": ranked,
            },
        )

    def _embed(self, texts: list[str]) -> torch.Tensor:
        loaded = _load_e5()
        if loaded is None:
            raise RuntimeError("multilingual-e5-small is not available")
        tokenizer, model = loaded
        with torch.no_grad():
            batch = tokenizer(
                texts,
                max_length=128,
                padding=True,
                truncation=True,
                return_tensors="pt",
            )
            output = model(**batch)
            attention_mask = batch["attention_mask"]
            embeddings = self._average_pool(output.last_hidden_state, attention_mask)
            return F.normalize(embeddings, p=2, dim=1)

    def _average_pool(self, last_hidden_states: torch.Tensor, attention_mask: torch.Tensor) -> torch.Tensor:
        masked = last_hidden_states.masked_fill(~attention_mask[..., None].bool(), 0.0)
        return masked.sum(dim=1) / attention_mask.sum(dim=1)[..., None].clamp(min=1)
