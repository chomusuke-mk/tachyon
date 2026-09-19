import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/features/locales/presentation/locale_controller.dart';

import 'lyrics_controller.dart';

/// Synchronized lyrics list view widget.
///
/// Highlights the current active line in O(log n) time, centers the active
/// line automatically, supports tap-to-seek, and handles user manual scroll lock
/// with a 5-second automatic resume timer and manual sync action button.
class LyricsView extends StatelessWidget {
  final String? uri;
  final ValueChanged<Duration>? onSeek;

  const LyricsView({super.key, this.uri, this.onSeek});

  @override
  Widget build(BuildContext context) {
    final lyricsController = context.watch<LyricsController>();
    final strings = context.watch<LocaleController>().localeStrings;
    final colorScheme = Theme.of(context).colorScheme;

    if (lyricsController.isLoading) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    if (!lyricsController.hasLyrics) {
      return Center(
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
    }

    final lines = lyricsController.lines;
    final activeIndex = lyricsController.currentIndex;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is UserScrollNotification) {
          lyricsController.onUserScroll();
        }
        return false;
      },
      child: Stack(
        children: [
          ListView.builder(
            controller: lyricsController.scrollController,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: 24.0,
              vertical: 120.0,
            ),
            itemCount: lines.length,
            itemBuilder: (context, index) {
              final line = lines[index];
              final isActive = index == activeIndex;

              return InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  lyricsController.seekToLine(index);
                  if (onSeek != null && line.isSynced) {
                    onSeek!(line.timestamp);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 10.0,
                    horizontal: 8.0,
                  ),
                  child: Text(
                    line.text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: isActive ? 22 : 16,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      color: isActive
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                      height: 1.4,
                    ),
                  ),
                ),
              );
            },
          ),

          // Floating "Sync" Pill displayed when user has manually scrolled
          if (lyricsController.isUserScrollLocked)
            Positioned(
              bottom: 16,
              right: 16,
              child: FloatingActionButton.extended(
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                icon: const Icon(Icons.sync_rounded, size: 20),
                label: const Text('Sync'),
                onPressed: () => lyricsController.resumeAutoScroll(),
              ),
            ),
        ],
      ),
    );
  }
}
