import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Renders a full-bleed blurred thumbnail with a subtle ambient gradient
/// matching the active theme, used as the dynamic backdrop across
/// Now Playing, Album Detail, and Artist Detail screens.
class AmbientBackdrop extends StatelessWidget {
  final String? thumbnailHash;

  const AmbientBackdrop({
    super.key,
    this.thumbnailHash,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool hasImage =
        thumbnailHash != null && thumbnailHash!.trim().isNotEmpty;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasImage)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 32.0, sigmaY: 32.0),
              child: AlbumArtImage(
                thumbnailHash: thumbnailHash,
                fit: BoxFit.cover,
                cacheWidth: 128,
                cacheHeight: 128,
                fallback: const SizedBox.shrink(),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.surface.withValues(alpha: 0.65),
                  colorScheme.surface.withValues(alpha: 0.82),
                  colorScheme.surface.withValues(alpha: 0.95),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
