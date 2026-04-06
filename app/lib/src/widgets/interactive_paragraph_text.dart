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
    final baseStyle = const TextStyle(fontSize: 18, height: 1.7);
    final highlightColor = Theme.of(context).colorScheme.primary.withOpacity(0.18);
    final defaultColor = Theme.of(context).colorScheme.onSurface;
    final wordById = {for (final word in words) word.id: word};

    return RichText(
      text: TextSpan(
        children: [
          for (final token in tokens)
            () {
              final word = token.wordId == null ? null : wordById[token.wordId];
              final isSelected = token.tapUnitId != null && token.tapUnitId == selectedTapUnitId;
              final style = baseStyle.copyWith(
                color: defaultColor,
                fontWeight: token.isWord && isSelected ? FontWeight.w700 : FontWeight.w400,
                backgroundColor: isSelected ? highlightColor : null,
              );
              if (word == null) {
                return TextSpan(text: token.text, style: style);
              }
              return WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: () => onWordTap(word),
                  onLongPress: () => onWordLongPress(word),
                  child: Text(
                    token.text,
                    style: style,
                  ),
                ),
              );
            }(),
        ],
      ),
    );
  }
}
