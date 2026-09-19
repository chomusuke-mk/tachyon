import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/services/wakelock_service.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

import 'audio_effects_sheet.dart';
import 'lyrics_view.dart';
import 'playback_controller.dart';
import 'queue_drawer.dart';
import 'waveform_slider.dart';

/// Fullscreen Material 3 Now Playing screen.
///
/// Features:
/// - Responsive layout: mobile single-column vs desktop side-by-side (720dp breakpoint)
/// - Ambient blurred album artwork backdrop with dark scrim overlay
/// - Hero album art transition linked with MiniPlayerBar
/// - Interactive WaveformSlider with tabular numeric figures
/// - Full transport controls (Play/Pause, Previous with smart 3s restart, Next, 3-way Repeat, Shuffle)
/// - Integrated Volume slider with mute toggle
/// - Flip switch between Hero Cover Art and Synchronized LyricsView
/// - Heart button toggling track inclusion in Liked Songs playlist via AppDatabase
/// - Display wakelock integration keeping screen awake during playback
class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with WidgetsBindingObserver {
  bool _showLyrics = false;
  int _desktopRightPanelTab = 0; // 0: Lyrics, 1: Queue
  bool _isCurrentTrackLiked = false;
  String? _lastLikedCheckUri;
  double _lastUnmutedVolume = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncWakelock();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncWakelock();
    _checkLikedStatus();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncWakelock();
    } else {
      WakelockService.disable();
    }
  }

  void _syncWakelock() {
    if (!mounted) return;
    final playback = context.read<PlaybackController>();
    if (playback.isPlaying) {
      WakelockService.enable();
    } else {
      WakelockService.disable();
    }
  }

  Future<void> _checkLikedStatus() async {
    final playback = context.read<PlaybackController>();
    final track = playback.currentTrack;
    if (track == null || track.uri == _lastLikedCheckUri) return;

    _lastLikedCheckUri = track.uri;
    if (track.trackId != null) {
      final db = context.read<AppDatabase>();
      final liked = await db.isTrackLiked(track.trackId!);
      if (mounted && _lastLikedCheckUri == track.uri) {
        setState(() => _isCurrentTrackLiked = liked);
      }
    } else {
      if (mounted) {
        setState(() => _isCurrentTrackLiked = false);
      }
    }
  }

  Future<void> _toggleLike() async {
    final playback = context.read<PlaybackController>();
    final track = playback.currentTrack;
    if (track == null || track.trackId == null) return;

    final db = context.read<AppDatabase>();
    await db.toggleLikeTrack(track.trackId!, track.uri);
    final liked = await db.isTrackLiked(track.trackId!);
    if (mounted) {
      setState(() => _isCurrentTrackLiked = liked);
    }
  }

  void _handlePrevious(PlaybackController playback) {
    if (playback.position > const Duration(seconds: 3)) {
      playback.seek(Duration.zero);
    } else if (playback.hasPrevious) {
      playback.previous();
    } else {
      playback.seek(Duration.zero);
    }
  }

  void _toggleMute(PlaybackController playback) {
    if (playback.volume > 0.0) {
      _lastUnmutedVolume = playback.volume;
      playback.setVolume(0.0);
    } else {
      playback.setVolume(_lastUnmutedVolume > 0 ? _lastUnmutedVolume : 100.0);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    WakelockService.disable();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final currentTrack = playback.currentTrack;
    final isDesktop = TachyonBreakpoints.isDesktop(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Keep wakelock state in sync with playback playing changes
    if (playback.isPlaying) {
      WakelockService.enable();
    } else {
      WakelockService.disable();
    }

    if (currentTrack == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Text(strings.npQueueEmpty, style: theme.textTheme.titleMedium),
        ),
      );
    }

    // Refresh liked status if track changed
    if (currentTrack.uri != _lastLikedCheckUri) {
      _checkLikedStatus();
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // 1. Ambient Blurred Backdrop
          Positioned.fill(
            child: _buildAmbientBackdrop(currentTrack.uri, colorScheme),
          ),

          // 2. Main Responsive Content Layer
          SafeArea(
            child: isDesktop
                ? _buildDesktopLayout(
                    context,
                    playback,
                    currentTrack,
                    strings,
                    colorScheme,
                  )
                : _buildMobileLayout(
                    context,
                    playback,
                    currentTrack,
                    strings,
                    colorScheme,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientBackdrop(String uri, ColorScheme colorScheme) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (uri.isNotEmpty) AlbumArtImage(uri: uri, fit: BoxFit.cover),
        BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 32.0, sigmaY: 32.0),
          child: Container(
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
        ),
      ],
    );
  }

  // Mobile Portrait Layout (< 720dp)
  Widget _buildMobileLayout(
    BuildContext context,
    PlaybackController playback,
    QueueItem track,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    return Column(
      children: [
        // Top App Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
                tooltip: 'Minimize',
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      strings.npTitle.toUpperCase(),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      track.album.isNotEmpty ? track.album : strings.alTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _showLyrics ? Icons.music_note_rounded : Icons.lyrics_rounded,
                  color: _showLyrics
                      ? colorScheme.primary
                      : colorScheme.onSurface,
                ),
                tooltip: strings.npLyrics,
                onPressed: () => setState(() => _showLyrics = !_showLyrics),
              ),
              IconButton(
                icon: const Icon(Icons.tune_rounded),
                tooltip: strings.npAudioControls,
                onPressed: () => _openAudioControls(context),
              ),
            ],
          ),
        ),

        // Middle Section: Animated Switcher between Cover Art Hero and LyricsView
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: _showLyrics
                ? LyricsView(
                    key: const ValueKey('lyrics_view'),
                    uri: track.uri,
                    onSeek: playback.seek,
                  )
                : _buildHeroCoverArt(track.uri, context),
          ),
        ),

        // Bottom Controls Block
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Track Info Row (Title, Artist, Like Heart Button)
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      _isCurrentTrackLiked
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      size: 28,
                      color: _isCurrentTrackLiked
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    tooltip: _isCurrentTrackLiked
                        ? strings.npLiked
                        : strings.npUnliked,
                    onPressed: _toggleLike,
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Interactive Waveform / Seek Slider
              WaveformSlider(
                position: playback.position,
                duration: playback.duration,
                isBuffering: playback.isBuffering,
                onSeek: playback.seek,
              ),
              const SizedBox(height: 8),

              // Primary Transport Controls (Shuffle, Prev, Play/Pause, Next, Repeat)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.shuffle_rounded, size: 24),
                    color: playback.isShuffled
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    tooltip: playback.isShuffled
                        ? strings.npShuffleOn
                        : strings.npShuffleOff,
                    onPressed: playback.toggleShuffle,
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_previous_rounded, size: 36),
                    tooltip: strings.npPrevious,
                    onPressed: () => _handlePrevious(playback),
                  ),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.primary,
                      foregroundColor: colorScheme.onPrimary,
                      padding: const EdgeInsets.all(16),
                    ),
                    icon: Icon(
                      playback.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                      size: 38,
                    ),
                    tooltip: playback.isPlaying
                        ? strings.npPause
                        : strings.npPlay,
                    onPressed: () {
                      playback.playOrPause();
                      _syncWakelock();
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.skip_next_rounded, size: 36),
                    tooltip: strings.npNext,
                    onPressed: playback.hasNext ? playback.next : null,
                  ),
                  IconButton(
                    icon: Icon(
                      playback.loopMode != Loop.off
                          ? (playback.loopMode == Loop.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded)
                          : Icons.repeat_rounded,
                      size: 24,
                    ),
                    color: playback.loopMode != Loop.off
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                    tooltip: playback.loopMode == Loop.one
                        ? strings.npRepeatOne
                        : (playback.loopMode == Loop.all
                              ? strings.npRepeatAll
                              : strings.npRepeatOff),
                    onPressed: playback.toggleLoopMode,
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Volume & Queue Bottom Row
              Row(
                children: [
                  IconButton(
                    icon: Icon(
                      playback.volume == 0.0
                          ? Icons.volume_off_rounded
                          : (playback.volume > 0.5
                                ? Icons.volume_up_rounded
                                : Icons.volume_down_rounded),
                      size: 20,
                    ),
                    tooltip: strings.npVolume,
                    onPressed: () => _toggleMute(playback),
                  ),
                  Expanded(
                    child: Slider(
                      value: playback.volume.clamp(0.0, 100.0),
                      min: 0.0,
                      max: 100.0,
                      onChanged: playback.setVolume,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openQueueDrawer(context),
                    icon: const Icon(Icons.queue_music_rounded),
                    label: Text(strings.npQueue),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Desktop / Landscape Layout (>= 720dp)
  Widget _buildDesktopLayout(
    BuildContext context,
    PlaybackController playback,
    QueueItem track,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Row(
        children: [
          // Left Panel: Cover Art, Metadata, Waveform, Controls, Volume
          Expanded(
            flex: 5,
            child: Column(
              children: [
                // Desktop Header
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      strings.npTitle,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(
                        _isCurrentTrackLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        color: _isCurrentTrackLiked
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      tooltip: _isCurrentTrackLiked
                          ? strings.npLiked
                          : strings.npUnliked,
                      onPressed: _toggleLike,
                    ),
                    IconButton(
                      icon: const Icon(Icons.tune_rounded),
                      tooltip: strings.npAudioControls,
                      onPressed: () => _openAudioControls(context),
                    ),
                  ],
                ),
                const Spacer(),

                // Hero Cover Art
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: 360,
                      maxHeight: 360,
                    ),
                    child: _buildHeroCoverArt(track.uri, context),
                  ),
                ),
                const Spacer(),

                // Track Metadata
                Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '${track.artist} • ${track.album}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),

                // Waveform Slider
                WaveformSlider(
                  position: playback.position,
                  duration: playback.duration,
                  isBuffering: playback.isBuffering,
                  onSeek: playback.seek,
                ),
                const SizedBox(height: 12),

                // Transport Controls Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.shuffle_rounded),
                      color: playback.isShuffled
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      tooltip: playback.isShuffled
                          ? strings.npShuffleOn
                          : strings.npShuffleOff,
                      onPressed: playback.toggleShuffle,
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.skip_previous_rounded, size: 32),
                      tooltip: strings.npPrevious,
                      onPressed: () => _handlePrevious(playback),
                    ),
                    const SizedBox(width: 12),
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: colorScheme.primary,
                        foregroundColor: colorScheme.onPrimary,
                        padding: const EdgeInsets.all(16),
                      ),
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 36,
                      ),
                      tooltip: playback.isPlaying
                          ? strings.npPause
                          : strings.npPlay,
                      onPressed: () {
                        playback.playOrPause();
                        _syncWakelock();
                      },
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: const Icon(Icons.skip_next_rounded, size: 32),
                      tooltip: strings.npNext,
                      onPressed: playback.hasNext ? playback.next : null,
                    ),
                    const SizedBox(width: 12),
                    IconButton(
                      icon: Icon(
                        playback.loopMode != Loop.off
                            ? (playback.loopMode == Loop.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded)
                            : Icons.repeat_rounded,
                      ),
                      color: playback.loopMode != Loop.off
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                      tooltip: playback.loopMode == Loop.one
                          ? strings.npRepeatOne
                          : (playback.loopMode == Loop.all
                                ? strings.npRepeatAll
                                : strings.npRepeatOff),
                      onPressed: playback.toggleLoopMode,
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Volume Bar
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(
                        playback.volume == 0.0
                            ? Icons.volume_off_rounded
                            : (playback.volume > 0.5
                                  ? Icons.volume_up_rounded
                                  : Icons.volume_down_rounded),
                        size: 20,
                      ),
                      tooltip: strings.npVolume,
                      onPressed: () => _toggleMute(playback),
                    ),
                    SizedBox(
                      width: 220,
                      child: Slider(
                        value: playback.volume.clamp(0.0, 100.0),
                        min: 0.0,
                        max: 100.0,
                        onChanged: playback.setVolume,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(width: 32),
          const VerticalDivider(width: 1),
          const SizedBox(width: 32),

          // Right Panel: Lyrics OR Queue Side Panel
          Expanded(
            flex: 5,
            child: Column(
              children: [
                // Right Panel Header Switcher (Lyrics / Queue)
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(
                      value: 0,
                      icon: const Icon(Icons.lyrics_rounded),
                      label: Text(strings.npLyrics),
                    ),
                    ButtonSegment(
                      value: 1,
                      icon: const Icon(Icons.queue_music_rounded),
                      label: Text(strings.npQueue),
                    ),
                  ],
                  selected: {_desktopRightPanelTab},
                  onSelectionChanged: (set) =>
                      setState(() => _desktopRightPanelTab = set.first),
                ),
                const SizedBox(height: 16),

                // Right Panel Content
                Expanded(
                  child: Card(
                    color: colorScheme.surfaceContainerLow.withValues(
                      alpha: 0.6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: _desktopRightPanelTab == 0
                        ? LyricsView(uri: track.uri, onSeek: playback.seek)
                        : const QueueView(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCoverArt(String uri, BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth * 0.85
            : constraints.maxHeight * 0.85;

        return Center(
          child: Hero(
            tag: 'now_playing_art_$uri',
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24.0),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24.0),
                child: AlbumArtImage(uri: uri, fit: BoxFit.cover),
              ),
            ),
          ),
        );
      },
    );
  }

  void _openQueueDrawer(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const QueueDrawerSheet(),
    );
  }

  void _openAudioControls(BuildContext context) {
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AudioEffectsSheet(),
    );
  }
}
