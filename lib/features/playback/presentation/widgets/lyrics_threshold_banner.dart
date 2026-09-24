import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:tachyon/features/locales/presentation/locale_controller.dart';
import 'package:tachyon/features/playback/presentation/lyrics_controller.dart';

/// Non-invasive HTTP 429 rate limit countdown banner for lrclib.net.
///
/// Displays a live countdown whenever [LyricsController.isThresholdWaiting] is true
/// and remaining seconds are <= 10s. Automatically animates out when the countdown
/// expires or when the retry succeeds. Includes a manual dismiss button for non-invasive UX.
class LyricsThresholdBanner extends StatefulWidget {
  final VoidCallback? onDismiss;
  final EdgeInsetsGeometry? margin;

  const LyricsThresholdBanner({
    super.key,
    this.onDismiss,
    this.margin,
  });

  @override
  State<LyricsThresholdBanner> createState() => _LyricsThresholdBannerState();
}

class _LyricsThresholdBannerState extends State<LyricsThresholdBanner> {
  bool _dismissedByUser = false;

  @override
  Widget build(BuildContext context) {
    final lyricsController = context.watch<LyricsController>();

    return StreamBuilder<int?>(
      stream: lyricsController.thresholdStream,
      initialData: lyricsController.thresholdCountdownSeconds,
      builder: (context, snapshot) {
        final remainingSeconds =
            snapshot.data ?? lyricsController.thresholdCountdownSeconds;
        final hasActiveSeconds =
            remainingSeconds != null && remainingSeconds > 0;
        final isWaiting =
            lyricsController.isThresholdWaiting && hasActiveSeconds;

        if (!isWaiting) {
          _dismissedByUser = false;
        }

        final isVisible = isWaiting && !_dismissedByUser;

        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              alignment: Alignment.topCenter,
              child: FadeTransition(
                opacity: animation,
                child: child,
              ),
            );
          },
          child: isVisible
              ? _buildBanner(context, remainingSeconds)
              : const SizedBox.shrink(key: ValueKey('threshold_banner_hidden')),
        );
      },
    );
  }

  Widget _buildBanner(BuildContext context, int remainingSeconds) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final strings = context.watch<LocaleController>().localeStrings;

    final progress = (remainingSeconds / 10.0).clamp(0.0, 1.0);

    return Container(
      key: const ValueKey('threshold_banner_visible'),
      margin: widget.margin ??
          const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(
          color: colorScheme.tertiary.withValues(alpha: 0.35),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 8.0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Circular progress countdown indicator
          SizedBox(
            width: 22,
            height: 22,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 2.2,
                  backgroundColor:
                      colorScheme.tertiary.withValues(alpha: 0.2),
                  color: colorScheme.tertiary,
                ),
                Text(
                  '$remainingSeconds',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12.0),
          // Formatted countdown message
          Expanded(
            child: Text(
              strings.npLyricsThresholdWaitingFormatted(remainingSeconds),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8.0),
          // Non-invasive dismiss button
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            tooltip: strings.npLyricsBannerDismiss,
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: colorScheme.onSurfaceVariant,
            onPressed: () {
              setState(() {
                _dismissedByUser = true;
              });
              widget.onDismiss?.call();
            },
          ),
        ],
      ),
    );
  }
}
