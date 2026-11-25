import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';

/// Renders a persistent background wallpaper image with Gaussian blur
/// and an adaptive surface tint overlay to ensure text legibility and contrast.
class AppBackground extends StatefulWidget {
  /// File system or OPFS path to the user-configured background image.
  final String? imagePath;

  /// Gaussian blur standard deviation applied to the background image.
  final double blurSigma;

  /// Opacity of the surface color overlay rendered above the background image.
  final double dimOpacity;

  /// Checks whether [path] is non-empty and exists on disk or OPFS.
  static bool fileExists(String? path) {
    if (path == null || path.isEmpty) return false;
    return PersistentBinaryStorage.fileExistsSync(path);
  }

  /// Creates an [AppBackground].
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
      _exists = PersistentBinaryStorage.fileExistsSync(path);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_exists || widget.imagePath == null) {
      return const SizedBox.shrink();
    }

    final path = widget.imagePath!;
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
                child: PersistentBinaryStorage.buildLocalOrOpfsImage(
                  path,
                  fit: BoxFit.cover,
                  cacheWidth: 640,
                  fallback: const SizedBox.shrink(),
                ),
              ),
            )
          else
            PersistentBinaryStorage.buildLocalOrOpfsImage(
              path,
              fit: BoxFit.cover,
              cacheWidth: 1280,
              fallback: const SizedBox.shrink(),
            ),
          Container(
            color: colorScheme.surface.withValues(alpha: widget.dimOpacity),
          ),
        ],
      ),
    );
  }
}
