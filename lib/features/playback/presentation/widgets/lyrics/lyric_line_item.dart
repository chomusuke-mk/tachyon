import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/lyrics/domain/lyric_line.dart';

/// Single synchronized or static lyric line row inside `LyricsView`.
///
/// Registers and unregisters its [BuildContext] with [onMounted] / [onUnmounted]
/// so the parent view can smoothly center the active line without maintaining
/// `GlobalKey`s per line.
class LyricLineItem extends StatefulWidget {
  /// Parsed lyric line data and timestamp.
  final LyricLine line;

  /// Zero-based index of this line inside the active lyrics list.
  final int index;

  /// Whether this line corresponds to the current playback position.
  final bool isActive;

  /// Whether the loaded lyrics contain LRC timestamps.
  final bool isSynced;

  /// Whether a translated variant exists for [index].
  final bool hasTranslation;

  /// Translated lyric string to render alongside or instead of [line.text].
  final String? translatedText;

  /// Whether translated display mode is currently enabled.
  final bool isTranslated;

  /// Whether original and translated lines are stacked interleaved.
  final bool isInterleaved;

  /// Theme color scheme styling active and inactive lines.
  final ColorScheme colorScheme;

  /// Callback triggered when the user taps this lyric line to seek.
  final ValueChanged<int> onTapLine;

  /// Callback invoked when this item mounts or changes index.
  final void Function(int index, BuildContext context) onMounted;

  /// Callback invoked before this item unmounts or rebinds to another index.
  final void Function(int index, BuildContext context) onUnmounted;

  /// Creates a [LyricLineItem].
  const LyricLineItem({
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
  State<LyricLineItem> createState() => _LyricLineItemState();
}

class _LyricLineItemState extends State<LyricLineItem> {
  @override
  void initState() {
    super.initState();
    widget.onMounted(widget.index, context);
  }

  @override
  void didUpdateWidget(covariant LyricLineItem oldWidget) {
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

    // Plain unsynced lyrics render uniformly without dimming inactive lines.
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

    final displayLine = (isTranslated && hasTranslation)
        ? translatedText!
        : originalText;
    return Text(
      displayLine,
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
