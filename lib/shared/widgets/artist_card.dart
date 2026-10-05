import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/thumbnail_quality.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Card widget displaying an artist in grid/card views with an animated
/// hover play button showing the localized "Play all tracks" tooltip.
class ArtistCard extends StatefulWidget {
  final Artist artist;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final double radius;
  final double? width;
  final bool showSubtitle;

  const ArtistCard({
    super.key,
    required this.artist,
    this.onTap,
    this.onPlay,
    this.radius = 54.0,
    this.width,
    this.showSubtitle = true,
  });

  @override
  State<ArtistCard> createState() => _ArtistCardState();
}

class _ArtistCardState extends State<ArtistCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverFilePath = widget.artist.tracks.firstOrNull?.filePath ?? '';

    final VoidCallback? effectiveOnPlay = widget.onPlay ??
        (widget.artist.tracks.isNotEmpty
            ? () {
                try {
                  final playback = context.read<PlaybackController>();
                  playback.playAll(widget.artist.tracks, startIndex: 0);
                } catch (_) {}
              }
            : null);

    final avatarSize = widget.radius * 2;

    final card = InkWell(
      borderRadius: BorderRadius.circular(12.0),
      onTap: widget.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
            SizedBox(
              width: avatarSize,
              height: avatarSize,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircleAvatar(
                    radius: widget.radius,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    child: coverFilePath.isNotEmpty
                        ? ClipOval(
                            child: SizedBox(
                              width: avatarSize,
                              height: avatarSize,
                              child: AlbumArtImage(
                                filePath: coverFilePath,
                                artistName: widget.artist.name,
                                quality: ThumbnailQuality.medium,
                                fit: BoxFit.cover,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.person_rounded,
                            size: widget.radius * 0.9,
                            color: colorScheme.onSurfaceVariant,
                          ),
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: IgnorePointer(
                      ignoring: !_isHovered,
                      child: AnimatedOpacity(
                        opacity: _isHovered ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 150),
                        child: AnimatedScale(
                          scale: _isHovered ? 1.0 : 0.7,
                          duration: const Duration(milliseconds: 150),
                          child: Material(
                            color: colorScheme.primary,
                            shape: const CircleBorder(),
                            elevation: 4.0,
                            shadowColor: Colors.black45,
                            child: SizedBox(
                              width: 38,
                              height: 38,
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                iconSize: 24,
                                icon: Icon(
                                  Icons.play_arrow_rounded,
                                  color: colorScheme.onPrimary,
                                ),
                                tooltip: strings.arPlayAll,
                                onPressed: effectiveOnPlay,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.artist.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            if (widget.showSubtitle) ...[
              const SizedBox(height: 2),
              Text(
                '${strings.arAlbumsCountFormatted(widget.artist.albumCount)} • ${strings.arTracksCountFormatted(widget.artist.trackCount)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.outline,
                ),
              ),
            ],
          ],
        ),
      );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.width != null
          ? SizedBox(width: widget.width, child: card)
          : card,
    );
  }
}

/// List tile widget displaying an artist in list views with an animated
/// hover play button showing the localized "Play all tracks" tooltip.
class ArtistListTile extends StatefulWidget {
  final Artist artist;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  const ArtistListTile({
    super.key,
    required this.artist,
    this.onTap,
    this.onPlay,
  });

  @override
  State<ArtistListTile> createState() => _ArtistListTileState();
}

class _ArtistListTileState extends State<ArtistListTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;
    final coverFilePath = widget.artist.tracks.firstOrNull?.filePath ?? '';

    final VoidCallback? effectiveOnPlay = widget.onPlay ??
        (widget.artist.tracks.isNotEmpty
            ? () {
                try {
                  final playback = context.read<PlaybackController>();
                  playback.playAll(widget.artist.tracks, startIndex: 0);
                } catch (_) {}
              }
            : null);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ListTile(
        leading: SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            fit: StackFit.expand,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: colorScheme.surfaceContainerHighest,
                child: coverFilePath.isNotEmpty
                    ? ClipOval(
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: AlbumArtImage(
                            filePath: coverFilePath,
                            artistName: widget.artist.name,
                            quality: ThumbnailQuality.low,
                            fit: BoxFit.cover,
                          ),
                        ),
                      )
                    : Icon(
                        Icons.person_rounded,
                        size: 24,
                        color: colorScheme.onSurfaceVariant,
                      ),
              ),
              if (_isHovered)
                ClipOval(
                  child: Container(
                    color: Colors.black38,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: colorScheme.primary,
                      size: 26,
                    ),
                  ),
                ),
            ],
          ),
        ),
        title: Text(
          widget.artist.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${strings.arAlbumsCountFormatted(widget.artist.albumCount)} • ${strings.arTracksCountFormatted(widget.artist.trackCount)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: _isHovered
            ? IconButton(
                icon: Icon(
                  Icons.play_arrow_rounded,
                  color: colorScheme.primary,
                  size: 26,
                ),
                tooltip: strings.arPlayAll,
                onPressed: effectiveOnPlay,
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: widget.onTap,
      ),
    );
  }
}
