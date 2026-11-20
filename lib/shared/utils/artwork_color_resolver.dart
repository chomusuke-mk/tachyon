import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/metadata/metadata_utils.dart';

/// Service responsible for extracting and caching a harmonized background color
/// from an audio track or album's artwork image.
abstract final class ArtworkColorResolver {
  static final Map<String, Color> _cache = <String, Color>{};

  /// Read-only snapshot of cached extracted colors.
  static Map<String, Color> get cache => _cache;

  @visibleForTesting
  static void clearCache() => _cache.clear();

  /// Returns the application's default container color for surfaces like the miniplayer
  /// when artwork is null, missing, or unresolvable.
  static Color getApplicationColor({
    required ThemeData theme,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    return isOled
        ? theme.colorScheme.surface
        : theme.colorScheme.surfaceContainerHigh;
  }

  /// Returns the harmonized color for [artworkUri]. If [artworkUri] is null, empty,
  /// or not yet resolved in cache, gracefully falls back to the application's surface color.
  static Color getColor({
    String? artworkUri,
    required ThemeData theme,
  }) {
    if (artworkUri == null || artworkUri.trim().isEmpty) {
      return getApplicationColor(theme: theme);
    }
    final clean = artworkUri.trim();
    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final cacheKey =
        '$clean:${theme.brightness.name}:${isOled ? 'oled' : 'std'}';
    return _cache[cacheKey] ?? getApplicationColor(theme: theme);
  }

  /// Synchronously returns cached color for [artworkUri] and [theme] if available.
  /// If [artworkUri] is null or empty, returns the application surface color.
  static Color? getCachedColor({
    String? artworkUri,
    required ThemeData theme,
  }) {
    if (artworkUri == null || artworkUri.trim().isEmpty) {
      return getApplicationColor(theme: theme);
    }
    final clean = artworkUri.trim();
    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final cacheKey =
        '$clean:${theme.brightness.name}:${isOled ? 'oled' : 'std'}';
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

  /// Asynchronously loads the artwork image and extracts a Material ColorScheme seeded from it.
  /// If [artworkUri] is null or empty, returns the application surface color.
  static Future<Color?> resolveColor({
    String? artworkUri,
    required ThemeData theme,
  }) async {
    if (artworkUri == null || artworkUri.trim().isEmpty) {
      return getApplicationColor(theme: theme);
    }
    final clean = artworkUri.trim();

    final isDark = theme.brightness == Brightness.dark;
    final isOled =
        isDark && theme.colorScheme.surface == const Color(0xFF000000);
    final cacheKey =
        '$clean:${theme.brightness.name}:${isOled ? 'oled' : 'std'}';

    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey];
    }

    try {
      final ImageProvider provider;
      if (clean.startsWith('http://') || clean.startsWith('https://')) {
        provider = CachedNetworkImageProvider(
          clean,
          maxWidth: 150,
          maxHeight: 150,
        );
      } else {
        File file = File(clean.startsWith('file://') ? clean.replaceFirst('file://', '') : clean);
        if (!await file.exists() && MetadataUtils.thumbnailsDirectory != null) {
          file = File(p.join(MetadataUtils.thumbnailsDirectory!.path, p.basename(clean)));
        }
        if (!await file.exists() || await file.length() <= 0) return null;
        provider = ResizeImage.resizeIfNeeded(150, null, FileImage(file));
      }

      final scheme = await ColorScheme.fromImageProvider(
        provider: provider,
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
