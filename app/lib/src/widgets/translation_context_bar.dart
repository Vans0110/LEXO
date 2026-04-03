import 'package:flutter/material.dart';

class TranslationContextBar extends StatelessWidget {
  const TranslationContextBar({
    super.key,
    required this.leftText,
    required this.focusText,
    required this.rightText,
  });

  final String? leftText;
  final String? focusText;
  final String? rightText;

  @override
  Widget build(BuildContext context) {
    final hasSelection =
        focusText != null &&
        focusText!.trim().isNotEmpty &&
        (leftText != null || rightText != null);

    return SizedBox(
      height: 72,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.45),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: hasSelection
              ? Center(
                  child: RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 16,
                        height: 1.3,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      children: [
                        if (leftText != null && leftText!.trim().isNotEmpty)
                          TextSpan(text: '${leftText!.trim()} '),
                        TextSpan(
                          text: focusText!.trim(),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (rightText != null && rightText!.trim().isNotEmpty)
                          TextSpan(text: ' ${rightText!.trim()}'),
                      ],
                    ),
                  ),
                )
              : const Center(
                  child: Text(
                    'Tap a word to see translation',
                    style: TextStyle(fontSize: 15),
                  ),
                ),
        ),
      ),
    );
  }
}
