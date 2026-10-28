import 'dart:async';
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:tachyon/shared/utils/memory_optimizer.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Coordinates app-wide memory, graphics cache eviction, and GC trimming.
///
/// Decoupled from media transport layers so OS media bridges focus purely
/// on system transport controls (SMTC, MPRIS, MediaSession).
class AppMemoryCoordinator {
  static bool _isBackgroundTrimmed = false;

  /// Evicts image caches, resets Skia GPU resource caches, and triggers
  /// native/GC trimming when the app is minimized, or restores them when restored.
  static void applyMinimizedMemoryPolicy(bool minimized) {
    if (minimized) {
      MemoryOptimizer.stopPeriodicTrimmer();
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      AlbumArtImage.clearExistenceCache();
      try {
        SystemChannels.skia.invokeMethod<void>(
          'Skia.setResourceCacheMaxBytes',
          0,
        );
      } catch (_) {}

      if (!_isBackgroundTrimmed) {
        _isBackgroundTrimmed = true;
        MemoryOptimizer.trim(aggressive: true);
        Future<void>.delayed(const Duration(milliseconds: 450), () {
          if (_isBackgroundTrimmed) {
            MemoryOptimizer.trim(aggressive: false);
          }
        });
      }
    } else {
      _isBackgroundTrimmed = false;
      try {
        SystemChannels.skia.invokeMethod<void>(
          'Skia.setResourceCacheMaxBytes',
          4 * 1024 * 1024,
        );
      } catch (_) {}
      MemoryOptimizer.trim(aggressive: false);
      MemoryOptimizer.startPeriodicTrimmer();
    }
  }
}
