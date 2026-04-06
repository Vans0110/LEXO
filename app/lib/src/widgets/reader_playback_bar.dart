import 'package:flutter/material.dart';
import 'dart:ui';

class ReaderPlaybackBar extends StatelessWidget {
  const ReaderPlaybackBar({
    super.key,
    required this.expanded,
    required this.hasPlayableJob,
    required this.isPlaying,
    required this.isPaused,
    required this.busy,
    required this.onToggleExpand,
    required this.onPlayPause,
    required this.onStop,
    required this.onPrev,
    required this.onNext,
  });

  final bool expanded;
  final bool hasPlayableJob;
  final bool isPlaying;
  final bool isPaused;
  final bool busy;
  final VoidCallback onToggleExpand;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controlsEnabled = hasPlayableJob && !busy;
    final playIcon = isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded;
    final arrowIcon = expanded ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded;
    final buttonBackground = Colors.black.withValues(alpha: controlsEnabled ? 0.42 : 0.18);
    final iconColor = Colors.white.withValues(alpha: controlsEnabled ? 0.95 : 0.45);

    return SafeArea(
      top: false,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 3.5, sigmaY: 3.5),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                padding: expanded
                    ? const EdgeInsets.fromLTRB(12, 8, 12, 12)
                    : const EdgeInsets.fromLTRB(12, 4, 12, 4),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: 24,
                      offset: const Offset(0, 8),
                      color: Colors.black.withValues(alpha: 0.10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: onToggleExpand,
                      borderRadius: BorderRadius.circular(999),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                        child: Icon(
                          arrowIcon,
                          size: 18,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.42),
                        ),
                      ),
                    ),
                    if (expanded) ...[
                      const SizedBox(height: 2),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _RoundControlButton(
                            onPressed: controlsEnabled ? onStop : null,
                            icon: Icons.stop_rounded,
                            tooltip: 'Stop',
                            backgroundColor: buttonBackground,
                            iconColor: iconColor,
                          ),
                          const SizedBox(width: 8),
                          _RoundControlButton(
                            onPressed: controlsEnabled ? onPrev : null,
                            icon: Icons.skip_previous_rounded,
                            tooltip: 'Prev segment',
                            backgroundColor: buttonBackground,
                            iconColor: iconColor,
                          ),
                          const SizedBox(width: 10),
                          _RoundControlButton(
                            onPressed: controlsEnabled ? onPlayPause : null,
                            icon: playIcon,
                            tooltip: 'Play pause',
                            size: 56,
                            iconSize: 30,
                            backgroundColor: buttonBackground,
                            iconColor: iconColor,
                          ),
                          const SizedBox(width: 10),
                          _RoundControlButton(
                            onPressed: controlsEnabled ? onNext : null,
                            icon: Icons.skip_next_rounded,
                            tooltip: 'Next segment',
                            backgroundColor: buttonBackground,
                            iconColor: iconColor,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundControlButton extends StatelessWidget {
  const _RoundControlButton({
    required this.onPressed,
    required this.icon,
    required this.tooltip,
    required this.backgroundColor,
    required this.iconColor,
    this.size = 46,
    this.iconSize = 24,
  });

  final VoidCallback? onPressed;
  final IconData icon;
  final String tooltip;
  final Color backgroundColor;
  final Color iconColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: iconColor),
          ),
        ),
      ),
    );
  }
}
