import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';

export 'package:tachyon/core/services/cover_cache_service.dart'
    show ThumbnailQuality;

class AlbumArtImage extends StatelessWidget {
  final String filePath;
  final String? artistName;
  final ThumbnailQuality quality;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  static final Set<String> _existingCovers = <String>{};
  static final Set<String> _missingCovers = <String>{};

  @visibleForTesting
  static void clearExistenceCache() {
    _existingCovers.clear();
    _missingCovers.clear();
  }

  @Deprecated('Use filePath instead')
  String get uri => filePath;

  const AlbumArtImage({
    super.key,
    String? filePath,
    this.artistName,
    this.quality = ThumbnailQuality.low,
    @Deprecated('Use filePath instead') String? uri,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.fit = BoxFit.cover,
    this.borderRadius,
  }) : filePath = filePath ?? uri ?? '';

  @override
  Widget build(BuildContext context) {
    CoverCacheService? cacheService;
    try {
      cacheService = Provider.of<CoverCacheService>(context, listen: false);
    } catch (_) {
      try {
        cacheService = Provider.of<CoverCacheService?>(context, listen: false);
      } catch (_) {
        cacheService = null;
      }
    }

    final colorScheme = Theme.of(context).colorScheme;

    final fallback = Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          artistName != null && filePath.isEmpty
              ? Icons.person_rounded
              : Icons.album_rounded,
          size: (width != null && height != null)
              ? (width! < height! ? width! * 0.5 : height! * 0.5)
              : (width != null ? width! * 0.5 : 24),
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );

    if (cacheService == null ||
        (filePath.isEmpty && (artistName == null || artistName!.trim().isEmpty))) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: fallback);
      }
      return fallback;
    }

    final coverFile = (artistName != null &&
            artistName!.trim().isNotEmpty &&
            cacheService.hasCachedArtistCover(artistName!, quality: quality))
        ? cacheService.getArtistCoverFile(artistName!, quality: quality)
        : cacheService.getCoverFile(filePath, quality: quality);

    if (_missingCovers.contains(coverFile.path)) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: fallback);
      }
      return fallback;
    }

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final int defaultBound = quality == ThumbnailQuality.high ? 500 : 80;
    final int targetCacheWidth = cacheWidth ??
        (width != null
            ? (quality == ThumbnailQuality.high
                ? (width! * dpr).round().clamp(80, 500)
                : 80)
            : defaultBound);
    final int targetCacheHeight = cacheHeight ??
        (height != null
            ? (quality == ThumbnailQuality.high
                ? (height! * dpr).round().clamp(80, 500)
                : 80)
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
          return fallback;
        },
        errorBuilder: (context, error, stackTrace) => fallback,
      );
    }

    Widget imageWidget;
    if (_existingCovers.contains(coverFile.path)) {
      imageWidget = buildImage(coverFile);
    } else {
      imageWidget = FutureBuilder<bool>(
        future: coverFile.exists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done) {
            if (snapshot.data == true) {
              _existingCovers.add(coverFile.path);
              return buildImage(coverFile);
            } else {
              _missingCovers.add(coverFile.path);
              return fallback;
            }
          }
          return fallback;
        },
      );
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }
    return imageWidget;
  }
}
