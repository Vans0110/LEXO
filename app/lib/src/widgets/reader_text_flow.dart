import 'package:flutter/material.dart';

import '../models.dart';
import 'interactive_paragraph_text.dart';
import 'translation_context_bar.dart';

class ReaderTextFlow extends StatelessWidget {
  const ReaderTextFlow({
    super.key,
    required this.payload,
    required this.translationLeftText,
    required this.translationFocusText,
    required this.translationRightText,
    required this.selectedParagraphIndex,
    required this.selectedTapUnitId,
    required this.onWordTap,
    required this.onWordLongPress,
  });

  final ReaderPayload payload;
  final String? translationLeftText;
  final String? translationFocusText;
  final String? translationRightText;
  final int? selectedParagraphIndex;
  final String? selectedTapUnitId;
  final void Function(ParagraphItem item, ParagraphWordItem word) onWordTap;
  final void Function(ParagraphItem item, ParagraphWordItem word) onWordLongPress;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        children: [
          TranslationContextBar(
            leftText: translationLeftText,
            focusText: translationFocusText,
            rightText: translationRightText,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: payload.paragraphs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 18),
              itemBuilder: (context, index) {
                final item = payload.paragraphs[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: InteractiveParagraphText(
                    tokens: item.tokens,
                    words: item.words,
                    selectedTapUnitId: selectedParagraphIndex == item.index
                        ? selectedTapUnitId
                        : null,
                    onWordTap: (word) => onWordTap(item, word),
                    onWordLongPress: (word) => onWordLongPress(item, word),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
