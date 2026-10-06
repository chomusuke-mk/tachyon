import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/shared/utils/cover_utils.dart';

export 'package:tachyon/features/library/domain/thumbnail_quality.dart';

class AlbumArtImage extends StatelessWidget {
  final String? thumbnailHash;
  final ThumbnailQuality quality;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;

  static final Map<String, String> _resolvedPaths = <String, String>{};

  @visibleForTesting
  static void clearExistenceCache() {
    _resolvedPaths.clear();
  }

  const AlbumArtImage({
    super.key,
    this.thumbnailHash,
    this.quality = ThumbnailQuality.low,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
  });

  /// UI utility: validates that the thumbnail file exists on disk and has length > 0.
  /// Returns the path if valid, or null otherwise.
  static Future<String?> getThumbnail(
    String? coverHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) async {
    if (coverHash == null || coverHash.trim().isEmpty) return null;
    final cleanHash = coverHash.trim();
    final lookupKey = '${quality.name}:$cleanHash';

    final cached = _resolvedPaths[lookupKey];
    if (cached != null) {
      final f = File(cached);
      if (f.existsSync() && f.lengthSync() > 0) {
        return cached;
      }
      _resolvedPaths.remove(lookupKey);
    }

    try {
      final f = CoverUtils.getCoverFile(cleanHash, quality: quality);
      if (await f.exists() && await f.length() > 0) {
        _resolvedPaths[lookupKey] = f.path;
        return f.path;
      }
    } catch (_) {}

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final defaultFallback = Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.album_rounded,
          size: (width != null && height != null)
              ? (width! < height! ? width! * 0.5 : height! * 0.5)
              : (width != null ? width! * 0.5 : 24),
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    final effectiveFallback = fallback ?? defaultFallback;

    // If thumbnailHash is null or empty, synchronously return fallback!
    final hash = thumbnailHash?.trim();
    if (hash == null || hash.isEmpty) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: effectiveFallback);
      }
      return effectiveFallback;
    }

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final int defaultBound = switch (quality) {
      ThumbnailQuality.high => AppDefaults.highQualityResolution,
      ThumbnailQuality.medium => AppDefaults.mediumQualityResolution,
      ThumbnailQuality.low => AppDefaults.lowQualityResolution,
    };
    final int targetCacheWidth =
        cacheWidth ??
        (width != null
            ? (width! * dpr).round().clamp(
                AppDefaults.lowQualityResolution,
                AppDefaults.highQualityResolution,
              )
            : defaultBound);
    final int targetCacheHeight =
        cacheHeight ??
        (height != null
            ? (height! * dpr).round().clamp(
                AppDefaults.lowQualityResolution,
                AppDefaults.highQualityResolution,
              )
            : defaultBound);

    Widget buildImage(File file) {
      return Image.file(
        file,
        width: width,
        height: height,
        cacheWidth: targetCacheWidth > 0 ? targetCacheWidth : null,
        cacheHeight: targetCacheHeight > 0 ? targetCacheHeight : null,
        fit: fit,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return effectiveFallback;
        },
        errorBuilder: (context, error, stackTrace) => effectiveFallback,
      );
    }

    final lookupKey = '${quality.name}:$hash';
    if (_resolvedPaths.containsKey(lookupKey)) {
      final cachedPath = _resolvedPaths[lookupKey]!;
      final image = buildImage(File(cachedPath));
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: image);
      }
      return image;
    }

    final Widget imageWidget = FutureBuilder<String?>(
      future: getThumbnail(hash, quality: quality),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done &&
            snapshot.data != null) {
          return buildImage(File(snapshot.data!));
        }
        return effectiveFallback;
      },
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }
    return imageWidget;
  }
}
