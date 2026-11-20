import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/audio_playable.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';

/// Unified artwork presentation widget that transparently resolves and renders
/// artwork from a single local image file, remote image URL, or an [AudioPlayable].
///
/// Implements on-the-fly RAM decode bounds via [cacheWidth] and [cacheHeight]
/// (or [quality]) to ensure minimal memory consumption without needing multiple
/// quality tiers on disk.
class AlbumArtImage extends StatelessWidget {
  final AudioPlayable? playable;
  final String? artworkUri;
  final Uint8List? artworkBytes;
  final ThumbnailQuality quality;
  final double? width;
  final double? height;
  final int? cacheWidth;
  final int? cacheHeight;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final Widget? fallback;

  static void clearExistenceCache() {}

  const AlbumArtImage({
    super.key,
    this.playable,
    this.artworkUri,
    this.artworkBytes,
    this.quality = ThumbnailQuality.low,
    this.width,
    this.height,
    this.cacheWidth,
    this.cacheHeight,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.fallback,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final uri = (artworkUri?.trim().isNotEmpty == true)
        ? artworkUri!.trim()
        : playable?.artworkUri?.trim();

    final isRemote = uri != null &&
        (uri.startsWith('http://') || uri.startsWith('https://'));
    final isStreamItem = (playable is RadioStation) ||
        (playable?.isStream ?? false) ||
        isRemote;

    final double iconSize = (width != null && height != null)
        ? (width! < height! ? width! * 0.5 : height! * 0.5)
        : (width != null
            ? width! * 0.5
            : (quality == ThumbnailQuality.high ? 64.0 : 24.0));

    final defaultFallback = Container(
      width: width,
      height: height,
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          isStreamItem ? Icons.radio_rounded : Icons.album_rounded,
          size: iconSize,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        ),
      ),
    );
    final effectiveFallback = fallback ?? defaultFallback;

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final int defaultBound = switch (quality) {
      ThumbnailQuality.high => AppDefaults.highQualityResolution,
      ThumbnailQuality.medium => AppDefaults.mediumQualityResolution,
      ThumbnailQuality.low => AppDefaults.lowQualityResolution,
    };

    // Calculate RAM decode bounds strictly along a single dimension.
    // Specifying both cacheWidth and cacheHeight triggers ResizeImagePolicy.exact
    // in Flutter's engine, which forcibly stretches any non-square image into an
    // exact square raster prior to BoxFit.cover, permanently deforming it.
    final int? targetCacheWidth;
    final int? targetCacheHeight;

    if (cacheWidth != null && cacheHeight == null) {
      targetCacheWidth = cacheWidth;
      targetCacheHeight = null;
    } else if (cacheHeight != null && cacheWidth == null) {
      targetCacheWidth = null;
      targetCacheHeight = cacheHeight;
    } else if (cacheWidth != null && cacheHeight != null) {
      targetCacheWidth = math.max(cacheWidth!, cacheHeight!);
      targetCacheHeight = null;
    } else {
      final double? targetExtent = (width != null && height != null)
          ? math.max(width!, height!)
          : (width ?? height);

      final int extentBound = targetExtent != null
          ? (targetExtent * math.max(dpr, 1.5)).round()
          : defaultBound;

      final int computed = math.max(extentBound, defaultBound).clamp(
            AppDefaults.lowQualityResolution,
            AppDefaults.highQualityResolution,
          );

      targetCacheWidth = computed;
      targetCacheHeight = null;
    }

    Widget buildImage(File file) {
      return Image.file(
        file,
        width: width,
        height: height,
        cacheWidth: targetCacheWidth,
        cacheHeight: targetCacheHeight,
        fit: fit,
        filterQuality: FilterQuality.medium,
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

    final Widget content;

    if (artworkBytes != null && artworkBytes!.isNotEmpty) {
      content = Image.memory(
        artworkBytes!,
        width: width,
        height: height,
        cacheWidth: targetCacheWidth,
        cacheHeight: targetCacheHeight,
        fit: fit,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded || frame != null) {
            return child;
          }
          return effectiveFallback;
        },
        errorBuilder: (context, error, stackTrace) => effectiveFallback,
      );
    } else if (isRemote) {
      content = CachedNetworkImage(
        imageUrl: uri,
        width: width,
        height: height,
        memCacheWidth: targetCacheWidth,
        memCacheHeight: targetCacheHeight,
        maxWidthDiskCache: targetCacheWidth != null
            ? math.max(targetCacheWidth, AppDefaults.mediumQualityResolution)
            : null,
        fit: fit,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) => effectiveFallback,
        errorWidget: (context, url, error) => effectiveFallback,
      );
    } else if (uri != null && uri.isNotEmpty) {
      final cleanPath = uri.startsWith('file://')
          ? uri.replaceFirst('file://', '')
          : uri;
      File file = File(cleanPath);
      if (!file.existsSync() && MetadataUtils.thumbnailsDirectory != null) {
        file = File(p.join(MetadataUtils.thumbnailsDirectory!.path, p.basename(cleanPath)));
      }
      content = file.existsSync() ? buildImage(file) : effectiveFallback;
    } else {
      content = effectiveFallback;
    }

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: content);
    }
    return content;
  }
}
