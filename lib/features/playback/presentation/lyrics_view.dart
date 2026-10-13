import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/core/backend/services/lrc_parser.dart';
import 'package:tachyon/features/locales/domain/locale.dart';
import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/domain/lyrics_display_mode.dart';
import 'package:tachyon/features/playback/domain/lyric_line.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';

import 'lyrics_controller.dart';
import 'widgets/lyrics_sources_dialog.dart';
import 'widgets/lyrics_threshold_banner.dart';

/// Synchronized lyrics list view widget.
///
/// Features:
/// - Highlights active line in O(log n) time and auto-centers.
/// - Outer Stack layout ensuring top controls bar and 429 threshold banner
///   remain accessible even when loading or empty.
/// - Frosted glass top controls bar: Source badge, translation mode menu,
///   sources configuration dialog trigger, and manual re-search button.
/// - Multi-mode translation display: Original, Translated, and Interleaved.
/// - Manual scroll lock with 5-second auto-resume and localized sync button.
class LyricsView extends StatefulWidget {
  final String filePath;
  final ValueChanged<Duration>? onSeek;

  const LyricsView({super.key, required this.filePath, this.onSeek});

  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  static const _centerDuration = Duration(milliseconds: 320);
  static const _maxCenterAttempts = 6;

  final ScrollController _scrollController = ScrollController();

  /// Contexts of the currently built lines, keyed by line index.
  final Map<int, BuildContext> _lineContexts = {};

  late final LyricsController _controller;

  // Last observed controller state, used to decide when to re-center.
  ParsedLrc? _lastLyrics;
  int _lastIndex = -1;
  LyricsDisplayMode? _lastMode;
  List<String>? _lastTranslated;
  bool _lastLocked = false;

  bool _centerScheduled = false;
  bool _centerAnimated = true;

  @override
  void initState() {
    super.initState();
    _controller = context.read<LyricsController>();
    _controller.addListener(_onControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.onLyricsViewMounted();
      _rememberState();
      _scheduleCenter(animated: false);
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _rememberState() {
    _lastLyrics = _controller.lyrics;
    _lastIndex = _controller.currentIndex;
    _lastMode = _controller.displayMode;
    _lastTranslated = _controller.translatedLines;
    _lastLocked = _controller.isUserScrollLocked;
  }

  void _onControllerChanged() {
    final c = _controller;
    final lyricsChanged = !identical(c.lyrics, _lastLyrics);
    final needsCenter =
        c.currentIndex != _lastIndex ||
        c.displayMode != _lastMode ||
        !identical(c.translatedLines, _lastTranslated) ||
        (_lastLocked && !c.isUserScrollLocked);
    _rememberState();
    if (lyricsChanged) {
      _scheduleCenter(animated: false);
    } else if (needsCenter) {
      _scheduleCenter(animated: true);
    }
  }

  /// Centers the active line after the pending rebuild has been laid out.
  void _scheduleCenter({required bool animated}) {
    _centerAnimated = _centerScheduled ? (_centerAnimated && animated) : animated;
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
    final c = _controller;
    final position = _scrollController.position;
    if (!c.hasLyrics) return;
    if (!c.isSynced) {
      if (!animated) position.jumpTo(position.minScrollExtent);
      return;
    }
    if (c.isUserScrollLocked) return;

    final index = c.currentIndex;
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
    final lyricsController = context.watch<LyricsController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;

    Widget body;
    if (lyricsController.isLoading) {
      body = const Center(child: CircularProgressIndicator.adaptive());
    } else if (!lyricsController.hasLyrics) {
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
      body = _buildLyricsList(context, lyricsController, strings, colorScheme);
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
                _buildTopControlsBar(
                  context,
                  lyricsController,
                  strings,
                  colorScheme,
                ),
                if (lyricsController.isThresholdWaiting)
                  const LyricsThresholdBanner(),
                if (lyricsController.isTranslated &&
                    lyricsController.translationError != null)
                  _buildTranslationErrorBanner(
                    context,
                    lyricsController,
                    strings,
                    colorScheme,
                  ),
              ],
            ),
          ),
        ),

        // 3. Floating "Sync" Pill displayed when user has manually scrolled synced lyrics
        if (lyricsController.isSynced && lyricsController.isUserScrollLocked)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.small(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              tooltip: strings.npLyricsResumeSync,
              onPressed: () => lyricsController.resumeAutoScroll(),
              child: const Icon(Icons.sync_rounded, size: 20),
            ),
          ),
      ],
    );
  }

  Widget _buildLyricsList(
    BuildContext context,
    LyricsController lyricsController,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    final lines = lyricsController.lines;
    final activeIndex = lyricsController.currentIndex;
    final isSynced = lyricsController.isSynced;
    final isTranslated = lyricsController.isTranslated;
    final isInterleaved = lyricsController.isInterleaved;
    final translatedLines = lyricsController.translatedLines;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          lyricsController.onUserScroll();
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
                lyricsController: lyricsController,
                onSeek: widget.onSeek,
                onMounted: _registerLine,
                onUnmounted: _unregisterLine,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTopControlsBar(
    BuildContext context,
    LyricsController lyricsController,
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
                _buildSourceBadge(lyricsController, strings, colorScheme),
                const Spacer(),
                _buildTranslationButton(
                  context,
                  lyricsController,
                  strings,
                  colorScheme,
                ),
                const SizedBox(width: 4),
                _buildSourcesButton(context, strings, colorScheme),
                const SizedBox(width: 4),
                _buildResearchButton(lyricsController, strings, colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceBadge(
    LyricsController controller,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    if (!controller.hasLyrics) {
      return const SizedBox.shrink();
    }

    final (serverName, fullTooltip) = switch (controller.currentLyricsSource) {
      LyricsSource.embedded => ('Tags', strings.npLyricsSourceEmbedded),
      LyricsSource.file => ('.lrc', strings.npLyricsSourceFile),
      LyricsSource.lrclib => ('lrclib.net', strings.npLyricsSourceLrclib),
      LyricsSource.lyricsOvh => ('lyrics.ovh', strings.npLyricsSourceOvh),
      null => ('', strings.npLyricsSourceNone),
    };

    final isSynced = controller.isSynced;

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
    LyricsController controller,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    if (controller.isTranslating) {
      return Padding(
        padding: const EdgeInsets.all(0),
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

    final isTranslated = controller.isTranslated;
    final isInterleaved = controller.isInterleaved;

    final tooltip = isTranslated
        ? (isInterleaved
              ? strings.npLyricsInterleaved
              : strings.npLyricsTranslated)
        : strings.npLyricsTranslate;

    return PopupMenuButton<LyricsDisplayMode>(
      tooltip: tooltip,
      // make the button smaller and more compact
      splashRadius: 20,
      // make the icon smaller
      style: ButtonStyle(
        padding: WidgetStateProperty.all<EdgeInsets>(EdgeInsets.all(6.0)),
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
      onSelected: (mode) => controller.setTranslationDisplayMode(mode),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: LyricsDisplayMode.original,
          child: Row(
            children: [
              Icon(
                Icons.notes_rounded,
                size: 18,
                color: controller.displayMode == LyricsDisplayMode.original
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
                color: controller.displayMode == LyricsDisplayMode.translated
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
                color: controller.displayMode == LyricsDisplayMode.interleaved
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
      onPressed: () => LyricsSourcesDialog.show(context),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildResearchButton(
    LyricsController controller,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    return IconButton(
      icon: const Icon(Icons.refresh_rounded, size: 20),
      tooltip: strings.npLyricsResearch,
      color: colorScheme.onSurfaceVariant,
      onPressed: controller.isLoading ? null : () => controller.forceReSearch(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildTranslationErrorBanner(
    BuildContext context,
    LyricsController controller,
    AppStringKey strings,
    ColorScheme colorScheme,
  ) {
    final isRateLimit = controller.translationError == 'rate_limit';
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
  final LyricsController lyricsController;
  final ValueChanged<Duration>? onSeek;
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
    required this.lyricsController,
    required this.onMounted,
    required this.onUnmounted,
    this.onSeek,
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
      onTap: () {
        widget.lyricsController.seekToLine(widget.index);
        if (widget.onSeek != null && widget.line.isSynced) {
          widget.onSeek!(widget.line.timestamp);
        }
      },
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
