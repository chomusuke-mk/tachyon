import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';

class AlbumArtImage extends StatelessWidget {
  final String filePath;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  static final Set<String> _existingCovers = <String>{};

  @visibleForTesting
  static void clearExistenceCache() => _existingCovers.clear();

  @Deprecated('Use filePath instead')
  String get uri => filePath;

  const AlbumArtImage({
    super.key,
    String? filePath,
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
          Icons.album_rounded,
          size: (width != null && height != null)
              ? (width! < height! ? width! * 0.5 : height! * 0.5)
              : (width != null ? width! * 0.5 : 24),
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );

    if (cacheService == null || filePath.isEmpty) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: fallback);
      }
      return fallback;
    }

    final coverFile = cacheService.getCoverFile(filePath);

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final int defaultBound =
        (width != null && width! > 200) || (height != null && height! > 200)
            ? 400
            : 150;
    final int targetCacheWidth = cacheWidth ??
        (width != null ? (width! * dpr).round() : defaultBound);
    final int targetCacheHeight = cacheHeight ??
        (height != null ? (height! * dpr).round() : defaultBound);

    Widget buildImage(File file) {
      return Image.file(
        file,
        width: width,
        height: height,
        cacheWidth: targetCacheWidth > 0 ? targetCacheWidth : null,
        cacheHeight: targetCacheHeight > 0 ? targetCacheHeight : null,
        fit: fit,
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
          if (snapshot.hasData && snapshot.data == true) {
            _existingCovers.add(coverFile.path);
            return buildImage(coverFile);
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
