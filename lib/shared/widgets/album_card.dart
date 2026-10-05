import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/thumbnail_quality.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/playback_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';

/// Card widget displaying an album in grid/card views with an animated
/// hover play button showing the localized "Play album" tooltip.
class AlbumCard extends StatefulWidget {
  final Album album;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;
  final double? width;
  final String? subtitle;

  const AlbumCard({
    super.key,
    required this.album,
    this.onTap,
    this.onPlay,
    this.width,
    this.subtitle,
  });

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final coverFilePath = widget.album.tracks.firstOrNull?.filePath ?? '';

    final VoidCallback? effectiveOnPlay = widget.onPlay ??
        (widget.album.tracks.isNotEmpty
            ? () {
                try {
                  final playback = context.read<PlaybackController>();
                  playback.playAll(widget.album.tracks, startIndex: 0);
                } catch (_) {}
              }
            : null);

    final imageWidget = Stack(
      fit: StackFit.expand,
      children: [
        AlbumArtImage(
          filePath: coverFilePath,
          quality: ThumbnailQuality.medium,
          fit: BoxFit.cover,
        ),
        Positioned(
          right: 8,
          bottom: 8,
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
                    width: 42,
                    height: 42,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 26,
                      icon: Icon(
                        Icons.play_arrow_rounded,
                        color: colorScheme.onPrimary,
                      ),
                      tooltip: strings.alPlayAll,
                      onPressed: effectiveOnPlay,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        widget.width != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(12.0),
                child: SizedBox(
                  width: widget.width,
                  height: widget.width,
                  child: imageWidget,
                ),
              )
            : Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12.0),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: imageWidget,
                  ),
                ),
              ),
        const SizedBox(height: 8),
        Text(
          widget.album.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            widget.subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.outline,
            ),
          ),
        ] else ...[
          const SizedBox(height: 2),
          Text(
            widget.album.artist?.name ?? strings.trUnknownArtist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            strings.alTracksCountFormatted(widget.album.trackCount),
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.outline,
            ),
          ),
        ],
      ],
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(12.0),
        onTap: widget.onTap,
        child: widget.width != null
            ? SizedBox(width: widget.width, child: content)
            : content,
      ),
    );
  }
}

/// List tile widget displaying an album in list views with an animated
/// hover play button showing the localized "Play album" tooltip.
class AlbumListTile extends StatefulWidget {
  final Album album;
  final VoidCallback? onTap;
  final VoidCallback? onPlay;

  const AlbumListTile({
    super.key,
    required this.album,
    this.onTap,
    this.onPlay,
  });

  @override
  State<AlbumListTile> createState() => _AlbumListTileState();
}

class _AlbumListTileState extends State<AlbumListTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;
    final coverFilePath = widget.album.tracks.firstOrNull?.filePath ?? '';

    final VoidCallback? effectiveOnPlay = widget.onPlay ??
        (widget.album.tracks.isNotEmpty
            ? () {
                try {
                  final playback = context.read<PlaybackController>();
                  playback.playAll(widget.album.tracks, startIndex: 0);
                } catch (_) {}
              }
            : null);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: ListTile(
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8.0),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AlbumArtImage(
                  filePath: coverFilePath,
                  quality: ThumbnailQuality.low,
                  fit: BoxFit.cover,
                ),
                if (_isHovered)
                  Container(
                    color: Colors.black38,
                    child: Icon(
                      Icons.play_arrow_rounded,
                      color: colorScheme.primary,
                      size: 26,
                    ),
                  ),
              ],
            ),
          ),
        ),
        title: Text(
          widget.album.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          '${widget.album.artist?.name ?? strings.trUnknownArtist} • ${strings.alTracksCountFormatted(widget.album.trackCount)}',
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
                tooltip: strings.alPlayAll,
                onPressed: effectiveOnPlay,
              )
            : const Icon(Icons.chevron_right_rounded),
        onTap: widget.onTap,
      ),
    );
  }
}
