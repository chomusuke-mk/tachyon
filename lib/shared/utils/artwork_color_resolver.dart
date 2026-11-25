import 'package:cached_network_image/cached_network_image.dart';
// ignore: depend_on_referenced_packages
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/shared/utils/cors_image_utils.dart';

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
          CorsImageUtils.resolveWebCorsImageUrl(
            clean,
            width: 150,
            height: 150,
          ),
          maxWidth: kIsWeb ? null : 150,
          maxHeight: kIsWeb ? null : 150,
          imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
        );
      } else {
        final localProvider =
            await PersistentBinaryStorage.resolveLocalOrOpfsImageProvider(
              clean,
              maxWidth: 150,
              maxHeight: 150,
            );
        if (localProvider == null) return null;
        provider = localProvider;
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
