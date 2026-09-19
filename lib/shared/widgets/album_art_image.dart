import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/services/cover_cache_service.dart';

class AlbumArtImage extends StatelessWidget {
  final String uri;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const AlbumArtImage({
    super.key,
    required this.uri,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    CoverCacheService? cacheService;
    try {
      cacheService = Provider.of<CoverCacheService?>(context, listen: false);
    } catch (_) {
      cacheService = null;
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

    if (cacheService == null || uri.isEmpty) {
      if (borderRadius != null) {
        return ClipRRect(borderRadius: borderRadius!, child: fallback);
      }
      return fallback;
    }

    final coverFile = cacheService.getCoverFile(uri);

    Widget imageWidget = FutureBuilder<bool>(
      future: coverFile.exists(),
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data == true) {
          return Image.file(
            coverFile,
            width: width,
            height: height,
            fit: fit,
            errorBuilder: (context, error, stackTrace) => fallback,
          );
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
