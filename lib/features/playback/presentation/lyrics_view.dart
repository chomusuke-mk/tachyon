import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
class LyricsView extends StatelessWidget {
  final String? filePath;
  final ValueChanged<Duration>? onSeek;

  const LyricsView({
    super.key,
    String? filePath,
    @Deprecated('Use filePath') String? uri,
    this.onSeek,
  }) : filePath = filePath ?? uri;

  @Deprecated('Use filePath')
  String? get uri => filePath;

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
                _buildTopControlsBar(context, lyricsController, strings, colorScheme),
                if (lyricsController.isThresholdWaiting)
                  const LyricsThresholdBanner(),
              ],
            ),
          ),
        ),

        // 3. Floating "Sync" Pill displayed when user has manually scrolled
        if (lyricsController.isUserScrollLocked)
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton.extended(
              backgroundColor: colorScheme.primaryContainer,
              foregroundColor: colorScheme.onPrimaryContainer,
              icon: const Icon(Icons.sync_rounded, size: 20),
              label: Text(strings.npLyricsResumeSync),
              onPressed: () => lyricsController.resumeAutoScroll(),
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
            controller: lyricsController.scrollController,
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
                onSeek: onSeek,
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
          filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.65),
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
                _buildTranslationButton(context, lyricsController, strings, colorScheme),
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

    final (badgeLabel, serverName, fullTooltip) =
        switch (controller.currentLyricsSource) {
      LyricsSource.embedded => (
        'E',
        'Tags',
        strings.npLyricsSourceEmbedded,
      ),
      LyricsSource.file => (
        'L',
        '.lrc',
        strings.npLyricsSourceFile,
      ),
      LyricsSource.lrclib => (
        '1',
        'lrclib.net',
        strings.npLyricsSourceLrclib,
      ),
      LyricsSource.lyricsOvh => (
        '2',
        'lyrics.ovh',
        strings.npLyricsSourceOvh,
      ),
      null => ('-', '', strings.npLyricsSourceNone),
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
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 5.0,
                vertical: 1.5,
              ),
              decoration: BoxDecoration(
                color: isSynced
                    ? colorScheme.primaryContainer
                    : colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(4.0),
              ),
              child: Text(
                badgeLabel,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSynced
                      ? colorScheme.onPrimaryContainer
                      : colorScheme.onSecondaryContainer,
                ),
              ),
            ),
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
        padding: const EdgeInsets.all(8.0),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2.0,
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
      icon: Icon(
        Icons.translate_rounded,
        size: 20,
        color: isTranslated ? colorScheme.primary : colorScheme.onSurfaceVariant,
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
    this.onSeek,
  });

  @override
  State<_LyricLineItem> createState() => _LyricLineItemState();
}

class _LyricLineItemState extends State<_LyricLineItem> {
  @override
  void didUpdateWidget(covariant _LyricLineItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive && widget.isSynced) {
      if (!widget.lyricsController.isUserScrollLocked) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Scrollable.ensureVisible(
              context,
              alignment: 0.5,
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeOutCubic,
            );
          }
        });
      }
    }
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
        padding: const EdgeInsets.symmetric(
          vertical: 10.0,
          horizontal: 8.0,
        ),
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

      final textToDisplay =
          (isTranslated && hasTranslation) ? translatedText! : originalText;
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

