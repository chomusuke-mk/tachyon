import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Service responsible for extracting and caching a harmonized background color
/// from an audio track or album's low-quality thumbnail image.
abstract final class ArtworkColorResolver {
  static final Map<String, Color> _cache = <String, Color>{};

  /// Read-only snapshot of cached extracted colors.
  static Map<String, Color> get cache => _cache;

  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// Synchronously returns cached color for [thumbnailHash] and [theme] if available.
  static Color? getCachedColor({
    required String thumbnailHash,
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final cacheKey =
        '$thumbnailHash:${theme.brightness.name}:${isOled ? 'oled' : 'std'}';
    return _cache[cacheKey];
  }

  /// Computes a surface color harmonized with the extracted artwork color scheme,
  /// preserving readability and contrasting with [ThemeData.colorScheme].
  static Color computeColor({
    required ColorScheme extractedScheme,
    required ColorScheme themeScheme,
    required bool isDark,
    required bool isOled,
  }) {
    if (isOled) {
      return Color.alphaBlend(
        extractedScheme.primaryContainer.withValues(alpha: 0.28),
        themeScheme.surfaceContainerHigh,
      );
    } else if (isDark) {
      return Color.alphaBlend(
        extractedScheme.primaryContainer.withValues(alpha: 0.45),
        extractedScheme.surfaceContainerHigh,
      );
    } else {
      return Color.alphaBlend(
        extractedScheme.primaryContainer.withValues(alpha: 0.35),
        extractedScheme.surfaceContainerHigh,
      );
    }
  }

  /// Asynchronously loads the low-quality thumbnail and extracts
  /// a Material ColorScheme seeded from the artwork.
  static Future<Color?> resolveColor({
    required String thumbnailHash,
    required ThemeData theme,
  }) async {
    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final cacheKey =
        '$thumbnailHash:${theme.brightness.name}:${isOled ? 'oled' : 'std'}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final filePath = await AlbumArtImage.getThumbnail(
        thumbnailHash,
        quality: ThumbnailQuality.low,
      );
      if (filePath == null) return null;

      final file = File(filePath);
      if (!await file.exists() || await file.length() <= 0) return null;

      final scheme = await ColorScheme.fromImageProvider(
        provider: FileImage(file),
        brightness: theme.brightness,
      );

      final color = computeColor(
        extractedScheme: scheme,
        themeScheme: theme.colorScheme,
        isDark: isDark,
        isOled: isOled,
      );

      _cache[cacheKey] = color;
      return color;
    } catch (_) {
      return null;
    }
  }
}
