import 'package:flutter/material.dart';

import '../models.dart';

class InteractiveParagraphText extends StatelessWidget {
  const InteractiveParagraphText({
    super.key,
    required this.tokens,
    required this.words,
    required this.onWordTap,
    required this.onWordLongPress,
    this.selectedTapUnitId,
  });

  final List<ParagraphTokenItem> tokens;
  final List<ParagraphWordItem> words;
  final String? selectedTapUnitId;
  final void Function(ParagraphWordItem word) onWordTap;
  final void Function(ParagraphWordItem word) onWordLongPress;

  @override
  Widget build(BuildContext context) {
    const baseStyle = TextStyle(fontSize: 18, height: 1.7);
    final highlightColor =
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.18);
    final defaultColor = Theme.of(context).colorScheme.onSurface;
    const wordHighlightPadding =
        EdgeInsets.symmetric(horizontal: 2, vertical: 1);
    final wordById = {for (final word in words) word.id: word};
    final unitWordById = <String, ParagraphWordItem>{};
    for (final word in words) {
      unitWordById.putIfAbsent(word.tapUnitId, () => word);
    }
    final firstTokenIndexByUnit = <String, int>{};
    final lastTokenIndexByUnit = <String, int>{};
    for (var index = 0; index < tokens.length; index++) {
      final tapUnitId = tokens[index].tapUnitId;
      if (tapUnitId == null || tapUnitId.isEmpty) {
        continue;
      }
      firstTokenIndexByUnit.putIfAbsent(tapUnitId, () => index);
      lastTokenIndexByUnit[tapUnitId] = index;
    }

    String? joinedUnitIdForWhitespace(int index) {
      if (tokens[index].text.trim().isNotEmpty ||
          index == 0 ||
          index == tokens.length - 1) {
        return null;
      }
      final leftUnitId = tokens[index - 1].tapUnitId;
      final rightUnitId = tokens[index + 1].tapUnitId;
      if (leftUnitId == null ||
          leftUnitId.isEmpty ||
          leftUnitId != rightUnitId) {
        return null;
      }
      return leftUnitId;
    }

    return RichText(
      text: TextSpan(
        children: [
          for (var index = 0; index < tokens.length; index++)
            () {
              final token = tokens[index];
              final word = token.wordId == null ? null : wordById[token.wordId];
              final unitWord = token.tapUnitId == null
                  ? null
                  : unitWordById[token.tapUnitId!];
              final isSelected = token.tapUnitId != null &&
                  token.tapUnitId == selectedTapUnitId;
              final isFirstInUnit = token.tapUnitId != null &&
                  firstTokenIndexByUnit[token.tapUnitId] == index;
              final isLastInUnit = token.tapUnitId != null &&
                  lastTokenIndexByUnit[token.tapUnitId] == index;
              final joinedWhitespaceUnitId = joinedUnitIdForWhitespace(index);
              final isSelectedGroupWhitespace =
                  joinedWhitespaceUnitId != null &&
                      joinedWhitespaceUnitId == selectedTapUnitId;
              final style = baseStyle.copyWith(
                color: defaultColor,
                fontWeight: FontWeight.w400,
              );
              final decoration = isSelected
                  ? BoxDecoration(
                      color: highlightColor,
                      borderRadius: BorderRadius.horizontal(
                        left: isFirstInUnit
                            ? const Radius.circular(6)
                            : Radius.zero,
                        right: isLastInUnit
                            ? const Radius.circular(6)
                            : Radius.zero,
                      ),
                    )
                  : null;
              final isStandaloneFunctionWord = word?.isFunctionWord == true &&
                  (token.tapUnitId?.trim().isEmpty ?? true);
              if (isSelectedGroupWhitespace) {
                return WidgetSpan(
                  alignment: PlaceholderAlignment.baseline,
                  baseline: TextBaseline.alphabetic,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    color: highlightColor,
                    child: Text(token.text, style: style),
                  ),
                );
              }
              if ((word == null || isStandaloneFunctionWord) &&
                  unitWord == null) {
                return TextSpan(
                  text: token.text,
                  style: style,
                );
              }
              return WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () {
                    final tapWord = unitWord ?? word;
                    if (tapWord == null) {
                      return;
                    }
                    onWordTap(tapWord);
                  },
                  onLongPress:
                      word == null ? null : () => onWordLongPress(word),
                  child: Container(
                    padding: wordHighlightPadding,
                    decoration: decoration ??
                        const BoxDecoration(color: Colors.transparent),
                    child: Text(
                      token.text,
                      style: style,
                    ),
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}
