from __future__ import annotations

"""Facade over the preserved V1 translation/alignment pipeline.

This module is the isolation point for the legacy core. New code should import
the old pipeline through this facade instead of reaching directly into
`segmenter.py`, `translator.py`, and `word_alignment.py`.
"""

from .segmenter import split_paragraphs, split_sentences, split_study_segments
from .translator import TranslationProvider, create_default_provider, translate_study_segments
from .word_alignment import (
    build_context_window,
    build_context_window_from_tokens,
    build_tap_word_payloads,
    build_word_mappings,
    tokenize_words,
)

__all__ = [
    "TranslationProvider",
    "build_context_window",
    "build_context_window_from_tokens",
    "build_tap_word_payloads",
    "build_word_mappings",
    "create_default_provider",
    "split_paragraphs",
    "split_sentences",
    "split_study_segments",
    "tokenize_words",
    "translate_study_segments",
]
