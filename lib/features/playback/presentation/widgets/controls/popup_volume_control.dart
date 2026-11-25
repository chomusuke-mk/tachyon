import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/playback/playback_controller.dart';

/// Anchor volume button opening an animated overlay slider and mute toggle.
class PopupVolumeControl extends StatefulWidget {
  /// Playback controller driving [PlaybackController.volumeListenable] and updates.
  final PlaybackController playback;

  /// Callback toggling between muted (`0.0`) and the restored volume level.
  final VoidCallback onToggleMute;

  /// Tooltip string shown on hover/long press over the anchor volume button.
  final String tooltip;

  /// Creates a [PopupVolumeControl].
  const PopupVolumeControl({
    super.key,
    required this.playback,
    required this.onToggleMute,
    required this.tooltip,
  });

  @override
  State<PopupVolumeControl> createState() => _PopupVolumeControlState();
}

class _PopupVolumeControlState extends State<PopupVolumeControl>
    with SingleTickerProviderStateMixin {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutBack,
    );
  }

  void _togglePopup() {
    if (_overlayEntry == null) {
      _showPopup();
    } else {
      _hidePopup();
    }
  }

  void _showPopup() {
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
    _animationController.forward();
  }

  Future<void> _hidePopup() async {
    await _animationController.reverse();
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;

        return Stack(
          children: [
            // Translucent barrier to capture taps outside the volume popover.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hidePopup,
              ),
            ),
            // Floating volume pill anchored just above the trigger icon button.
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(-12, -10),
              child: Material(
                color: Colors.transparent,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  alignment: Alignment.bottomLeft,
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    // Scoped strictly to volumeListenable.
                    child: ValueListenableBuilder<double>(
                      valueListenable: widget.playback.volumeListenable,
                      builder: (context, volume, _) {
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 4),
                            IconButton(
                              icon: Icon(
                                volume == 0.0
                                    ? Icons.volume_off_rounded
                                    : (volume > 0.5
                                          ? Icons.volume_up_rounded
                                          : Icons.volume_down_rounded),
                              ),
                              color: colorScheme.onSurface,
                              onPressed: widget.onToggleMute,
                            ),
                            SizedBox(
                              width: 120,
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 4.0,
                                  thumbShape: const RoundSliderThumbShape(
                                    enabledThumbRadius: 6.0,
                                  ),
                                  overlayShape: const RoundSliderOverlayShape(
                                    overlayRadius: 14.0,
                                  ),
                                ),
                                child: Slider(
                                  value: volume.clamp(
                                    AppDefaults.volumeMin,
                                    AppDefaults.volumeMax,
                                  ),
                                  min: AppDefaults.volumeMin,
                                  max: AppDefaults.volumeMax,
                                  onChanged: widget.playback.setVolume,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Anchor button that stays aligned inside the Now Playing control bar.
    return RepaintBoundary(
      child: CompositedTransformTarget(
        link: _layerLink,
        child: ValueListenableBuilder<double>(
          valueListenable: widget.playback.volumeListenable,
          builder: (context, vol, _) {
            return IconButton(
              icon: Icon(
                vol == 0.0
                    ? Icons.volume_off_rounded
                    : (vol > 0.5
                          ? Icons.volume_up_rounded
                          : Icons.volume_down_rounded),
                size: 28,
              ),
              tooltip: widget.tooltip,
              color: Theme.of(context).colorScheme.onSurface,
              onPressed: _togglePopup,
            );
          },
        ),
      ),
    );
  }
}
