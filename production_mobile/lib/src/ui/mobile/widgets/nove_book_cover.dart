import 'dart:typed_data';

import 'package:flutter/material.dart';

class NoveBookCoverCard extends StatelessWidget {
  const NoveBookCoverCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.favorite,
    required this.installed,
    this.coverBytes,
    this.coverUrl,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool favorite;
  final bool installed;
  final Uint8List? coverBytes;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 116,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NoveCoverArt(
              title: title,
              favorite: favorite,
              installed: installed,
              coverBytes: coverBytes,
              coverUrl: coverUrl,
              height: 162,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
            if (subtitle.trim().isNotEmpty)
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class NoveCoverArt extends StatelessWidget {
  const NoveCoverArt({
    super.key,
    required this.title,
    required this.favorite,
    required this.installed,
    this.coverBytes,
    this.coverUrl,
    required this.height,
  });

  final String title;
  final bool favorite;
  final bool installed;
  final Uint8List? coverBytes;
  final String? coverUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final imageBytes = coverBytes;
    final imageUrl = coverUrl?.trim() ?? '';
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: colorScheme.primaryContainer,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageBytes == null
                  ? (imageUrl.isEmpty
                      ? _CoverPlaceholder(title: title)
                      : Image.network(
                          imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) {
                              return child;
                            }
                            return _CoverPlaceholder(title: title);
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return _CoverPlaceholder(title: title);
                          },
                        ))
                  : Image.memory(
                      imageBytes,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return _CoverPlaceholder(title: title);
                      },
                    ),
            ),
          ),
          if (favorite)
            const Positioned(
              right: 8,
              top: 8,
              child: Icon(Icons.star, size: 19),
            ),
          Positioned(
            right: 8,
            bottom: 8,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colorScheme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  installed
                      ? Icons.download_done_outlined
                      : Icons.download_outlined,
                  size: 17,
                  color: colorScheme.onSurface,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nove',
            style: TextStyle(
              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.74),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            title,
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colorScheme.onPrimaryContainer,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
