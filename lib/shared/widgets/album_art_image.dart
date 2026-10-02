import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/features/library/domain/thumbnail_quality.dart';

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
  static final Map<String, String> _resolvedPaths = <String, String>{};

  @visibleForTesting
  static void clearExistenceCache() {
    _existingCovers.clear();
    _missingCovers.clear();
    _resolvedPaths.clear();
  }

  const AlbumArtImage({
    super.key,
    required this.filePath,
    this.artistName,
    this.quality = ThumbnailQuality.low,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    TachyonBackendClient? backendClient;
    try {
      backendClient = Provider.of<TachyonBackendClient>(context, listen: false);
    } catch (_) {
      try {
        backendClient = Provider.of<TachyonBackendClient?>(
          context,
          listen: false,
        );
      } catch (_) {
        backendClient = null;
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

    if (filePath.isEmpty &&
        (artistName == null || artistName!.trim().isEmpty)) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: fallback);
      }
      return fallback;
    }

    final String lookupKey = '${quality.name}:$filePath:${artistName ?? ''}';

    if (_missingCovers.contains(lookupKey)) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: fallback);
      }
      return fallback;
    }

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final int defaultBound = quality == ThumbnailQuality.high ? 500 : 80;
    final int targetCacheWidth =
        cacheWidth ??
        (width != null
            ? (quality == ThumbnailQuality.high
                  ? (width! * dpr).round().clamp(80, 500)
                  : 80)
            : defaultBound);
    final int targetCacheHeight =
        cacheHeight ??
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

    if (_resolvedPaths.containsKey(lookupKey)) {
      final cachedPath = _resolvedPaths[lookupKey]!;
      final image = buildImage(File(cachedPath));
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: image);
      }
      return image;
    }

    Future<File?> resolveCoverFile() async {
      if (backendClient != null) {
        try {
          String? path;
          if (artistName != null &&
              artistName!.trim().isNotEmpty &&
              filePath.isEmpty) {
            path = await backendClient.getArtistCover(
              artistName!,
              isHighQuality: quality == ThumbnailQuality.high,
            );
          } else if (filePath.isNotEmpty) {
            path = await backendClient.getThumbnail(
              filePath,
              isHighQuality: quality == ThumbnailQuality.high,
            );
          }
          if (path != null) {
            final f = File(path);
            if (await f.exists() && await f.length() > 0) {
              _resolvedPaths[lookupKey] = path;
              _existingCovers.add(f.path);
              return f;
            }
          }
        } catch (_) {}
      }
      _missingCovers.add(lookupKey);
      return null;
    }

    final Widget imageWidget = FutureBuilder<File?>(
      future: resolveCoverFile(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.done) {
          final file = snapshot.data;
          if (file != null) {
            return buildImage(file);
          } else {
            return fallback;
          }
        }
        return fallback;
      },
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: imageWidget);
    }
    return imageWidget;
  }
}
