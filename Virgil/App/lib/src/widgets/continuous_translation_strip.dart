import 'package:flutter/material.dart';

import '../models.dart';
import 'translation_context_bar.dart';

class _TargetStreamToken {
  const _TargetStreamToken({
    required this.text,
    required this.segmentId,
    required this.globalIndex,
  });

  final String text;
  final String segmentId;
  final int globalIndex;
}

class ContinuousTranslationStrip extends StatelessWidget {
  const ContinuousTranslationStrip({
    super.key,
    required this.item,
    required this.selectedTapUnitId,
    required this.translationLeftText,
    required this.translationFocusText,
    required this.translationRightText,
  });

  final ParagraphItem? item;
  final String? selectedTapUnitId;
  final String? translationLeftText;
  final String? translationFocusText;
  final String? translationRightText;

  @override
  Widget build(BuildContext context) {
    final paragraph = item;
    if (paragraph == null) {
      return TranslationContextBar(
        leftText: translationLeftText,
        focusText: translationFocusText,
        rightText: translationRightText,
      );
    }

    final selectedWord = _resolveSelectedWord(paragraph);
    final targetStream = _buildTargetStream(paragraph);
    if (selectedWord == null || targetStream.isEmpty) {
      return _buildFallbackBar(context, _fallbackText(paragraph));
    }

    final selection = _resolveSelection(
      paragraph: paragraph,
      selectedWord: selectedWord,
      targetStream: targetStream,
    );
    final segment = _fullSegment(targetStream, selectedWord.segmentId);
    if (segment.isEmpty) {
      return _buildFallbackBar(context, _fallbackText(paragraph));
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 94),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Center(
            child: Text.rich(
              TextSpan(
                style: TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                children: [
                  for (var index = 0; index < segment.length; index++) ...[
                    if (index > 0) const TextSpan(text: ' '),
                    TextSpan(
                      text: segment[index].text,
                      style: selection != null &&
                              segment[index].globalIndex >= selection.$1 &&
                              segment[index].globalIndex <= selection.$2
                          ? const TextStyle(fontWeight: FontWeight.w700)
                          : null,
                    ),
                  ],
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  String _fallbackText(ParagraphItem paragraph) {
    return paragraph.targetText;
  }

  ParagraphWordItem? _resolveSelectedWord(ParagraphItem paragraph) {
    final tapUnitId = selectedTapUnitId?.trim() ?? '';
    if (tapUnitId.isEmpty) {
      return null;
    }
    for (final word in paragraph.words) {
      if (word.tapUnitId == tapUnitId) {
        return word;
      }
    }
    return null;
  }

  List<_TargetStreamToken> _buildTargetStream(ParagraphItem paragraph) {
    final tokens = <_TargetStreamToken>[];
    for (final segment in paragraph.segmentsV2) {
      final rawTokens =
          (segment.segmentAlignment['target_tokens'] as List<dynamic>? ??
              const []);
      for (final rawToken in rawTokens) {
        final text = rawToken is String ? rawToken.trim() : '';
        if (text.isEmpty) {
          continue;
        }
        tokens.add(
          _TargetStreamToken(
            text: text,
            segmentId: segment.id,
            globalIndex: tokens.length,
          ),
        );
      }
    }
    return tokens;
  }

  (int, int)? _resolveSelection({
    required ParagraphItem paragraph,
    required ParagraphWordItem selectedWord,
    required List<_TargetStreamToken> targetStream,
  }) {
    final segmentId = selectedWord.segmentId?.trim() ?? '';
    if (segmentId.isEmpty) {
      return null;
    }
    final hasDisplayHighlight = selectedWord.highlightTargetStartIndex >= 0 &&
        selectedWord.highlightTargetEndIndex >=
            selectedWord.highlightTargetStartIndex;
    final startInSegment = hasDisplayHighlight
        ? selectedWord.highlightTargetStartIndex
        : selectedWord.targetStartIndex;
    final endInSegment = hasDisplayHighlight
        ? selectedWord.highlightTargetEndIndex
        : selectedWord.targetEndIndex;
    if (startInSegment < 0 || endInSegment < 0) {
      return null;
    }
    final offset = _segmentOffset(targetStream, segmentId);
    if (offset < 0) {
      return null;
    }
    final start = offset + startInSegment;
    final end = offset + endInSegment;
    if (start >= targetStream.length || end >= targetStream.length) {
      return null;
    }
    return (start, end);
  }

  int _segmentOffset(List<_TargetStreamToken> targetStream, String segmentId) {
    for (final token in targetStream) {
      if (token.segmentId == segmentId) {
        return token.globalIndex;
      }
    }
    return -1;
  }

  List<_TargetStreamToken> _fullSegment(
    List<_TargetStreamToken> targetStream,
    String? segmentId,
  ) {
    final id = segmentId?.trim() ?? '';
    return targetStream.where((token) => token.segmentId == id).toList();
  }

  Widget _buildFallbackBar(BuildContext context, String text) {
    final trimmed = text.trim();
    return SizedBox(
      height: 94,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Center(
            child: trimmed.isEmpty
                ? const Text(
                    'Tap a word to see translation',
                    style: TextStyle(fontSize: 15),
                  )
                : Text(
                    trimmed,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      height: 1.3,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
