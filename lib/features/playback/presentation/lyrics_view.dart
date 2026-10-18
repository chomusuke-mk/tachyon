import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/lyrics/domain/lyric_line.dart';
import 'package:tachyon/core/lyrics/domain/lyric_source.dart';
import 'package:tachyon/core/lyrics/domain/lyrics_display_mode.dart';
import 'package:tachyon/core/lyrics/lrc_parser.dart';
import 'package:tachyon/core/lyrics/lyrics_manager.dart';
import 'package:tachyon/core/lyrics/lyrics_translation_client.dart';
import 'package:tachyon/core/playback/playback_controller.dart';
import 'package:tachyon/core/store/domain/track.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart';
import 'package:tachyon/features/settings/presentation/settings_controller.dart';

import 'widgets/lyrics_sources_dialog.dart';
import 'widgets/lyrics_threshold_banner.dart';

/// Synchronized lyrics list view widget.
///
/// Owns all visual lyrics state (active line index, auto-scroll lock,
/// display mode, translation state, and source toggles) while requesting
/// lyrics on-demand from [LyricsManager].
class LyricsView extends StatefulWidget {
  final String filePath;
  final int? trackId;
  final Track? track;
  final ValueChanged<Duration>? onSeek;

  const LyricsView({
    super.key,
    required this.filePath,
    this.trackId,
    this.track,
    this.onSeek,
  });

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const _centerDuration = Duration(milliseconds: 320);
  static const _maxCenterAttempts = 6;

  final ScrollController _scrollController = ScrollController();

  /// Contexts of the currently built lines, keyed by line index.
  final Map<int, BuildContext> _lineContexts = {};

  late final LyricsManager _lyricsManager;
  PlaybackController? _playback;
  SettingsRepository? _settingsRepository;
  LocaleController? _localeController;
  SettingsController? _settingsController;
  StreamSubscription<int?>? _thresholdSub;

  int? _lastObservedTrackId;
  String? _lastObservedTrackPath;
  String? _lastTargetLang;

  // Visual state owned by LyricsView
  ParsedLrc? _lyrics;
  LyricsSource? _currentLyricsSource;
  int? _currentLyricsId;
  String? _currentLyricsLang;
  bool _isLoading = false;
  int _currentIndex = 0;
  bool _isUserScrollLocked = false;

  bool _enableLocalSources = true;
  bool _enableLrclib = true;
  bool _enableLyricsOvh = true;

  LyricsDisplayMode _displayMode = LyricsDisplayMode.original;
  bool _isTranslating = false;
  List<String> _translatedLines = const [];
  String? _translationError;

  bool _centerScheduled = false;
  bool _centerAnimated = true;
  int _viewRequestGen = 0;

  bool get _hasLyrics => _lyrics != null && _lyrics!.isNotEmpty;
  bool get _isSynced => _lyrics?.isSynced ?? false;
  List<LyricLine> get _lines => _lyrics?.lines ?? const [];
  bool get _isTranslated => _displayMode != LyricsDisplayMode.original;
  bool get _isInterleaved => _displayMode == LyricsDisplayMode.interleaved;

  @override
  void initState() {
    super.initState();
    _lyricsManager = context.read<LyricsManager>();

    try {
      _playback = context.read<PlaybackController>();
    } catch (_) {
      _playback = null;
    }

    try {
      _settingsRepository = context.read<SettingsRepository>();
      _displayMode = _settingsRepository!.getLyricsDisplayMode();
      _lastTargetLang = _settingsRepository!.getLyricsTranslationTargetLang();
    } catch (_) {
      _settingsRepository = null;
    }

    try {
      _localeController = context.read<LocaleController>();
      _localeController!.addListener(_onLocaleOrSettingsChanged);
    } catch (_) {
      _localeController = null;
    }

    try {
      _settingsController = context.read<SettingsController>();
      _settingsController!.addListener(_onLocaleOrSettingsChanged);
    } catch (_) {
      _settingsController = null;
    }

    _thresholdSub = _lyricsManager.thresholdStream.listen((_) {
      if (mounted) setState(() {});
    });

    final playback = _playback;
    if (playback != null) {
      _lastObservedTrackId = playback.currentTrack?.id;
      _lastObservedTrackPath = playback.currentTrack?.filePath;
      playback.addListener(_onPlaybackChanged);
      playback.positionListenable.addListener(_onPositionChanged);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadLyricsForCurrentTrack(immediate: true);
    });
  }

  @override
  void didUpdateWidget(covariant LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath != widget.filePath ||
        oldWidget.trackId != widget.trackId ||
        oldWidget.track?.id != widget.track?.id) {
      _loadLyricsForCurrentTrack(immediate: false);
    }
  }

  void _onPlaybackChanged() {
    final playback = _playback;
    if (playback == null || !mounted) return;
    final currentTrack = playback.currentTrack;
    final currentId = currentTrack?.id;
    final currentPath = currentTrack?.filePath;
    if (currentId != _lastObservedTrackId ||
        currentPath != _lastObservedTrackPath) {
      _lastObservedTrackId = currentId;
      _lastObservedTrackPath = currentPath;
      _loadLyricsForCurrentTrack(immediate: false);
    }
  }

  void _onPositionChanged() {
    final playback = _playback;
    if (playback == null || !mounted || !_isSynced) return;
    final newIndex = _lyrics!.activeIndexAt(playback.position);
    if (newIndex != _currentIndex) {
      setState(() {
        _currentIndex = newIndex;
      });
      _scheduleCenter(animated: true);
    }
  }

  void _onLocaleOrSettingsChanged() {
    if (!mounted || !_isTranslated || !_hasLyrics) return;
    final savedTarget =
        _settingsRepository?.getLyricsTranslationTargetLang() ??
        'defaultOption';
    if (savedTarget != _lastTargetLang || savedTarget == 'defaultOption') {
      _lastTargetLang = savedTarget;
      _translateCurrentLyrics(forceRefresh: true);
    }
  }

  Track? _resolveCurrentTrack() {
    if (widget.track != null) return widget.track;
    final pbTrack = _playback?.currentTrack;
    if (pbTrack != null) return pbTrack;
    if (widget.trackId != null) {
      final byId = _lyricsManager.store.getTrackById(widget.trackId!);
      if (byId != null) return byId;
    }
    if (widget.filePath.isNotEmpty) {
      return _lyricsManager.store.getTrackByPath(widget.filePath);
    }
    return null;
  }

  Future<void> _loadLyricsForCurrentTrack({
    bool forceRefresh = false,
    bool immediate = false,
  }) async {
    final track = _resolveCurrentTrack();
    final trackId = widget.trackId ?? track?.id;
    final filePath = track?.filePath ?? widget.filePath;
    final gen = ++_viewRequestGen;

    setState(() {
      _isLoading = true;
      _isUserScrollLocked = false;
      _lyrics = null;
      _currentLyricsSource = null;
      _currentLyricsId = null;
      _currentIndex = 0;
      _translatedLines = const [];
      _translationError = null;
      _isTranslating = false;
    });

    try {
      final LyricsResult result;
      if (trackId != null) {
        result = await _lyricsManager.getLyrics(
          trackId,
          track: track,
          enableLocal: _enableLocalSources,
          enableLrclib: _enableLrclib,
          enableLyricsOvh: _enableLyricsOvh,
          forceRefresh: forceRefresh,
          debounceOverride: (immediate || forceRefresh) ? Duration.zero : null,
          onThresholdRetryResolved: (retryRes) {
            if (!mounted || gen != _viewRequestGen || retryRes.isCancelled) {
              return;
            }
            _applyLyricsResult(retryRes, gen);
          },
        );
      } else {
        result = await _lyricsManager.getLyricsForTrack(
          trackId: null,
          filePath: filePath,
          title: track?.title ?? '',
          artist: track != null
              ? track.artists.map((a) => a.name).join(', ')
              : '',
          album: track?.album?.name,
          durationSeconds: track != null && track.durationMs > 0
              ? (track.durationMs / 1000).round()
              : null,
          enableLocal: _enableLocalSources,
          enableLrclib: _enableLrclib,
          enableLyricsOvh: _enableLyricsOvh,
          forceRefresh: forceRefresh,
        );
      }

      if (!mounted || gen != _viewRequestGen || result.isCancelled) return;
      _applyLyricsResult(result, gen);
    } catch (_) {
      if (!mounted || gen != _viewRequestGen) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _applyLyricsResult(LyricsResult result, int gen) {
    if (!mounted || gen != _viewRequestGen) return;
    if (result.isThresholdWaiting) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final pos = _playback?.position ?? Duration.zero;
    final initialIndex = result.lrc.isSynced
        ? result.lrc.activeIndexAt(pos)
        : 0;

    setState(() {
      _lyrics = result.lrc;
      _currentLyricsSource = result.source;
      _currentLyricsId = result.lyricsId;
      _currentIndex = initialIndex;
      _isLoading = false;
    });

    _scheduleCenter(animated: false);

    if (_isTranslated && _hasLyrics) {
      unawaited(_translateCurrentLyrics());
    }
  }

  String _resolveEffectiveTargetLang() {
    final saved =
        _settingsRepository?.getLyricsTranslationTargetLang() ??
        'defaultOption';
    if (saved == 'defaultOption' || saved.trim().isEmpty) {
      final locale = _localeController?.currentLocaleCode ?? 'en';
      return locale.trim().isEmpty ? 'en' : locale.trim().toLowerCase();
    }
    return saved.trim().toLowerCase();
  }

  String _resolveEffectiveSourceLang() {
    final saved =
        _settingsRepository?.getLyricsTranslationSourceLang() ?? 'autodetect';
    return saved.trim().isEmpty ? 'autodetect' : saved.trim().toLowerCase();
  }

  Future<void> _translateCurrentLyrics({
    String? sourceLanguage,
    String? targetLanguage,
    bool forceRefresh = false,
  }) async {
    if (!_hasLyrics || !mounted) return;
    final targetLang = (targetLanguage ?? _resolveEffectiveTargetLang())
        .trim()
        .toLowerCase();
    final sourceLang = (sourceLanguage ?? _resolveEffectiveSourceLang())
        .trim()
        .toLowerCase();
    final langKey = sourceLang == 'autodetect'
        ? targetLang
        : '$sourceLang->$targetLang';

    if (!forceRefresh &&
        _translatedLines.length == _lines.length &&
        _currentLyricsLang == langKey &&
        _translationError == null) {
      return;
    }

    final gen = _viewRequestGen;
    setState(() {
      _isTranslating = true;
      _translationError = null;
    });

    try {
      final rawLines = _lines.map((l) => l.text).toList(growable: false);
      final translated = await _lyricsManager.translateLyrics(
        lyricsId: _currentLyricsId,
        lines: rawLines,
        targetLanguage: targetLang,
        sourceLanguage: sourceLang,
        forceRefresh: forceRefresh,
      );
      if (!mounted || gen != _viewRequestGen) return;
      if (translated.isNotEmpty) {
        setState(() {
          _translatedLines = translated;
          _currentLyricsLang = langKey;
          _isTranslating = false;
          _translationError = null;
        });
        _scheduleCenter(animated: true);
      } else {
        setState(() {
          _isTranslating = false;
        });
      }
    } on LyricsTranslationException catch (e) {
      if (!mounted || gen != _viewRequestGen) return;
      setState(() {
        _isTranslating = false;
        _translationError = e.isRateLimited ? 'rate_limit' : 'error';
      });
    } catch (_) {
      if (!mounted || gen != _viewRequestGen) return;
      setState(() {
        _isTranslating = false;
        _translationError = 'error';
      });
    }
  }

  Future<void> _setTranslationDisplayMode(LyricsDisplayMode mode) async {
    if (_displayMode == mode && _translationError == null) return;
    setState(() {
      _displayMode = mode;
    });
    await _settingsRepository?.setLyricsDisplayMode(mode);

    if (mode == LyricsDisplayMode.original) {
      setState(() {
        _translationError = null;
        _isTranslating = false;
      });
      _scheduleCenter(animated: true);
      return;
    }

    await _translateCurrentLyrics(
      forceRefresh: _translationError != null,
    );
  }

  void _setSourcesConfig({bool? local, bool? lrclib, bool? lyricsOvh}) {
    final nextLocal = local ?? _enableLocalSources;
    final nextLrclib = lrclib ?? _enableLrclib;
    final nextOvh = lyricsOvh ?? _enableLyricsOvh;
    if (!nextLocal && !nextLrclib && !nextOvh) return;
    setState(() {
      _enableLocalSources = nextLocal;
      _enableLrclib = nextLrclib;
      _enableLyricsOvh = nextOvh;
    });
  }

  void _onUserScroll() {
    if (!_isSynced || _isUserScrollLocked) return;
    setState(() {
      _isUserScrollLocked = true;
    });
  }

  void _resumeAutoScroll() {
    if (!_isUserScrollLocked) return;
    setState(() {
      _isUserScrollLocked = false;
    });
    _scheduleCenter(animated: true);
  }

  void _seekToLine(int index) {
    if (index < 0 || index >= _lines.length) return;
    final line = _lines[index];
    setState(() {
      _currentIndex = index;
      _isUserScrollLocked = false;
    });
    _scheduleCenter(animated: true);
    if (line.isSynced) {
      if (widget.onSeek != null) {
        widget.onSeek!(line.timestamp);
      } else {
        _playback?.seek(line.timestamp);
      }
    }
  }

  @override
  void dispose() {
    _viewRequestGen++;
    _thresholdSub?.cancel();
    _playback?.removeListener(_onPlaybackChanged);
    _playback?.positionListenable.removeListener(_onPositionChanged);
    _localeController?.removeListener(_onLocaleOrSettingsChanged);
    _settingsController?.removeListener(_onLocaleOrSettingsChanged);
    _lyricsManager.cancelPending();
    _scrollController.dispose();
    super.dispose();
  }

  /// Centers the active line after the pending rebuild has been laid out.
  void _scheduleCenter({required bool animated}) {
    _centerAnimated =
        _centerScheduled ? (_centerAnimated && animated) : animated;
    if (_centerScheduled) return;
    _centerScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerScheduled = false;
      _centerActiveLine(animated: _centerAnimated);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _centerActiveLine({required bool animated, int attempt = 0}) {
    if (!mounted || !_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (!_hasLyrics) return;
    if (!_isSynced) {
      if (!animated) position.jumpTo(position.minScrollExtent);
      return;
    }
    if (_isUserScrollLocked) return;

    final index = _currentIndex;
    final target = _lineContexts[index]?.findRenderObject();
    if (target != null && target.attached) {
      position.ensureVisible(
        target,
        alignment: 0.5,
        duration: animated ? _centerDuration : Duration.zero,
        curve: Curves.easeOutCubic,
      );
      return;
    }

    // The active line is not built (far away): jump close to it using the
    // measured height of the built lines, then retry once it is laid out.
    if (attempt >= _maxCenterAttempts) return;
    final estimate = _estimateOffsetFor(index);
    if (estimate == null) return;
    position.jumpTo(
      estimate.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerActiveLine(animated: animated, attempt: attempt + 1),
    );
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  double? _estimateOffsetFor(int index) {
    int? refIndex;
    RenderBox? refBox;
    double totalHeight = 0;
    int count = 0;
    for (final entry in _lineContexts.entries) {
      final box = entry.value.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) continue;
      totalHeight += box.size.height;
      count++;
      if (refIndex == null ||
          (entry.key - index).abs() < (refIndex - index).abs()) {
        refIndex = entry.key;
        refBox = box;
      }
    }
    if (refBox == null || refIndex == null) return null;
    final viewport = RenderAbstractViewport.maybeOf(refBox);
    if (viewport == null) return null;
    final refOffset = viewport.getOffsetToReveal(refBox, 0.5).offset;
    return refOffset + (index - refIndex) * (totalHeight / count);
  }

  void _registerLine(int index, BuildContext lineContext) {
    _lineContexts[index] = lineContext;
  }

  void _unregisterLine(int index, BuildContext lineContext) {
    if (identical(_lineContexts[index], lineContext)) {
      _lineContexts.remove(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;

    Widget body;
    if (_isLoading) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (!_hasLyrics) {
      body = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lyrics_outlined,
              size: 64,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            Text(
              strings.npLyricsEmpty,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    } else {
      body = _buildLyricsList(context, strings, colorScheme);
    }

    return Stack(
      children: [
        // 1. Main Content Area (Loading, Empty, or Lyrics List)
        Positioned.fill(child: body),

        // 2. Floating Pinned Top Controls Bar & Threshold Banner
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildTopControlsBar(context, strings, colorScheme),
                if (_lyricsManager.isThresholdWaiting)
                  const LyricsThresholdBanner(),
                if (_isTranslated && _translationError != null)
                  _buildTranslationErrorBanner(context, strings, colorScheme),
              ],
            ),
          ),
        ),

        // 3. Floating "Sync" Pill displayed when user has manually scrolled synced lyrics
        if (_isSynced && _isUserScrollLocked)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              tooltip: strings.npLyricsResumeSync,
              onPressed: _resumeAutoScroll,
              child: const Icon(Icons.sync_rounded, size: 20),
            ),
          ),
      ],
    );
  }

  Widget _buildLyricsList(
    BuildContext context,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    final lines = _lines;
    final activeIndex = _currentIndex;
    final isSynced = _isSynced;
    final isTranslated = _isTranslated;
    final isInterleaved = _isInterleaved;
    final translatedLines = _translatedLines;

    return RepaintBoundary(
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification is UserScrollNotification) {
            _onUserScroll();
          }
          return false;
        },
        child: LayoutBuilder(
          builder: (context, constraints) {
            final halfHeight = constraints.maxHeight > 0
                ? constraints.maxHeight / 2
                : 160.0;

            return ListView.builder(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.only(
                left: 24.0,
                right: 24.0,
                top: isSynced ? (halfHeight - 28.0) : 100.0,
                bottom: isSynced ? (halfHeight - 28.0) : 100.0,
              ),
              itemCount: lines.length,
              itemBuilder: (context, index) {
                final line = lines[index];
                final isActive = isSynced && (index == activeIndex);
                final translatedText =
                    (index >= 0 && index < translatedLines.length)
                    ? translatedLines[index]
                    : null;
                final hasTranslation =
                    translatedText != null && translatedText.trim().isNotEmpty;

                return _LyricLineItem(
                  key: ValueKey('line_${line.timestamp.inMilliseconds}_$index'),
                  line: line,
                  index: index,
                  isActive: isActive,
                  isSynced: isSynced,
                  hasTranslation: hasTranslation,
                  translatedText: translatedText,
                  isTranslated: isTranslated,
                  isInterleaved: isInterleaved,
                  colorScheme: colorScheme,
                  onTapLine: _seekToLine,
                  onMounted: _registerLine,
                  onUnmounted: _unregisterLine,
                );
              },
            );
          },
        ),
      ),
    );
  }

  Widget _buildTopControlsBar(
    BuildContext context,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.0),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 2.0, sigmaY: 2.0),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 10.0,
              vertical: 2.0,
            ),
            decoration: BoxDecoration(
              color: const Color.fromARGB(10, 0, 0, 0),
              borderRadius: BorderRadius.circular(16.0),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                width: 0.8,
              ),
            ),
            child: Row(
              children: [
                _buildSourceBadge(strings, colorScheme),
                const Spacer(),
                _buildTranslationButton(context, strings, colorScheme),
                const SizedBox(width: 4),
                _buildSourcesButton(context, strings, colorScheme),
                const SizedBox(width: 4),
                _buildResearchButton(strings, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    if (!_hasLyrics) {
      return const SizedBox.shrink();
    }

    final (serverName, fullTooltip) = switch (_currentLyricsSource) {
      LyricsSource.embedded => ('Tags', strings.npLyricsSourceEmbedded),
      LyricsSource.file => ('.lrc', strings.npLyricsSourceFile),
      LyricsSource.lrclib => ('lrclib.net', strings.npLyricsSourceLrclib),
      LyricsSource.lyricsOvh => ('lyrics.ovh', strings.npLyricsSourceOvh),
      null => ('', strings.npLyricsSourceNone),
    };

    final isSynced = _isSynced;

    return Tooltip(
      message: fullTooltip,
      waitDuration: const Duration(milliseconds: 250),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        decoration: BoxDecoration(
          color: colorScheme.surface.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(10.0),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(width: 6),
            Text(
              serverName,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              isSynced ? Icons.timer_outlined : Icons.notes_rounded,
              size: 13,
              color: isSynced
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTranslationButton(
    BuildContext context,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    if (_isTranslating) {
      return RepaintBoundary(
        child: SizedBox(
          width: 15,
          height: 15,
          child: CircularProgressIndicator(
            strokeWidth: 1.9,
            color: colorScheme.primary,
          ),
        ),
      );
    }

    final isTranslated = _isTranslated;
    final isInterleaved = _isInterleaved;

    final tooltip = isTranslated
        ? (isInterleaved
              ? strings.npLyricsInterleaved
              : strings.npLyricsTranslated)
        : strings.npLyricsTranslate;

    return PopupMenuButton<LyricsDisplayMode>(
      tooltip: tooltip,
      splashRadius: 20,
      style: ButtonStyle(
        padding: WidgetStateProperty.all<EdgeInsets>(const EdgeInsets.all(6.0)),
        minimumSize: WidgetStateProperty.all<Size>(Size.zero),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: Icon(
        Icons.translate_rounded,
        size: 20,
        color: isTranslated
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
      onSelected: _setTranslationDisplayMode,
      itemBuilder: (context) => [
        PopupMenuItem(
          value: LyricsDisplayMode.original,
          child: Row(
            children: [
              Icon(
                Icons.notes_rounded,
                size: 18,
                color: _displayMode == LyricsDisplayMode.original
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(strings.npLyricsOriginal),
            ],
          ),
        ),
        PopupMenuItem(
          value: LyricsDisplayMode.translated,
          child: Row(
            children: [
              Icon(
                Icons.translate_rounded,
                size: 18,
                color: _displayMode == LyricsDisplayMode.translated
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(strings.npLyricsTranslated),
            ],
          ),
        ),
        PopupMenuItem(
          value: LyricsDisplayMode.interleaved,
          child: Row(
            children: [
              Icon(
                Icons.horizontal_split_rounded,
                size: 18,
                color: _displayMode == LyricsDisplayMode.interleaved
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Text(strings.npLyricsInterleaved),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSourcesButton(
    BuildContext context,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    return IconButton(
      icon: const Icon(Icons.tune_rounded, size: 20),
      tooltip: strings.npLyricsSources,
      color: colorScheme.onSurfaceVariant,
      onPressed: () => LyricsSourcesDialog.show(
        context,
        initialEnableLocal: _enableLocalSources,
        initialEnableLrclib: _enableLrclib,
        initialEnableLyricsOvh: _enableLyricsOvh,
        hasLyrics: _hasLyrics,
        isTranslated: _isTranslated,
        onSourcesChanged: _setSourcesConfig,
        onForceReSearch: () => _loadLyricsForCurrentTrack(
          forceRefresh: true,
          immediate: true,
        ),
        onRetranslate: ({sourceLanguage, required targetLanguage}) =>
            _translateCurrentLyrics(
              sourceLanguage: sourceLanguage,
              targetLanguage: targetLanguage,
              forceRefresh: true,
            ),
      ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildResearchButton(
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    return IconButton(
      icon: const Icon(Icons.refresh_rounded, size: 20),
      tooltip: strings.npLyricsResearch,
      color: colorScheme.onSurfaceVariant,
      onPressed: _isLoading
          ? null
          : () => _loadLyricsForCurrentTrack(
              forceRefresh: true,
              immediate: true,
            ),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildTranslationErrorBanner(
    BuildContext context,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    final isRateLimit = _translationError == 'rate_limit';
    final message = isRateLimit
        ? strings.npLyricsRateLimitError
        : strings.npLyricsTranslateError;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(
            isRateLimit ? Icons.timer_outlined : Icons.error_outline_rounded,
            size: 16,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onErrorContainer,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricLineItem extends StatefulWidget {
  final LyricLine line;
  final int index;
  final bool isActive;
  final bool isSynced;
  final bool hasTranslation;
  final String? translatedText;
  final bool isTranslated;
  final bool isInterleaved;
  final ColorScheme colorScheme;
  final ValueChanged<int> onTapLine;
  final void Function(int index, BuildContext context) onMounted;
  final void Function(int index, BuildContext context) onUnmounted;

  const _LyricLineItem({
    super.key,
    required this.line,
    required this.index,
    required this.isActive,
    required this.isSynced,
    required this.hasTranslation,
    required this.translatedText,
    required this.isTranslated,
    required this.isInterleaved,
    required this.colorScheme,
    required this.onTapLine,
    required this.onMounted,
    required this.onUnmounted,
  });

  @override
  State<_LyricLineItem> createState() => _LyricLineItemState();
}

class _LyricLineItemState extends State<_LyricLineItem> {
  @override
  void initState() {
    super.initState();
    widget.onMounted(widget.index, context);
  }

  @override
  void didUpdateWidget(covariant _LyricLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      oldWidget.onUnmounted(oldWidget.index, context);
      widget.onMounted(widget.index, context);
    }
  }

  @override
  void dispose() {
    widget.onUnmounted(widget.index, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => widget.onTapLine(widget.index),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 8.0),
        child: _buildContent(),
      ),
    );
  }

  Widget _buildContent() {
    final colorScheme = widget.colorScheme;
    final isActive = widget.isActive;
    final isSynced = widget.isSynced;
    final isTranslated = widget.isTranslated;
    final isInterleaved = widget.isInterleaved;
    final hasTranslation = widget.hasTranslation;
    final originalText = widget.line.text;
    final translatedText = widget.translatedText;

    // Plain text unsynced mode: uniform, clean presentation without highlighting or opacity fading
    if (!isSynced) {
      if (isTranslated && isInterleaved) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              originalText,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w400,
                color: colorScheme.onSurface,
                height: 1.4,
              ),
            ),
            if (hasTranslation) ...[
              const SizedBox(height: 4.0),
              Text(
                translatedText!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                  fontStyle: FontStyle.italic,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ],
        );
      }

      final textToDisplay = (isTranslated && hasTranslation)
          ? translatedText!
          : originalText;
      return Text(
        textToDisplay,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: colorScheme.onSurface,
          height: 1.4,
        ),
      );
    }

    // Synchronized mode with active line highlight
    if (isTranslated && isInterleaved) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            originalText,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: isActive ? 22 : 16,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
              color: isActive
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
              height: 1.3,
            ),
          ),
          if (hasTranslation) ...[
            const SizedBox(height: 4.0),
            Text(
              translatedText!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isActive ? 16 : 13,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.w300,
                fontStyle: FontStyle.italic,
                color: isActive
                    ? colorScheme.secondary
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                height: 1.3,
              ),
            ),
          ],
        ],
      );
    }

    if (isTranslated && hasTranslation) {
      return Text(
        translatedText!,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: isActive ? 22 : 16,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
          color: isActive
              ? colorScheme.primary
              : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          height: 1.4,
        ),
      );
    }

    return Text(
      originalText,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: isActive ? 22 : 16,
        fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
        color: isActive
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
        height: 1.4,
      ),
    );
  }
}
