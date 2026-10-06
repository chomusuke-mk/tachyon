import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Renders a persistent background wallpaper image with Gaussian blur
/// and an adaptive surface tint overlay to ensure text legibility and contrast.
class AppBackground extends StatelessWidget {
  final String? imagePath;
  final double blurSigma;
  final double dimOpacity;

  const AppBackground({
    super.key,
    required this.imagePath,
    this.blurSigma = 20.0,
    this.dimOpacity = 0.65,
  });

  @override
  Widget build(BuildContext context) {
    if (imagePath == null) return const SizedBox.shrink();

    final file = File(imagePath!);
    if (!file.existsSync()) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (blurSigma > 0.0)
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: blurSigma,
                sigmaY: blurSigma,
                tileMode: TileMode.clamp,
              ),
              child: Transform.scale(
                scale: 1.05,
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            )
          else
            Image.file(
              file,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          Container(
            color: colorScheme.surface.withValues(alpha: dimOpacity),
          ),
        ],
      ),
    );
  }
}
