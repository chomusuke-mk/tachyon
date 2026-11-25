import 'package:material_ui/material_ui.dart';
import 'package:tachyon/features/locales/domain/locale.dart';

/// Top bar displayed above the Now Playing layout containing navigation dismiss,
/// audio output routing, lyrics, queue, and equalizer controls.
class NowPlayingHeader extends StatelessWidget {
  /// Localized application strings used for button tooltips.
  final AppStringKey strings;

  /// Theme color scheme used for active and inactive icon tints.
  final ColorScheme colorScheme;

  /// Whether the active track supports toggling the synchronized lyrics view.
  final bool canToggleLyrics;

  /// Whether the synchronized lyrics panel is currently visible.
  final bool showLyrics;

  /// Whether the playback queue drawer/split panel is currently visible.
  final bool showQueue;

  /// Dismisses the Now Playing screen.
  final VoidCallback onMinimize;

  /// Opens the audio output device selector dialog.
  final VoidCallback onShowAudioDevices;

  /// Toggles visibility of the lyrics panel.
  final VoidCallback onToggleLyrics;

  /// Toggles visibility of the queue view.
  final VoidCallback onToggleQueue;

  /// Opens the audio effects & DSP controls sheet.
  final VoidCallback onOpenAudioControls;

  /// Vertical drag start gesture handler for pull-to-dismiss interaction.
  final GestureDragStartCallback onVerticalDragStart;

  /// Vertical drag update gesture handler for pull-to-dismiss interaction.
  final GestureDragUpdateCallback onVerticalDragUpdate;

  /// Vertical drag end gesture handler for pull-to-dismiss interaction.
  final GestureDragEndCallback onVerticalDragEnd;

  /// Vertical drag cancel gesture handler for pull-to-dismiss interaction.
  final VoidCallback onVerticalDragCancel;

  /// Creates a [NowPlayingHeader].
  const NowPlayingHeader({
    super.key,
    required this.strings,
    required this.colorScheme,
    required this.canToggleLyrics,
    required this.showLyrics,
    required this.showQueue,
    required this.onMinimize,
    required this.onShowAudioDevices,
    required this.onToggleLyrics,
    required this.onToggleQueue,
    required this.onOpenAudioControls,
    required this.onVerticalDragStart,
    required this.onVerticalDragUpdate,
    required this.onVerticalDragEnd,
    required this.onVerticalDragCancel,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      onVerticalDragCancel: onVerticalDragCancel,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
              tooltip: strings.commonMinimize,
              onPressed: onMinimize,
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.speaker_group_rounded),
              tooltip: strings.npAudioDevices,
              color: colorScheme.onSurface,
              onPressed: onShowAudioDevices,
            ),
            if (canToggleLyrics)
              IconButton(
                icon: Icon(
                  Icons.lyrics_rounded,
                  color: showLyrics
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                tooltip: strings.npLyrics,
                onPressed: onToggleLyrics,
              ),
            IconButton(
              icon: Icon(
                Icons.queue_music_rounded,
                color: showQueue ? colorScheme.primary : colorScheme.onSurface,
              ),
              tooltip: strings.npQueue,
              onPressed: onToggleQueue,
            ),
            IconButton(
              icon: const Icon(Icons.equalizer_rounded),
              tooltip: strings.npAudioControls,
              color: colorScheme.onSurface,
              onPressed: onOpenAudioControls,
            ),
          ],
        ),
      ),
    );
  }
}
