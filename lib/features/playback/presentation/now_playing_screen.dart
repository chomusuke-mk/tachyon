import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/features/playlists/presentation/playlists_controller.dart';
import 'package:tachyon/features/library/domain/thumbnail_quality.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';
import 'package:tachyon/shared/widgets/album_art_image.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

import 'audio_effects_sheet.dart';
import 'lyrics_view.dart';
import 'playback_controller.dart';
import 'lyrics_controller.dart';
import 'queue_drawer.dart';
import 'waveform_slider.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with WidgetsBindingObserver {
  bool _showLyrics = false;
  bool _showQueue = false;
  bool _hasInitializedViewSettings = false;
  LyricsController? _lyricsController;
  double _lastUnmutedVolume = AppDefaults.volumeDefault;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _lyricsController = context.read<LyricsController>();
    if (!_hasInitializedViewSettings) {
      _hasInitializedViewSettings = true;
      try {
        final settings = context.read<SettingsRepository>();
        _showLyrics = settings.getPlaybackShowLyrics();
        _showQueue = settings.getPlaybackShowQueue();
      } catch (_) {
        // Fallback if SettingsRepository is not provided (e.g. in isolated widget tests)
      }
      if (_showLyrics) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _showLyrics) {
            _lyricsController?.setLyricsViewVisible(true);
          }
        });
      }
    }
  }

  Future<void> _toggleLike() async {
    final playback = context.read<PlaybackController>();
    final track = playback.currentTrack;
    if (track == null || track.trackId == null) return;

    try {
      final playlists = context.read<PlaylistsController?>();
      if (playlists != null) {
        await playlists.toggleLike(track.trackId!, track.filePath);
      }
    } catch (_) {}
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
      playback.setVolume(
        _lastUnmutedVolume > 0 ? _lastUnmutedVolume : AppDefaults.volumeDefault,
      );
    }
  }

  void _toggleLyrics() {
    final isNarrow = MediaQuery.sizeOf(context).width < 588;
    setState(() {
      _showLyrics = !_showLyrics;
      if (_showLyrics && isNarrow && _showQueue) {
        _showQueue = false;
      }
    });
    _lyricsController?.setLyricsViewVisible(_showLyrics);
    try {
      final settings = context.read<SettingsRepository>();
      settings.setPlaybackShowLyrics(_showLyrics);
      settings.setPlaybackShowQueue(_showQueue);
    } catch (_) {}
  }

  void _toggleQueue() {
    final isNarrow = MediaQuery.sizeOf(context).width < 588;
    setState(() {
      _showQueue = !_showQueue;
      if (_showQueue && isNarrow && _showLyrics) {
        _showLyrics = false;
        _lyricsController?.setLyricsViewVisible(false);
      }
    });
    try {
      final settings = context.read<SettingsRepository>();
      settings.setPlaybackShowLyrics(_showLyrics);
      settings.setPlaybackShowQueue(_showQueue);
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_showLyrics) {
      if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden ||
          state == AppLifecycleState.detached) {
        _lyricsController?.setLyricsViewVisible(false);
      } else if (state == AppLifecycleState.resumed) {
        _lyricsController?.setLyricsViewVisible(true);
      }
    }
  }

  @override
  void dispose() {
    _lyricsController?.setLyricsViewVisible(false);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final currentTrack = playback.currentTrack;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

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

    final double currentWidth = MediaQuery.sizeOf(context).width;

    final Widget appTopBar = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 2.0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 32),
            tooltip: 'Minimize',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.speaker_group_rounded),
            tooltip: strings.npAudioDevices,
            color: colorScheme.onSurface,
            onPressed: () => _showAudioDevicesDialog(context),
          ),
          IconButton(
            icon: Icon(
              _showLyrics ? Icons.music_note_rounded : Icons.lyrics_rounded,
              color: _showLyrics ? colorScheme.primary : colorScheme.onSurface,
            ),
            tooltip: strings.npLyrics,
            onPressed: _toggleLyrics,
          ),
          IconButton(
            icon: Icon(
              Icons.queue_music_rounded,
              color: _showQueue ? colorScheme.primary : colorScheme.onSurface,
            ),
            tooltip: strings.npQueue,
            onPressed: _toggleQueue,
          ),
          IconButton(
            icon: const Icon(Icons.equalizer_rounded),
            tooltip: strings.npAudioControls,
            color: colorScheme.onSurface,
            onPressed: () => _openAudioControls(context),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          // 1. Ambient Blurred Backdrop
          Positioned.fill(
            child: RepaintBoundary(
              child: _buildAmbientBackdrop(currentTrack.filePath, colorScheme),
            ),
          ),

          // 2. Main Responsive Content Layer
          SafeArea(
            child: Column(
              children: [
                // Top App Bar
                appTopBar,
                Expanded(
                  child: currentWidth >= 588 && _showQueue
                      ? Row(
                          key: const ValueKey('queue_and_player'),
                          children: [
                            Expanded(child: QueueView()),
                            Expanded(
                              child: _buildPlayer(
                                currentTrack,
                                context,
                                preferVertical: true,
                                hideQueue: true,
                                hideLyrics: true,
                              ),
                            ),
                          ],
                        )
                      : currentWidth >= 588 && _showLyrics
                      ? Row(
                          key: const ValueKey('lyrics_and_player'),
                          children: [
                            Expanded(
                              child: LyricsView(
                                key: const ValueKey('lyrics_view'),
                                filePath: currentTrack.filePath,
                                onSeek: playback.seek,
                              ),
                            ),
                            Expanded(
                              child: _buildPlayer(
                                currentTrack,
                                context,
                                preferVertical: true,
                                hideQueue: false,
                                hideLyrics: true,
                              ),
                            ),
                          ],
                        )
                      : _buildPlayer(
                          currentTrack,
                          context,
                          key: ValueKey(
                            _showQueue
                                ? 'narrow_queue'
                                : _showLyrics
                                ? 'narrow_lyrics'
                                : 'player_only',
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayer(
    QueueItem currentTrack,
    BuildContext context, {
    bool preferVertical = false,
    bool hideLyrics = false,
    bool hideQueue = false,
    Key? key,
  }) {
    final playback = context.watch<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final playlists = context.watch<PlaylistsController?>();
    final isCurrentTrackLiked = currentTrack.trackId != null &&
        (playlists?.isTrackLiked(currentTrack.trackId!) ?? false);

    final Widget playerControls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 10.0,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _PopupVolumeControl(
                playback: playback,
                tooltip: strings.npVolume,
                onToggleMute: () => _toggleMute(playback),
              ),
              IconButton(
                tooltip: isCurrentTrackLiked
                    ? strings.npLiked
                    : strings.npUnliked,
                onPressed: _toggleLike,
                icon: AnimatedSwitcher(
                  // 1. Duración rápida y con energía
                  duration: const Duration(milliseconds: 400),

                  // 2. Curvas de animación: easeOutBack da ese efecto de "rebote" al inflarse
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeIn,

                  // 3. Constructor de la transición: Escala el ícono desde el centro
                  transitionBuilder:
                      (Widget child, Animation<double> animation) {
                        return ScaleTransition(
                          scale: animation,
                          child: child, // Opcional: puedes envolver 'child' en FadeTransition si también quieres que se desvanezca
                        );
                      },

                  // 4. El contenido: El ícono en sí
                  child: Icon(
                    isCurrentTrackLiked
                        ? Icons.favorite_rounded
                        : Icons.favorite_border_rounded,

                    // ¡EL KEY ES OBLIGATORIO! Le dice al Switcher que son dos widgets diferentes.
                    key: ValueKey<bool>(isCurrentTrackLiked),

                    size: 28,
                    color: isCurrentTrackLiked
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),

              IconButton(
                onPressed: _toggleQueue,
                icon: const Icon(Icons.add_rounded, size: 28),
                tooltip: strings.npQueue,
              ),
            ],
          ),
          RepaintBoundary(
            child: WaveformSlider(
              positionListenable: playback.positionListenable,
              position: playback.position,
              duration: playback.duration,
              isBuffering: playback.isBuffering,
              onSeek: playback.seek,
              currentIndex: playback.currentIndex + 1,
              totalCount: playback.queue.length + 1,
              playlistPosition: () =>
                  playback.queue
                      .take(playback.currentIndex)
                      .fold<Duration>(
                        Duration.zero,
                        (sum, item) => sum + item.duration,
                      ) +
                  playback.position,
              playlistDuration: () => playback.queue.fold<Duration>(
                Duration.zero,
                (sum, item) => sum + item.duration,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              IconButton(
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.shuffle_rounded, size: 24),
                    if (playback.isShuffled)
                      Positioned(
                        bottom: 0,
                        child: Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                  ],
                ),
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
              Flexible(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: 70,
                    maxHeight: 70,
                  ),
                  child: AspectRatio(
                    aspectRatio: 1.0,
                    child: IconButton.filled(
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
                          duration: const Duration(
                            milliseconds: 150,
                          ), // Duración de la animación
                          transitionBuilder:
                              (Widget child, Animation<double> animation) {
                                // 2. Definimos la transición: Rotación + Escala
                                return ScaleTransition(
                                  scale: animation,
                                  child: RotationTransition(
                                    // Un Tween de 0.5 a 1.0 hace que dé medio giro (180 grados).
                                    // Si quieres un giro completo, usa simplemente: turns: animation
                                    turns: Tween<double>(
                                      begin: 0.9,
                                      end: 1.0,
                                    ).animate(animation),
                                    child: child,
                                  ),
                                );
                              },
                          child: Icon(
                            playback.isPlaying
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            // ¡EL KEY ES OBLIGATORIO!
                            // Sin esto, Flutter piensa que es el mismo ícono y no lo anima.
                            key: ValueKey<bool>(playback.isPlaying),
                            size: 40,
                          ),
                        ),
                      ),
                      tooltip: playback.isPlaying
                          ? strings.npPause
                          : strings.npPlay,
                      onPressed: () {
                        playback.playOrPause();
                      },
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.skip_next_rounded, size: 36),
                tooltip: strings.npNext,
                onPressed: playback.hasNext ? playback.next : null,
              ),
              IconButton(
                icon: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      playback.loopMode != Loop.off
                          ? (playback.loopMode == Loop.one
                                ? Icons.repeat_one_rounded
                                : Icons.repeat_rounded)
                          : Icons.repeat_rounded,
                      size: 24,
                    ),
                    if (playback.loopMode == Loop.all)
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
        ],
      ),
    );

    final Widget playerTitle = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            currentTrack.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 2),
          Text(
            currentTrack.artist,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge
                ?.copyWith(color: colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final bool canFitVertically = constraints.maxHeight > 400;
        final bool canFitHorizontally = constraints.maxWidth > 590;
        if (canFitHorizontally && !(preferVertical && canFitVertically)) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: !hideQueue && _showQueue
                      ? QueueView(key: const ValueKey('queue_view'))
                      : !hideLyrics && _showLyrics
                      ? LyricsView(
                          key: const ValueKey('lyrics_view'),
                          filePath: currentTrack.filePath,
                          onSeek: playback.seek,
                        )
                      : _buildHeroCoverArt(
                          currentTrack.filePath,
                          context,
                          key: const ValueKey('cover_art_view'),
                        ),
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [playerTitle, playerControls],
                ),
              ),
            ],
          );
        }
        if (canFitVertically) {
          return Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: !hideQueue && _showQueue
                      ? QueueView(key: const ValueKey('queue_view'))
                      : !hideLyrics && _showLyrics
                      ? LyricsView(
                          key: const ValueKey('lyrics_view'),
                          filePath: currentTrack.filePath,
                          onSeek: playback.seek,
                        )
                      : _buildHeroCoverArt(
                          currentTrack.filePath,
                          context,
                          key: const ValueKey('cover_art_view'),
                        ),
                ),
              ),
              playerTitle,
              playerControls,
              SizedBox(height: 12),
            ],
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: !hideQueue && _showQueue
              ? QueueView(key: const ValueKey('queue_view'))
              : !hideLyrics && _showLyrics
              ? LyricsView(
                  key: const ValueKey('lyrics_view'),
                  filePath: currentTrack.filePath,
                  onSeek: playback.seek,
                )
              : Column(
                  key: const ValueKey('cover_art_view'),
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [playerTitle, playerControls],
                ),
        );
      },
    );
  }

  // Middle Section: Animated Switcher between Cover Art Hero and LyricsView
  //Expanded(
  //  child: AnimatedSwitcher(
  //    duration: const Duration(milliseconds: 300),
  //    child: _showLyrics
  //        ? LyricsView(
  //            key: const ValueKey('lyrics_view'),
  //            filePath: currentTrack.filePath,
  //            onSeek: playback.seek,
  //          )
  //        : _buildHeroCoverArt(currentTrack.filePath, context),
  //  ),
  //),
  //// Bottom Controls Block
  //Padding(
  //  padding: const EdgeInsets.symmetric(
  //    horizontal: 24.0,
  //    vertical: 8.0,
  //  ),
  //  child: Column(
  //    mainAxisSize: MainAxisSize.min,
  //    children: [
  //      Row(
  //        children: [
  //          //IconButton(
  //          //  icon: Icon(
  //          //    playback.volume == 0.0
  //          //        ? Icons.volume_off_rounded
  //          //        : (playback.volume > 0.5
  //          //              ? Icons.volume_up_rounded
  //          //              : Icons.volume_down_rounded),
  //          //    size: 20,
  //          //  ),
  //          //  tooltip: strings.npVolume,
  //          //  onPressed: () => _toggleMute(playback),
  //          //),
  //          //Expanded(
  //          //  child: Slider(
  //          //    value: playback.volume.clamp(0.0, 100.0),
  //          //    min: 0.0,
  //          //    max: 100.0,
  //          //    onChanged: playback.setVolume,
  //          //  ),
  //          //),
  //        ],
  //      ),
  //    ],
  //  ),
  //),
  Widget _buildAmbientBackdrop(String filePath, ColorScheme colorScheme) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (filePath.isNotEmpty)
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 32.0, sigmaY: 32.0),
              child: AlbumArtImage(
                filePath: filePath,
                fit: BoxFit.cover,
                cacheWidth: 128,
                cacheHeight: 128,
              ),
            ),
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
    );
  }

  Widget _buildHeroCoverArt(String filePath, BuildContext context, {Key? key}) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth < constraints.maxHeight
              ? constraints.maxWidth * 0.8
              : constraints.maxHeight * 0.8;

          return Hero(
            key: key,
            tag: 'now_playing_art_$filePath',
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
                child: AlbumArtImage(
                  filePath: filePath,
                  quality: ThumbnailQuality.high,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _openAudioControls(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    showModalBottomSheet(
      useSafeArea: true,
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (context) => const AudioEffectsSheet(),
    );
  }

  void _showAudioDevicesDialog(BuildContext context) async {
    final playback = context.read<PlaybackController>();
    final settings = context.read<SettingsController>();
    final strings = context.read<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final devices = await playback.getAudioDevices();
    if (!context.mounted) return;

    final currentDeviceId = settings.audioOutputDeviceId;

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.speaker_group_rounded, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      strings.npAudioDevices,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    ListTile(
                      leading: const Icon(Icons.settings_suggest_rounded),
                      title: Text(strings.npAudioDeviceDefault),
                      trailing: (currentDeviceId == null || currentDeviceId.isEmpty)
                          ? Icon(Icons.check_rounded, color: colorScheme.primary)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      onTap: () async {
                        await settings.setAudioOutputDeviceId(null);
                        if (devices.isNotEmpty) {
                          final defaultDev = devices.firstWhere(
                            (d) => d.isDefault,
                            orElse: () => devices.first,
                          );
                          await playback.setAudioDevice(defaultDev);
                        }
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                    const Divider(),
                    ...devices.map((device) {
                      final isSelected = currentDeviceId == device.id ||
                          ((currentDeviceId == null || currentDeviceId.isEmpty) &&
                              device.isDefault);
                      return ListTile(
                        leading: Icon(
                          device.name.toLowerCase().contains('headphone')
                              ? Icons.headphones_rounded
                              : Icons.speaker_rounded,
                        ),
                        title: Text(device.name),
                        trailing: isSelected
                            ? Icon(Icons.check_rounded, color: colorScheme.primary)
                            : null,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        onTap: () async {
                          await settings.setAudioOutputDeviceId(device.id);
                          await playback.setAudioDevice(device);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PopupVolumeControl extends StatefulWidget {
  final PlaybackController playback;
  final VoidCallback onToggleMute;
  final String tooltip;

  const _PopupVolumeControl({
    required this.playback,
    required this.onToggleMute,
    required this.tooltip,
  });

  @override
  State<_PopupVolumeControl> createState() => _PopupVolumeControlState();
}

class _PopupVolumeControlState extends State<_PopupVolumeControl>
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
            // Capa transparente para detectar toques fuera del popup
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _hidePopup,
              ),
            ),
            // Popup anclado al botón inferior
            CompositedTransformFollower(
              link: _layerLink,
              showWhenUnlinked: false,
              targetAnchor: Alignment.topLeft,
              followerAnchor: Alignment.bottomLeft,
              offset: const Offset(
                -12,
                -10,
              ), // Un pequeño margen debajo del botón
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
                    // Usar ListenableBuilder permite que el interior se actualice en vivo
                    // con el estado del PlaybackController
                    child: ListenableBuilder(
                      listenable: widget.playback,
                      builder: (context, _) {
                        final volume = widget.playback.volume;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 4),
                            // Botón de mute dentro del Popup
                            IconButton(
                              icon: Icon(
                                volume == 0.0
                                    ? Icons.volume_off_rounded
                                    : (volume > 50.0
                                          ? Icons.volume_up_rounded
                                          : Icons.volume_down_rounded),
                              ),
                              color: colorScheme.onSurface,
                              onPressed: widget.onToggleMute,
                            ),
                            // Slider de volumen
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
    // Este es el botón que se queda anclado en la App Bar
    return CompositedTransformTarget(
      link: _layerLink,
      child: IconButton(
        icon: Icon(
          widget.playback.volume == 0.0
              ? Icons.volume_off_rounded
              : (widget.playback.volume > 50.0
                    ? Icons.volume_up_rounded
                    : Icons.volume_down_rounded),
          size: 28,
        ),
        tooltip: widget.tooltip,
        color: Theme.of(context).colorScheme.onSurface,
        onPressed: _togglePopup,
      ),
    );
  }
}
