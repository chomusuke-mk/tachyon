import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
// ignore: depend_on_referenced_packages
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart'
    show ImageRenderMethodForWeb;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/shared/utils/cors_image_utils.dart';

/// Reusable widget that renders a station's remote favicon/logo with animated
/// playback overlay and graceful fallback to theme-colored vector icons.
class RadioLogoAvatar extends StatelessWidget {
  final String? faviconUrl;
  final double size;
  final bool isCurrent;
  final bool isPlaying;
  final BorderRadius? borderRadius;

  const RadioLogoAvatar({
    super.key,
    required this.faviconUrl,
    this.size = 44.0,
    this.isCurrent = false,
    this.isPlaying = false,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(8.0);

    Widget fallbackIcon() {
      return Center(
        child: Icon(
          isPlaying ? Icons.graphic_eq_rounded : Icons.radio_rounded,
          color: isCurrent ? colorScheme.primary : colorScheme.onSurfaceVariant,
          size: size * 0.54,
        ),
      );
    }

    final hasFavicon = faviconUrl != null &&
        faviconUrl!.trim().isNotEmpty &&
        Uri.tryParse(faviconUrl!)?.hasScheme == true;

    final dpr = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1.0;
    final int cacheDimension = math.max(
      (size * math.max(dpr, 1.5)).round(),
      AppDefaults.lowQualityResolution,
    );

    final Widget content;
    if (hasFavicon) {
      final resolvedImageUrl = CorsImageUtils.resolveWebCorsImageUrl(
        faviconUrl!,
        width: cacheDimension,
        height: cacheDimension,
      );
      content = Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: resolvedImageUrl,
            width: size,
            height: size,
            memCacheWidth: cacheDimension,
            maxWidthDiskCache: kIsWeb ? null : cacheDimension * 2,
            imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
            filterQuality: FilterQuality.medium,
            fit: BoxFit.cover,
            placeholder: (context, url) => fallbackIcon(),
            errorWidget: (context, url, error) => fallbackIcon(),
          ),
          if (isPlaying)
            Container(
              color: Colors.black.withValues(alpha: 0.45),
              child: Center(
                child: Icon(
                  Icons.graphic_eq_rounded,
                  color: Colors.white,
                  size: size * 0.54,
                ),
              ),
            ),
        ],
      );
    } else {
      content = fallbackIcon();
    }

    return RepaintBoundary(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: isCurrent
              ? colorScheme.primaryContainer
              : colorScheme.surfaceContainerHighest,
          borderRadius: effectiveRadius,
        ),
        child: ClipRRect(
          borderRadius: effectiveRadius,
          child: content,
        ),
      ),
    );
  }
}
