import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

/// Renders a persistent background wallpaper image with Gaussian blur
/// and an adaptive surface tint overlay to ensure text legibility and contrast.
class AppBackground extends StatefulWidget {
  final String? imagePath;
  final double blurSigma;
  final double dimOpacity;

  /// Checks whether [path] is non-empty and exists on disk.
  static bool fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    return File(path).existsSync();
  }

  const AppBackground({
    super.key,
    required this.imagePath,
    this.blurSigma = 20.0,
    this.dimOpacity = 0.65,
  });

  @override
  State<AppBackground> createState() => _AppBackgroundState();
}

class _AppBackgroundState extends State<AppBackground> {
  bool _exists = false;

  @override
  void initState() {
    super.initState();
    _checkExists();
  }

  @override
  void didUpdateWidget(covariant AppBackground oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imagePath != widget.imagePath) {
      _checkExists();
    }
  }

  void _checkExists() {
    final path = widget.imagePath;
    if (path == null || path.isEmpty) {
      _exists = false;
    } else {
      _exists = File(path).existsSync();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_exists || widget.imagePath == null) {
      return const SizedBox.shrink();
    }

    final file = File(widget.imagePath!);
    final colorScheme = Theme.of(context).colorScheme;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (widget.blurSigma > 0.0)
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: widget.blurSigma,
                sigmaY: widget.blurSigma,
                tileMode: TileMode.clamp,
              ),
              child: Transform.scale(
                scale: 1.05,
                child: Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: 640,
                  cacheHeight: 360,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            )
          else
            Image.file(
              file,
              fit: BoxFit.cover,
              cacheWidth: 1280,
              cacheHeight: 720,
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
          Container(
            color: colorScheme.surface.withValues(alpha: widget.dimOpacity),
          ),
        ],
      ),
    );
  }
}
