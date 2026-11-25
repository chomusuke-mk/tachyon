import 'dart:typed_data';
import 'dart:ui';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/shared/widgets/app_background.dart';

/// Renders a full-bleed blurred artwork backdrop matching the active theme,
/// used across Now Playing, Radios, Album Detail, and Artist Detail screens.
///
/// Features:
/// - 100% opaque base container to prevent route/background transparency leaks.
/// - [TileMode.clamp] and edge bleeding to eliminate Gaussian blur border feathering.
/// - [BoxFit.cover] scaling to flood the entire viewport without aspect distortion.
///
/// Fallback resolution hierarchy:
/// 1. Artwork image or URL via [artworkUri].
/// 2. User configured wallpaper image via [SettingsController.customBackgroundPath].
/// 3. App accent theme radial gradient fallback.
class AmbientBackdrop extends StatelessWidget {
  final String? artworkUri;
  final Uint8List? artworkBytes;

  const AmbientBackdrop({
    super.key,
    this.artworkUri,
    this.artworkBytes,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bool hasBytes = artworkBytes != null && artworkBytes!.isNotEmpty;
    final bool hasUri = artworkUri != null && artworkUri!.trim().isNotEmpty;
    final bool hasArtwork = hasBytes || hasUri;

    final settings = Provider.of<SettingsController?>(context, listen: false);

    Widget buildFallbackBackground() {
      final customBg = settings?.customBackgroundPath;
      final bool hasCustomBg = AppBackground.fileExists(customBg);
      if (hasCustomBg) {
        return AppBackground(
          imagePath: customBg,
          blurSigma: settings?.backgroundBlurSigma ?? 20.0,
          dimOpacity: settings?.backgroundDimOpacity ?? 0.65,
        );
      }
      // General App Accent / Theme Color Fallback
      return Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          gradient: RadialGradient(
            center: const Alignment(0, -0.35),
            radius: 1.15,
            colors: [
              colorScheme.primary.withValues(alpha: 0.28),
              colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              colorScheme.surface,
            ],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
      );
    }

    final Widget backgroundContent;
    if (hasArtwork) {
      backgroundContent = ImageFiltered(
        imageFilter: ImageFilter.blur(
          sigmaX: 36.0,
          sigmaY: 36.0,
          tileMode: TileMode.clamp,
        ),
        child: Transform.scale(
          scale: 1.15,
          child: AlbumArtImage(
            artworkUri: artworkUri,
            artworkBytes: artworkBytes,
            fit: BoxFit.cover,
            width: double.infinity,
            height: double.infinity,
            cacheWidth: 384,
            fallback: const SizedBox.shrink(),
          ),
        ),
      );
    } else if (settings != null) {
      backgroundContent = ListenableBuilder(
        listenable: settings.themeListenable,
        builder: (context, _) => buildFallbackBackground(),
      );
    } else {
      backgroundContent = buildFallbackBackground();
    }

    return RepaintBoundary(
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // Solid surface container to guarantee zero background route bleed-through
            Container(color: colorScheme.surface),
            backgroundContent,
            if (hasArtwork)
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colorScheme.surface.withValues(alpha: 0.65),
                      colorScheme.surface.withValues(alpha: 0.82),
                      colorScheme.surface.withValues(alpha: 0.95),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
