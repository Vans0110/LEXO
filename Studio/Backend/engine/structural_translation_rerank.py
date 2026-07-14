from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
from typing import Any

from .config import STANZA_RESOURCES_DIR
from .tokenization import WORD_RE


CONTENT_UPOS = {"PROPN", "PRON", "NUM", "NOUN", "ADJ", "VERB", "ADV"}
WEAK_UPOS = {"AUX", "DET", "ADP", "CCONJ", "SCONJ", "PART"}
FINITE_VERB_UPOS = {"VERB", "AUX"}
BUCKET_WEIGHTS = {
    "PROPN": 0.2,
    "NOUN": 0.16,
    "VERB": 0.16,
    "ADJ": 0.12,
    "ADV": 0.08,
    "NUM": 0.22,
    "PRON": 0.14,
    "POSSESSIVE": 0.28,
    "NEGATION": 0.3,
}
@dataclass(frozen=True)
class StructuralRerankResult:
    selected: str
    score: float
    explanation: dict


@lru_cache(maxsize=1)
def _load_en_model() -> Any | None:
    try:
        import spacy

        return spacy.load("en_core_web_sm")
    except Exception:
        return None


@lru_cache(maxsize=2)
def _load_target_model(lang: str) -> Any | None:
    try:
        import stanza

        return stanza.Pipeline(
            lang=lang,
            processors="tokenize,pos,lemma,depparse",
            dir=str(STANZA_RESOURCES_DIR),
            use_gpu=False,
            verbose=False,
        )
    except Exception:
        return None


class StructuralTranslationReranker:
    def select(self, source_text: str, target_lang: str, candidates: list[str]) -> StructuralRerankResult:
        clean_candidates = [candidate.strip() for candidate in candidates if candidate and candidate.strip()]
        if not clean_candidates:
            return StructuralRerankResult("", 0.0, {"reason": "no_candidates"})

        source = self._analyze_source(source_text)
        scored: list[tuple[str, float, dict]] = []
        for index, candidate in enumerate(clean_candidates):
            target = self._analyze_target(target_lang, candidate)
            score, detail = self._score(source, target, index)
            scored.append((candidate, score, detail))

        scored.sort(key=lambda item: item[1], reverse=True)
        selected, score, detail = scored[0]
        return StructuralRerankResult(
            selected=selected,
            score=score,
            explanation={
                "source": source,
                "target_lang": target_lang,
                "selected": selected,
                "score": score,
                "winner_detail": detail,
                "candidates": [
                    {"text": candidate, "score": candidate_score, **candidate_detail}
                    for candidate, candidate_score, candidate_detail in scored
                ],
            },
        )

    def _score(self, source: dict, target: dict, rank_index: int) -> tuple[float, dict]:
        score = 0.0
        reasons: list[dict] = []
        source_content_count = max(1, source["content_count"])
        target_content_count = max(1, target["content_count"])

        source_upos = set(source["content_upos"])
        target_upos = set(target["content_upos"])
        required = source_upos - {"AUX"}
        covered = required & target_upos
        if required:
            coverage = len(covered) / len(required)
            score += coverage * 1.2
            reasons.append({"type": "upos_coverage", "value": coverage})

        count_ratio = target_content_count / source_content_count
        count_score = max(-0.3, 0.3 - abs(1.0 - min(count_ratio, 2.0)) * 0.3)
        score += count_score
        reasons.append({"type": "content_count_ratio", "ratio": count_ratio, "value": count_score})

        extra_weak = max(0, target["weak_count"] - source["weak_count"])
        if extra_weak:
            penalty = min(0.24, extra_weak * 0.08)
            score -= penalty
            reasons.append({"type": "extra_weak_upos", "count": extra_weak, "value": -penalty})

        if target["has_finite_verb"]:
            score += 0.12
            reasons.append({"type": "finite_verb", "value": 0.12})

        if target["has_noun_root_without_finite_verb"] and target["has_dative_pronoun"]:
            score += 0.35
            reasons.append({"type": "dative_pronoun_verbless_noun_root", "value": 0.35})

        if target["has_noun_root_without_finite_verb"] and target["has_nominative_subject_pronoun"]:
            score -= 0.35
            reasons.append({"type": "nominative_subject_verbless_noun_root", "value": -0.35})

        if source["has_pronoun"] and not target["has_pronoun"]:
            score -= 0.2
            reasons.append({"type": "missing_pronoun_shape", "value": -0.2})

        bucket_score, bucket_reasons = self._bucket_count_score(
            source["bucket_counts"],
            target["bucket_counts"],
        )
        score += bucket_score
        reasons.extend(bucket_reasons)

        rank_penalty = rank_index * 0.035
        score -= rank_penalty
        reasons.append({"type": "nllb_rank_penalty", "rank": rank_index, "value": -rank_penalty})

        return score, {"target": target, "reasons": reasons}

    def _bucket_count_score(
        self,
        source_counts: dict[str, int],
        target_counts: dict[str, int],
    ) -> tuple[float, list[dict]]:
        score = 0.0
        reasons: list[dict] = []
        for bucket, source_count in source_counts.items():
            if source_count <= 0:
                continue
            target_count = target_counts.get(bucket, 0)
            missing = max(0, source_count - target_count)
            extra = max(0, target_count - source_count)
            weight = BUCKET_WEIGHTS.get(bucket, 0.08)
            if missing:
                penalty = missing * weight
                score -= penalty
                reasons.append({
                    "type": "missing_bucket",
                    "bucket": bucket,
                    "source": source_count,
                    "target": target_count,
                    "value": -penalty,
                })
            else:
                bonus = min(source_count, target_count) * weight * 0.35
                score += bonus
                reasons.append({
                    "type": "covered_bucket",
                    "bucket": bucket,
                    "source": source_count,
                    "target": target_count,
                    "value": bonus,
                })
            if extra and bucket in {"ADJ", "ADV", "NUM", "NEGATION"}:
                penalty = min(extra * weight * 0.45, 0.25)
                score -= penalty
                reasons.append({
                    "type": "extra_bucket",
                    "bucket": bucket,
                    "source": source_count,
                    "target": target_count,
                    "value": -penalty,
                })
        return score, reasons

    def _analyze_source(self, text: str) -> dict:
        nlp = _load_en_model()
        if nlp is None:
            tokens = WORD_RE.findall(str(text or ""))
            return {
                "tokens": [{"text": token, "upos": "", "dep": "", "feats": ""} for token in tokens],
                "content_upos": [],
                "content_count": len(tokens),
                "weak_count": 0,
                "bucket_counts": {},
                "has_pronoun": False,
            }
        doc = nlp(str(text or ""))
        token_payloads = []
        for token in doc:
            if token.is_space or token.is_punct:
                continue
            token_payloads.append(
                {
                    "text": token.text,
                    "lemma": token.lemma_,
                    "upos": token.pos_,
                    "tag": token.tag_,
                    "dep": token.dep_,
                    "head": token.head.text,
                    "feats": "",
                }
            )
        return self._shape(token_payloads)

    def _analyze_target(self, lang: str, text: str) -> dict:
        nlp = _load_target_model(lang)
        if nlp is None:
            tokens = WORD_RE.findall(str(text or ""))
            return {
                "tokens": [{"text": token, "upos": "", "dep": "", "feats": ""} for token in tokens],
                "content_upos": [],
                "content_count": len(tokens),
                "weak_count": 0,
                "bucket_counts": {},
                "has_pronoun": False,
                "has_finite_verb": False,
                "has_noun_root_without_finite_verb": False,
                "has_dative_pronoun": False,
                "has_nominative_subject_pronoun": False,
            }
        doc = nlp(str(text or ""))
        token_payloads = []
        for sentence in doc.sentences:
            for word in sentence.words:
                if word.upos == "PUNCT":
                    continue
                head = sentence.words[word.head - 1].text if word.head else "ROOT"
                token_payloads.append(
                    {
                        "text": word.text,
                        "lemma": word.lemma or "",
                        "upos": word.upos or "",
                        "dep": word.deprel or "",
                        "head": head,
                        "feats": word.feats or "",
                    }
                )
        return self._shape(token_payloads)

    def _shape(self, tokens: list[dict]) -> dict:
        content = [token for token in tokens if token.get("upos") in CONTENT_UPOS]
        weak = [token for token in tokens if token.get("upos") in WEAK_UPOS]
        has_finite_verb = any(
            token.get("upos") in FINITE_VERB_UPOS and "VerbForm=Fin" in token.get("feats", "")
            for token in tokens
        )
        if not has_finite_verb:
            has_finite_verb = any(token.get("upos") in FINITE_VERB_UPOS for token in tokens)
        has_root_noun = any(token.get("upos") == "NOUN" and token.get("dep") == "root" for token in tokens)
        return {
            "tokens": tokens,
            "content_upos": [token.get("upos", "") for token in content],
            "content_count": len(content),
            "weak_count": len(weak),
            "bucket_counts": self._bucket_counts(tokens),
            "has_pronoun": any(token.get("upos") == "PRON" for token in tokens),
            "has_finite_verb": has_finite_verb,
            "has_noun_root_without_finite_verb": has_root_noun and not has_finite_verb,
            "has_dative_pronoun": any(
                token.get("upos") == "PRON" and "Case=Dat" in token.get("feats", "")
                for token in tokens
            ),
            "has_nominative_subject_pronoun": any(
                token.get("upos") == "PRON"
                and "Case=Nom" in token.get("feats", "")
                and str(token.get("dep", "")).startswith("nsubj")
                for token in tokens
            ),
        }

    def _bucket_counts(self, tokens: list[dict]) -> dict[str, int]:
        counts: dict[str, int] = {}
        for token in tokens:
            bucket = self._bucket_for_token(token)
            if bucket:
                counts[bucket] = counts.get(bucket, 0) + 1
        return counts

    def _bucket_for_token(self, token: dict) -> str:
        upos = str(token.get("upos") or "")
        tag = str(token.get("tag") or "")
        dep = str(token.get("dep") or "")
        feats = str(token.get("feats") or "")
        if "Polarity=Neg" in feats:
            return "NEGATION"
        if tag == "PRP$" or dep == "poss" or "Poss=Yes" in feats:
            return "POSSESSIVE"
        if upos in {"PROPN", "NOUN", "VERB", "ADJ", "ADV", "NUM", "PRON"}:
            return upos
        return ""
