import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
// ignore: depend_on_referenced_packages
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/metadata/metadata_utils.dart';
import 'package:tachyon/core/playback/domain/audio_playable.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/storage/persistent_binary_storage.dart';
import 'package:tachyon/shared/utils/cors_image_utils.dart';

/// Unified artwork presentation widget that transparently resolves and renders
/// artwork from a single local image file, remote image URL, or an [AudioPlayable].
///
/// Implements on-the-fly RAM decode bounds via [cacheWidth] and [cacheHeight]
/// (or [quality]) to ensure minimal memory consumption without needing multiple
/// quality tiers on disk.
class AlbumArtImage extends StatelessWidget {
  /// Optional playable item whose [AudioPlayable.artworkUri] is used when [artworkUri] is omitted.
  final AudioPlayable? playable;

  /// Local file path, OPFS key, or remote HTTP(S) URL for the artwork image.
  final String? artworkUri;

  /// Optional raw encoded image bytes rendered directly from memory when non-empty.
  final Uint8List? artworkBytes;

  /// Target resolution tier used to derive default memory decode bounds.
  final ThumbnailQuality quality;

  /// Optional layout width of the rendered artwork in logical pixels.
  final double? width;

  /// Optional layout height of the rendered artwork in logical pixels.
  final double? height;

  /// Optional explicit decode width bound in physical pixels.
  final int? cacheWidth;

  /// Optional explicit decode height bound in physical pixels.
  final int? cacheHeight;

  /// How the artwork image is inscribed into its layout box.
  final BoxFit fit;

  /// Optional corner radius applied via a [ClipRRect] around the image.
  final BorderRadius? borderRadius;

  /// Optional placeholder widget shown while loading or when no artwork resolves.
  final Widget? fallback;

  /// Creates an [AlbumArtImage].
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
      final resolvedUrl = CorsImageUtils.resolveWebCorsImageUrl(
        uri,
        width: targetCacheWidth,
        height: targetCacheHeight,
      );
      content = CachedNetworkImage(
        imageUrl: resolvedUrl,
        width: width,
        height: height,
        memCacheWidth: targetCacheWidth,
        memCacheHeight: targetCacheHeight,
        maxWidthDiskCache: kIsWeb
            ? null
            : (targetCacheWidth != null
                  ? math.max(
                      targetCacheWidth,
                      AppDefaults.mediumQualityResolution,
                    )
                  : null),
        imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
        fit: fit,
        filterQuality: FilterQuality.medium,
        placeholder: (context, url) => effectiveFallback,
        errorWidget: (context, url, error) => effectiveFallback,
      );
    } else if (uri != null && uri.isNotEmpty) {
      content = PersistentBinaryStorage.buildLocalOrOpfsImage(
        uri,
        width: width,
        height: height,
        cacheWidth: targetCacheWidth,
        cacheHeight: targetCacheHeight,
        fit: fit,
        fallback: effectiveFallback,
      );
    } else {
      content = effectiveFallback;
    }

    final Widget clipped = borderRadius != null
        ? ClipRRect(borderRadius: borderRadius!, child: content)
        : content;
    return RepaintBoundary(child: clipped);
  }
}
