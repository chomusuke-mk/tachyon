import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/shared/utils/metadata_utils.dart';

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

  /// UI utility: returns the resolved thumbnail file path for [coverHash] if non-empty.
  static Future<String?> getThumbnail(
    String? coverHash, {
    ThumbnailQuality quality = ThumbnailQuality.low,
  }) async {
    if (coverHash == null ||
        coverHash.trim().isEmpty ||
        MetadataUtils.thumbnailsDirectory == null) {
      return null;
    }
    final cleanHash = coverHash.trim();
    return MetadataUtils.getThumbnailFilePath(cleanHash, quality: quality);
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

    // If thumbnailHash is null, empty or MetadataUtils is not initialized, synchronously return fallback!
    final hash = thumbnailHash?.trim();
    if (hash == null ||
        hash.isEmpty ||
        MetadataUtils.thumbnailsDirectory == null) {
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

    final filePath = MetadataUtils.getThumbnailFilePath(hash, quality: quality);
    final image = buildImage(File(filePath));
    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }
}
