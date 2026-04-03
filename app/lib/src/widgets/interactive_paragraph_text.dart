import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models.dart';

class InteractiveParagraphText extends StatelessWidget {
  const InteractiveParagraphText({
    super.key,
    required this.sourceText,
    required this.words,
    required this.onWordTap,
    this.selectedTapUnitId,
  });

  final String sourceText;
  final List<ParagraphWordItem> words;
  final String? selectedTapUnitId;
  final void Function(ParagraphWordItem word) onWordTap;

  @override
  Widget build(BuildContext context) {
    final baseStyle = const TextStyle(fontSize: 18, height: 1.7);
    final highlightColor = Theme.of(context).colorScheme.primary.withOpacity(0.18);
    final defaultColor = Theme.of(context).colorScheme.onSurface;
    final tokens = _tokenize(sourceText);
    var wordIndex = 0;
    ParagraphWordItem? previousWord;

    return RichText(
      text: TextSpan(
        children: [
          for (final token in tokens)
            if (token.isWord)
              () {
                final word = wordIndex < words.length ? words[wordIndex] : null;
                wordIndex += 1;
                final isSelected = word != null && word.tapUnitId == selectedTapUnitId;
                previousWord = word;
                return TextSpan(
                  text: word?.text ?? token.text,
                  recognizer: word == null ? null : (TapGestureRecognizer()..onTap = () => onWordTap(word)),
                  style: baseStyle.copyWith(
                    color: defaultColor,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                    backgroundColor: isSelected ? highlightColor : null,
                  ),
                );
              }()
            else
              () {
                final highlightSpace =
                    previousWord != null &&
                    previousWord!.tapUnitId == selectedTapUnitId &&
                    wordIndex < words.length &&
                    words[wordIndex].tapUnitId == selectedTapUnitId;
                return TextSpan(
                  text: token.text,
                  style: baseStyle.copyWith(
                    color: defaultColor,
                    backgroundColor: highlightSpace ? highlightColor : null,
                  ),
                );
              }(),
        ],
      ),
    );
  }
}

class _ParagraphToken {
  const _ParagraphToken(this.text, this.isWord);

  final String text;
  final bool isWord;
}

List<_ParagraphToken> _tokenize(String text) {
  final pattern = RegExp(r"[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)*|[^A-Za-z0-9]+");
  final matches = pattern.allMatches(text);
  return [
    for (final match in matches)
      _ParagraphToken(
        match.group(0) ?? '',
        RegExp(r"^[A-Za-z0-9]+(?:[-'][A-Za-z0-9]+)*$").hasMatch(match.group(0) ?? ''),
      ),
  ];
}
