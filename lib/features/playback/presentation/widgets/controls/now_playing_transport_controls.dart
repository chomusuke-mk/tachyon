import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/domain/locale.dart';

/// Primary playback transport bar displaying shuffle, previous, play/pause,
/// next, and repeat mode controls scoped cleanly to [PlaybackController].
class NowPlayingTransportControls extends StatelessWidget {
  /// Playback controller driving transport state and commands.
  final PlaybackController playback;

  /// Localized strings for control tooltips.
  final AppStringKey strings;

  /// Theme color scheme styling active toggles and the main play button.
  final ColorScheme colorScheme;

  /// Smart previous-track handler (restarts track after initial threshold).
  final VoidCallback onPrevious;

  /// Creates a [NowPlayingTransportControls].
  const NowPlayingTransportControls({
    super.key,
    required this.playback,
    required this.strings,
    required this.colorScheme,
    required this.onPrevious,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        ListenableBuilder(
          listenable: playback.controlsListenable,
          builder: (context, _) {
            final shuffled = playback.isShuffled;
            return IconButton(
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.shuffle_rounded, size: 24),
                  if (shuffled)
                    Positioned(
                      left: 3,
                      child: Container(
                        width: 3,
                        height: 3,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              color: shuffled
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              tooltip: shuffled ? strings.npShuffleOn : strings.npShuffleOff,
              onPressed: playback.toggleShuffle,
            );
          },
        ),
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 36),
          tooltip: strings.npPrevious,
          onPressed: onPrevious,
        ),
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 70, maxHeight: 70),
            child: AspectRatio(
              aspectRatio: 1.0,
              child: ListenableBuilder(
                listenable: playback.transportListenable,
                builder: (context, _) {
                  final playing = playback.isPlaying;
                  return IconButton.filled(
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                    style: IconButton.styleFrom(
                      minimumSize: const Size(500, 500),
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                    ),
                    icon: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 150),
                        transitionBuilder: (
                          Widget child,
                          Animation<double> animation,
                        ) {
                          return ScaleTransition(
                            scale: animation,
                            child: RotationTransition(
                              turns: Tween<double>(
                                begin: 0.9,
                                end: 1.0,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Icon(
                          playing
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          key: ValueKey<bool>(playing),
                          size: 40,
                        ),
                      ),
                    ),
                    tooltip: playing ? strings.npPause : strings.npPlay,
                    onPressed: playback.playOrPause,
                  );
                },
              ),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: playback.transportListenable,
          builder: (context, _) {
            return IconButton(
              icon: const Icon(Icons.skip_next_rounded, size: 36),
              tooltip: strings.npNext,
              onPressed: playback.hasNext ? playback.next : null,
            );
          },
        ),
        ListenableBuilder(
          listenable: playback.controlsListenable,
          builder: (context, _) {
            final loop = playback.loopMode;
            return IconButton(
              icon: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    loop == LoopMode.one
                        ? Icons.repeat_one_rounded
                        : Icons.repeat_rounded,
                    size: 24,
                  ),
                  if (loop == LoopMode.all)
                    Positioned(
                      child: Text(
                        'A',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                ],
              ),
              color: loop != LoopMode.off
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
              tooltip: loop == LoopMode.one
                  ? strings.npRepeatOne
                  : (loop == LoopMode.all
                        ? strings.npRepeatAll
                        : strings.npRepeatOff),
              onPressed: playback.toggleLoopMode,
            );
          },
        ),
      ],
    );
  }
}
