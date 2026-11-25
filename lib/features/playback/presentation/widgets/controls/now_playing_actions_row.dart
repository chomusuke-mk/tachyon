import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/playback/presentation/widgets/controls/popup_volume_control.dart';

/// Secondary control strip in Now Playing containing volume, favorite/like,
/// and add-to-playlist or save-radio-station actions.
class NowPlayingActionsRow extends StatelessWidget {
  /// Playback controller backing [PopupVolumeControl].
  final PlaybackController playback;

  /// Localized strings for action tooltips.
  final AppStringKey strings;

  /// Active color scheme for liked/saved icon emphasis.
  final ColorScheme colorScheme;

  /// Whether a radio live stream is currently active instead of a local track.
  final bool isRadio;

  /// Whether the active track or station is marked as a favorite.
  final bool isItemLiked;

  /// Whether the active radio station is already saved in the user library.
  final bool isRadioInLibrary;

  /// Whether a local track is available to add to a playlist.
  final bool hasTrack;

  /// Callback toggling audio mute state.
  final VoidCallback onToggleMute;

  /// Callback toggling favorite status for the current track or radio station.
  final VoidCallback onToggleLike;

  /// Callback adding the current track to a playlist or saving a radio station.
  final VoidCallback? onSecondaryAction;

  /// Creates a [NowPlayingActionsRow].
  const NowPlayingActionsRow({
    super.key,
    required this.playback,
    required this.strings,
    required this.colorScheme,
    required this.isRadio,
    required this.isItemLiked,
    required this.isRadioInLibrary,
    required this.hasTrack,
    required this.onToggleMute,
    required this.onToggleLike,
    required this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        PopupVolumeControl(
          playback: playback,
          tooltip: strings.npVolume,
          onToggleMute: onToggleMute,
        ),
        IconButton(
          tooltip: isItemLiked
              ? (isRadio ? strings.rdUnlike : strings.npUnlike)
              : (isRadio ? strings.rdLike : strings.npLike),
          onPressed: onToggleLike,
          icon: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (Widget child, Animation<double> animation) {
              return ScaleTransition(scale: animation, child: child);
            },
            child: Icon(
              isItemLiked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              // Key distinguishes filled vs outline heart for AnimatedSwitcher.
              key: ValueKey<bool>(isItemLiked),
              size: 28,
              color: isItemLiked
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (isRadio)
          IconButton(
            onPressed: isRadioInLibrary ? null : onSecondaryAction,
            icon: Icon(
              isRadioInLibrary
                  ? Icons.bookmark_added_rounded
                  : Icons.add_rounded,
              size: 28,
              color: isRadioInLibrary ? colorScheme.primary : null,
            ),
            tooltip: isRadioInLibrary
                ? strings.rdAlreadyInLibrary
                : strings.rdSaveToLibrary,
          )
        else
          IconButton(
            onPressed: hasTrack ? onSecondaryAction : null,
            icon: const Icon(Icons.add_rounded, size: 28),
            tooltip: strings.npAddToPlaylist,
          ),
      ],
    );
  }
}
