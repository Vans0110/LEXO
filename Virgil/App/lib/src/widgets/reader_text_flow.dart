import 'package:flutter/material.dart';

import '../models.dart';
import 'continuous_translation_strip.dart';
import 'interactive_paragraph_text.dart';

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
    this.bottomContentPadding = 0,
  });

  final ReaderPayload payload;
  final String? translationLeftText;
  final String? translationFocusText;
  final String? translationRightText;
  final int? selectedParagraphIndex;
  final String? selectedTapUnitId;
  final void Function(ParagraphItem item, ParagraphWordItem word) onWordTap;
  final void Function(ParagraphItem item, ParagraphWordItem word)
      onWordLongPress;
  final double bottomContentPadding;

  @override
  Widget build(BuildContext context) {
    final selectedParagraph = selectedParagraphIndex == null
        ? null
        : payload.paragraphs.cast<ParagraphItem?>().firstWhere(
              (item) => item?.index == selectedParagraphIndex,
              orElse: () => null,
            );
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        children: [
          ContinuousTranslationStrip(
            item: selectedParagraph,
            selectedTapUnitId: selectedTapUnitId,
            translationLeftText: translationLeftText,
            translationFocusText: translationFocusText,
            translationRightText: translationRightText,
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: payload.paragraphs.length + 1,
              separatorBuilder: (_, __) => const SizedBox(height: 18),
              itemBuilder: (context, index) {
                if (index == payload.paragraphs.length) {
                  return SizedBox(height: bottomContentPadding);
                }
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
