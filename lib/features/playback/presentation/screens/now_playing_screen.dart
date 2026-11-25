import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:tachyon/core/constants/app_defaults.dart';
import 'package:tachyon/core/lifecycle/app_lifecycle_controller.dart';
import 'package:tachyon/core/playback/domain/radio_station.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/library_store.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/locales/presentation/controllers/locale_controller.dart';
import 'package:tachyon/features/playlists/presentation/controllers/playlists_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/controllers/settings_controller.dart';
import 'package:tachyon/shared/theme/app_theme.dart';
import 'package:tachyon/shared/widgets/ambient_backdrop.dart';
import 'package:tachyon/shared/widgets/track_action_helper.dart';

import 'package:tachyon/features/playback/presentation/widgets/audio_effects_sheet.dart';
import 'package:tachyon/features/playback/presentation/widgets/controls/clickable_artist_names.dart';
import 'package:tachyon/features/playback/presentation/widgets/controls/now_playing_actions_row.dart';
import 'package:tachyon/features/playback/presentation/widgets/controls/now_playing_header.dart';
import 'package:tachyon/features/playback/presentation/widgets/controls/now_playing_transport_controls.dart';
import 'package:tachyon/features/playback/presentation/widgets/lyrics_view.dart';
import 'package:tachyon/features/playback/presentation/widgets/queue_drawer.dart';
import 'package:tachyon/features/playback/presentation/widgets/waveform_slider.dart';
import 'package:tachyon/features/playback/presentation/widgets/now_playing_cover_art.dart';

/// Full-screen Now Playing view with reactive artwork, synchronized lyrics,
/// playback queue access, and audio DSP controls.
class NowPlayingScreen extends StatefulWidget {
  /// Creates a [NowPlayingScreen].
  const NowPlayingScreen({super.key});

  /// Opens the Now Playing screen with standard slide-up transition.
  static void open(BuildContext context) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (context, animation, secondaryAnimation) =>
            const NowPlayingScreen(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          const curve = Curves.easeOutCubic;
          final tween = Tween(
            begin: begin,
            end: end,
          ).chain(CurveTween(curve: curve));
          return SlideTransition(
            position: animation.drive(tween),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 350),
      ),
    );
  }

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  bool _showLyrics = false;
  bool _showQueue = false;
  bool _isAppActive = true;
  bool _hasInitializedViewSettings = false;
  double _lastUnmutedVolume = AppDefaults.volumeDefault;
  AppLifecycleController? _lifecycleController;

  final ValueNotifier<double> _screenDragOffset = ValueNotifier<double>(0.0);
  bool _isDismissing = false;
  late final AnimationController _dragResetController;
  Animation<double>? _dragResetAnimation;

  bool get _isUiActive => (_lifecycleController?.isActive ?? true) && _isAppActive;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _dragResetController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    )..addListener(() {
        _screenDragOffset.value = _dragResetAnimation?.value ?? 0.0;
      });
  }

  void _onVerticalDragStart(DragStartDetails details) {
    if (_dragResetController.isAnimating) {
      _dragResetController.stop();
    }
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (_isDismissing) return;
    final delta = details.primaryDelta ?? 0.0;
    _screenDragOffset.value = math.max(0.0, _screenDragOffset.value + delta);
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (_isDismissing) return;
    final velocity = details.primaryVelocity ?? 0.0;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final dismissThreshold = math.min(150.0, screenHeight * 0.18);

    if (velocity > 350 || _screenDragOffset.value > dismissThreshold) {
      _dismissScreen();
    } else {
      _animateDragReset();
    }
  }

  void _onVerticalDragCancel() {
    if (_isDismissing) return;
    _animateDragReset();
  }

  void _animateDragReset() {
    _dragResetAnimation = Tween<double>(
      begin: _screenDragOffset.value,
      end: 0.0,
    ).animate(
      CurvedAnimation(
        parent: _dragResetController,
        curve: Curves.easeOutCubic,
      ),
    );
    _dragResetController.forward(from: 0.0);
  }

  void _dismissScreen() {
    if (_isDismissing) return;
    _isDismissing = true;
    Navigator.of(context).maybePop().then((popped) {
      if (!popped && mounted) {
        _isDismissing = false;
        _animateDragReset();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitializedViewSettings) {
      _hasInitializedViewSettings = true;
      _lifecycleController = Provider.of<AppLifecycleController?>(
        context,
        listen: false,
      );
      _lifecycleController?.modeListenable.addListener(_onLifecycleModeChanged);
      try {
        final settings = context.read<SettingsRepository>();
        _showLyrics = settings.getPlaybackShowLyrics();
        _showQueue = settings.getPlaybackShowQueue();
      } catch (_) {
        // Fallback if SettingsRepository is not provided (e.g. in isolated widget tests)
      }
    }
  }

  Future<void> _toggleLike() async {
    final playback = context.read<PlaybackController>();
    final currentPlayable = playback.currentPlayable;
    if (currentPlayable == null) return;

    try {
      if (currentPlayable is Track && currentPlayable.id != null) {
        final playlists = context.read<PlaylistsController?>();
        if (playlists != null) {
          await playlists.toggleLike(currentPlayable.id!);
        }
      } else if (currentPlayable is RadioStation) {
        final store = context.read<LibraryStore?>();
        if (store != null) {
          final existing = store.radioStations.cast<RadioStation?>().firstWhere(
            (st) =>
                st != null &&
                ((currentPlayable.id != null && st.id == currentPlayable.id) ||
                    st.streamUrl == currentPlayable.streamUrl ||
                    (st.stationUuid != null &&
                        currentPlayable.stationUuid != null &&
                        st.stationUuid == currentPlayable.stationUuid)),
            orElse: () => null,
          );

          if (existing == null || existing.id == null) {
            // Not in library -> Save to library AND like it
            final saved = await store.saveRadioStationInStore(
              currentPlayable.copyWith(isFavorite: true),
            );
            if (saved != null && saved.id != null && !saved.isFavorite) {
              await store.toggleRadioStationFavoriteInStore(saved.id!);
            }
          } else {
            // Already in library -> toggle like status
            await store.toggleRadioStationFavoriteInStore(existing.id!);
          }
        }
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
    setState(() {
      _showLyrics = !_showLyrics;
      if (_showLyrics && _showQueue) {
        _showQueue = false;
      }
    });
    try {
      final settings = context.read<SettingsRepository>();
      settings.setPlaybackShowLyrics(_showLyrics);
      settings.setPlaybackShowQueue(_showQueue);
    } catch (_) {}
  }

  void _toggleQueue() {
    setState(() {
      _showQueue = !_showQueue;
      if (_showQueue && _showLyrics) {
        _showLyrics = false;
      }
    });
    try {
      final settings = context.read<SettingsRepository>();
      settings.setPlaybackShowLyrics(_showLyrics);
      settings.setPlaybackShowQueue(_showQueue);
    } catch (_) {}
  }

  void _onLifecycleModeChanged() {
    if (_showLyrics && mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused &&
        state != AppLifecycleState.detached;
    if (_isAppActive != active) {
      _isAppActive = active;
      if (_showLyrics && mounted) {
        setState(() {});
      }
    }
  }

  @override
  void dispose() {
    _dragResetController.dispose();
    _screenDragOffset.dispose();
    _lifecycleController?.modeListenable.removeListener(_onLifecycleModeChanged);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Widget _wrapWithDragTransform(Widget child) {
    return ValueListenableBuilder<double>(
      valueListenable: _screenDragOffset,
      child: child,
      builder: (context, dragOffset, child) {
        final isDragging = dragOffset > 0.0;
        return Transform.translate(
          offset: Offset(0.0, dragOffset),
          child: ClipRRect(
            clipBehavior: isDragging ? Clip.antiAlias : Clip.none,
            borderRadius: isDragging
                ? const BorderRadius.vertical(top: Radius.circular(24.0))
                : BorderRadius.zero,
            child: child,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.read<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return ListenableBuilder(
      listenable: playback.trackListenable,
      builder: (context, _) {
        final currentPlayable = playback.currentPlayable;

        if (currentPlayable == null) {
          final emptyScaffold = Scaffold(
            appBar: AppBar(
              leading: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                tooltip: strings.commonMinimize,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            body: Center(
              child: Text(
                strings.npQueueEmpty,
                style: theme.textTheme.titleMedium,
              ),
            ),
          );

          return _wrapWithDragTransform(
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onVerticalDragStart: _onVerticalDragStart,
              onVerticalDragUpdate: _onVerticalDragUpdate,
              onVerticalDragEnd: _onVerticalDragEnd,
              onVerticalDragCancel: _onVerticalDragCancel,
              child: emptyScaffold,
            ),
          );
        }

        final double currentWidth = MediaQuery.sizeOf(context).width;
        final currentTrack = currentPlayable is Track ? currentPlayable : null;
        final isLiveStream = playback.isLiveStream;
        final canShowLyrics =
            !isLiveStream && currentTrack != null && _showLyrics;

        final Widget appTopBar = NowPlayingHeader(
          strings: strings,
          colorScheme: colorScheme,
          canToggleLyrics: !isLiveStream && currentTrack != null,
          showLyrics: _showLyrics,
          showQueue: _showQueue,
          onMinimize: () => Navigator.of(context).pop(),
          onShowAudioDevices: () => _showAudioDevicesDialog(context),
          onToggleLyrics: _toggleLyrics,
          onToggleQueue: _toggleQueue,
          onOpenAudioControls: () => _openAudioControls(context),
          onVerticalDragStart: _onVerticalDragStart,
          onVerticalDragUpdate: _onVerticalDragUpdate,
          onVerticalDragEnd: _onVerticalDragEnd,
          onVerticalDragCancel: _onVerticalDragCancel,
        );

        final Widget mainBody = currentWidth >= 588 && _showQueue
            ? Row(
                key: const ValueKey('queue_and_player'),
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragStart: _onVerticalDragStart,
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      onVerticalDragEnd: _onVerticalDragEnd,
                      onVerticalDragCancel: _onVerticalDragCancel,
                      child: _buildPlayer(
                        currentPlayable,
                        context,
                        preferVertical: true,
                        hideQueue: true,
                        hideLyrics: true,
                      ),
                    ),
                  ),
                  const Expanded(child: QueueView()),
                ],
              )
            : currentWidth >= 588 &&
                  canShowLyrics &&
                  _isUiActive
            ? Row(
                key: const ValueKey('lyrics_and_player'),
                children: [
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onVerticalDragStart: _onVerticalDragStart,
                      onVerticalDragUpdate: _onVerticalDragUpdate,
                      onVerticalDragEnd: _onVerticalDragEnd,
                      onVerticalDragCancel: _onVerticalDragCancel,
                      child: _buildPlayer(
                        currentPlayable,
                        context,
                        preferVertical: true,
                        hideQueue: false,
                        hideLyrics: true,
                      ),
                    ),
                  ),
                  Expanded(
                    child: LyricsView(
                      key: const ValueKey('lyrics_view'),
                      filePath: currentTrack.filePath,
                      trackId: currentTrack.id,
                      track: currentTrack,
                      onSeek: playback.seek,
                    ),
                  ),
                ],
              )
            : _buildPlayer(
                currentPlayable,
                context,
                key: ValueKey(
                  _showQueue
                      ? 'narrow_queue'
                      : canShowLyrics
                      ? 'narrow_lyrics'
                      : 'player_only',
                ),
              );

        final Widget responsiveContent = SafeArea(
          child: Column(
            children: [
              // Top App Bar
              appTopBar,
              Expanded(child: mainBody),
            ],
          ),
        );

        final Widget interactiveContent = (!_showQueue && !canShowLyrics)
            ? GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onVerticalDragStart,
                onVerticalDragUpdate: _onVerticalDragUpdate,
                onVerticalDragEnd: _onVerticalDragEnd,
                onVerticalDragCancel: _onVerticalDragCancel,
                child: responsiveContent,
              )
            : responsiveContent;

        final displayMeta = playback.currentDisplayMetadata;
        final Widget scaffold = Scaffold(
          backgroundColor: colorScheme.surface,
          body: Stack(
            children: [
              // 1. Ambient Blurred Backdrop
              Positioned.fill(
                child: AmbientBackdrop(
                  artworkUri:
                      displayMeta?.artworkUri ?? currentPlayable.artworkUri,
                  artworkBytes: displayMeta?.artworkBytes,
                ),
              ),

              // 2. Main Responsive Content Layer
              interactiveContent,
            ],
          ),
        );

        return _wrapWithDragTransform(scaffold);
      },
    );
  }

  Object? _cachedQueueRef;
  int _cachedQueueIndex = -1;
  Duration _cachedPrefixDuration = Duration.zero;
  Duration _cachedTotalPlaylistDuration = Duration.zero;

  void _ensurePlaylistDurationsCached(PlaybackController playback) {
    final queue = playback.queue;
    final idx = playback.currentIndex;
    if (identical(queue, _cachedQueueRef) && idx == _cachedQueueIndex) {
      return;
    }
    if (!identical(queue, _cachedQueueRef)) {
      var total = Duration.zero;
      for (var i = 0; i < queue.length; i++) {
        total += queue[i].track?.duration ?? Duration.zero;
      }
      _cachedTotalPlaylistDuration = total;
      _cachedQueueRef = queue;
    }
    var prefix = Duration.zero;
    final limit = idx.clamp(0, queue.length);
    for (var i = 0; i < limit; i++) {
      prefix += queue[i].track?.duration ?? Duration.zero;
    }
    _cachedPrefixDuration = prefix;
    _cachedQueueIndex = idx;
  }

  Widget _buildPlayer(
    AudioPlayable currentPlayable,
    BuildContext context, {
    bool preferVertical = false,
    bool hideLyrics = false,
    bool hideQueue = false,
    Key? key,
  }) {
    final playback = context.read<PlaybackController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentTrack = currentPlayable is Track ? currentPlayable : null;
    final currentRadio = currentPlayable is RadioStation ? currentPlayable : null;

    final bool isItemLiked;
    final bool isRadioInLibrary;
    if (currentTrack != null) {
      final trackId = currentTrack.id;
      isItemLiked = context.select<PlaylistsController?, bool>(
        (p) => trackId != null && (p?.isTrackLiked(trackId) ?? false),
      );
      isRadioInLibrary = false;
    } else if (currentRadio != null) {
      isItemLiked = context.select<LibraryStore?, bool>(
        (s) {
          final match = s?.radioStations.cast<RadioStation?>().firstWhere(
            (st) =>
                st != null &&
                ((currentRadio.id != null && st.id == currentRadio.id) ||
                    st.streamUrl == currentRadio.streamUrl ||
                    (st.stationUuid != null &&
                        currentRadio.stationUuid != null &&
                        st.stationUuid == currentRadio.stationUuid)),
            orElse: () => null,
          );
          return match?.isFavorite ?? currentRadio.isFavorite;
        },
      );
      isRadioInLibrary = context.select<LibraryStore?, bool>(
        (s) =>
            s?.radioStations.any(
              (st) =>
                  (currentRadio.id != null && st.id == currentRadio.id) ||
                  st.streamUrl == currentRadio.streamUrl ||
                  (st.stationUuid != null &&
                      currentRadio.stationUuid != null &&
                      st.stationUuid == currentRadio.stationUuid),
            ) ??
            false,
      );
    } else {
      isItemLiked = false;
      isRadioInLibrary = false;
    }

    final Widget playerControls = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        spacing: 10.0,
        children: [
          NowPlayingActionsRow(
            playback: playback,
            strings: strings,
            colorScheme: colorScheme,
            isRadio: currentRadio != null,
            isItemLiked: isItemLiked,
            isRadioInLibrary: isRadioInLibrary,
            hasTrack: currentTrack != null,
            onToggleMute: () => _toggleMute(playback),
            onToggleLike: _toggleLike,
            onSecondaryAction: currentRadio != null
                ? () async {
                    final store = context.read<LibraryStore?>();
                    if (store != null) {
                      await store.saveRadioStationInStore(currentRadio);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(strings.rdSavedToLibrary),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    }
                  }
                : (currentTrack != null
                      ? () => TrackActionHelper.showAddToPlaylistDialog(
                          context,
                          currentTrack,
                        )
                      : null),
          ),
          RepaintBoundary(
            child: ListenableBuilder(
              listenable: playback.queueListenable,
              builder: (context, _) {
                return WaveformSlider(
                  positionListenable: playback.positionListenable,
                  positionSecondsListenable: playback.positionSecondsListenable,
                  bufferListenable: playback.bufferListenable,
                  position: playback.position,
                  duration: playback.duration,
                  isBuffering: playback.isBuffering,
                  isLiveStream: playback.isLiveStream,
                  onSeek: playback.seek,
                  waveform: currentTrack?.waveform,
                  currentIndex: playback.currentIndex + 1,
                  totalCount: playback.queue.length,
                  playlistPosition: () {
                    _ensurePlaylistDurationsCached(playback);
                    return _cachedPrefixDuration + playback.position;
                  },
                  playlistDuration: () {
                    _ensurePlaylistDurationsCached(playback);
                    return _cachedTotalPlaylistDuration;
                  },
                );
              },
            ),
          ),
          NowPlayingTransportControls(
            playback: playback,
            strings: strings,
            colorScheme: colorScheme,
            onPrevious: () => _handlePrevious(playback),
          ),
        ],
      ),
    );

    final displayMeta = playback.currentDisplayMetadata;
    final displayTitle = displayMeta?.title ?? currentPlayable.title;
    final displaySubtitle =
        displayMeta?.subtitle ?? currentPlayable.artistNames.join(', ');
    final clickableArtists = displayMeta?.clickableArtists ?? const [];
    final liveBadge = displayMeta?.liveStreamBadge;

    final Widget playerTitle = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            displayTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          if (!currentPlayable.isStream && clickableArtists.isNotEmpty)
            ClickableArtistNames(
              artists: clickableArtists,
              fallbackName: displaySubtitle,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              colorScheme: colorScheme,
            )
          else
            Text(
              displaySubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
            ),
          if (currentPlayable.isStream &&
              liveBadge != null &&
              liveBadge.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              liveBadge,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
            ),
          ],
        ],
      ),
    );

    return LayoutBuilder(
      key: key,
      builder: (context, constraints) {
        final bool canFitVertically = constraints.maxHeight > 400;
        final bool canFitHorizontally = constraints.maxWidth > 590;
        final bool canShowLyrics = !playback.isLiveStream &&
            currentTrack != null &&
            !hideLyrics &&
            _showLyrics &&
            _isUiActive;

        Widget buildVisualContent() {
          if (!hideQueue && _showQueue) {
            return QueueView(key: const ValueKey('queue_view'));
          }
          if (canShowLyrics) {
            return LyricsView(
              key: const ValueKey('lyrics_view'),
              filePath: currentTrack.filePath,
              trackId: currentTrack.id,
              track: currentTrack,
              onSeek: playback.seek,
            );
          }
          return const NowPlayingCoverArt(
            key: ValueKey('cover_art_view'),
          );
        }

        if (canFitHorizontally && !(preferVertical && canFitVertically)) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Flexible(
                fit: FlexFit.loose,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [playerTitle, playerControls],
                ),
              ),
              Flexible(
                fit: FlexFit.loose,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: buildVisualContent(),
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
                  child: buildVisualContent(),
                ),
              ),
              playerTitle,
              playerControls,
              const SizedBox(height: 12),
            ],
          );
        }
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: !hideQueue && _showQueue || canShowLyrics
              ? buildVisualContent()
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

  void _openAudioControls(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = TachyonBreakpoints.isDesktop(context);

    if (isDesktop) {
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: colorScheme.surfaceContainerHigh,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
            child: const AudioEffectsSheet(isDialog: true),
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        useSafeArea: true,
        context: context,
        isScrollControlled: true,
        backgroundColor: colorScheme.surfaceContainerHigh,
        constraints: const BoxConstraints(maxWidth: 540),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => const AudioEffectsSheet(),
      );
    }
  }

  void _showAudioDevicesDialog(BuildContext context) {
    final playback = context.read<PlaybackController>();
    final settings = context.read<SettingsController>();
    final strings = context.read<LocaleController>().localeStrings;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Refresh devices in background if needed
    playback.getAudioDevices();

    final isDesktop = TachyonBreakpoints.isDesktop(context);

    Widget buildDeviceTile({
      required IconData icon,
      required String title,
      required bool isSelected,
      required VoidCallback onTap,
    }) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8.0),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? colorScheme.primaryContainer.withValues(alpha: 0.35)
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: isSelected ? 1.8 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.surfaceContainerHigh,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: isSelected
                          ? FontWeight.bold
                          : FontWeight.w500,
                      color: isSelected
                          ? colorScheme.onSurface
                          : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  isSelected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 20,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.outline.withValues(alpha: 0.6),
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildContent({required bool isSheet}) {
      return Container(
        padding: EdgeInsets.fromLTRB(
          20,
          isSheet ? 12 : 20,
          20,
          isSheet ? 28 : 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isSheet) ...[
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
              const SizedBox(height: 14),
            ],
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.speaker_group_rounded,
                    color: colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    strings.npAudioDevices,
                    overflow: TextOverflow.ellipsis,
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
              child: SingleChildScrollView(
                child: ListenableBuilder(
                  listenable: playback.devicesListenable,
                  builder: (context, _) {
                    final devices = playback.audioDevices;
                    final currentDeviceId = settings.audioOutputDeviceId;

                    if (devices.isEmpty) {
                      return buildDeviceTile(
                        icon: Icons.settings_suggest_rounded,
                        title: strings.npAudioDeviceDefault,
                        isSelected:
                            currentDeviceId == null || currentDeviceId.isEmpty,
                        onTap: () async {
                          await settings.setAudioOutputDeviceId(null);
                          await playback.setAudioDevice(AudioDevice.auto);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      );
                    }

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      children: devices.map((device) {
                        final isSelected = (currentDeviceId != null &&
                                currentDeviceId.isNotEmpty)
                            ? currentDeviceId == device.id
                            : (playback.currentDevice != null
                                ? playback.currentDevice!.id == device.id
                                : device.isAuto);

                        final String title = device.displayName;
                        final devName = device.name.toLowerCase();
                        final IconData icon = devName.contains('bluetooth')
                            ? Icons.bluetooth_audio_rounded
                            : (devName.contains('headphone') ||
                                      devName.contains('headset')
                                  ? Icons.headphones_rounded
                                  : Icons.speaker_rounded);

                        return buildDeviceTile(
                          icon: icon,
                          title: title,
                          isSelected: isSelected,
                          onTap: () async {
                            await settings.setAudioOutputDeviceId(device.id);
                            await playback.setAudioDevice(device);
                            if (context.mounted) Navigator.of(context).pop();
                          },
                        );
                      }).toList(),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isDesktop) {
      showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          backgroundColor: colorScheme.surfaceContainerHigh,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460, maxHeight: 580),
            child: buildContent(isSheet: false),
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: colorScheme.surfaceContainerHigh,
        constraints: const BoxConstraints(maxWidth: 500),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) => buildContent(isSheet: true),
      );
    }
  }
}
