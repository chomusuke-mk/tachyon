import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:miniaudio_player/miniaudio_player.dart' as ma;
import 'package:tachyon/shared/utils/duration_formatter.dart';

class _SliderDragNotifier extends ChangeNotifier {
  bool isDragging = false;
  double dragValueMs = 0.0;

  void start(double ms) {
    isDragging = true;
    dragValueMs = ms;
    notifyListeners();
  }

  void update(double ms) {
    if (dragValueMs == ms && isDragging) return;
    isDragging = true;
    dragValueMs = ms;
    notifyListeners();
  }

  void end() {
    if (!isDragging) return;
    isDragging = false;
    notifyListeners();
  }
}

/// Interactive seek slider with optimistic local drag state, simulated/extracted
/// waveform rendering, real prefetch buffer indicator, and 1 Hz tabular time readouts.
class WaveformSlider extends StatefulWidget {
  final Duration? position;
  final ValueListenable<Duration>? positionListenable;
  final ValueListenable<int>? positionSecondsListenable;
  final ValueListenable<ma.Buffer>? bufferListenable;
  final Duration duration;
  final bool isBuffering;
  final bool isLiveStream;
  final ValueChanged<Duration> onSeek;
  final int? currentIndex;
  final int? totalCount;
  final Duration Function()? playlistDuration;
  final Duration Function()? playlistPosition;
  final List<double>? waveform;

  @visibleForTesting
  static void clearGeometryCache() {
    _WaveformSliderPainter.clearGeometryCache();
  }

  const WaveformSlider({
    super.key,
    this.position,
    this.positionListenable,
    this.positionSecondsListenable,
    this.bufferListenable,
    required this.duration,
    required this.onSeek,
    this.isBuffering = false,
    this.isLiveStream = false,
    this.currentIndex,
    this.totalCount,
    this.playlistDuration,
    this.playlistPosition,
    this.waveform,
  }) : assert(
         position != null || positionListenable != null,
         'Either position or positionListenable must be provided',
       );

  @override
  State<WaveformSlider> createState() => _WaveformSliderState();
}

class _WaveformSliderState extends State<WaveformSlider> {
  final _SliderDragNotifier _dragNotifier = _SliderDragNotifier();
  ValueNotifier<int>? _fallbackSecondsNotifier;

  bool _showRemaining = true;
  bool _showPlaylistProgressTime = false;

  ValueListenable<int>? get _effectiveSecondsListenable {
    if (widget.positionSecondsListenable != null) {
      return widget.positionSecondsListenable;
    }
    return _fallbackSecondsNotifier;
  }

  void _syncFallbackSecondsListener() {
    final posListenable = widget.positionListenable;
    if (widget.positionSecondsListenable != null || posListenable == null) {
      _detachFallbackSecondsListener();
      return;
    }
    if (_fallbackSecondsNotifier == null) {
      _fallbackSecondsNotifier = ValueNotifier<int>(
        posListenable.value.inSeconds,
      );
      posListenable.addListener(_onFallbackPositionChanged);
    } else {
      _fallbackSecondsNotifier!.value = posListenable.value.inSeconds;
    }
  }

  void _detachFallbackSecondsListener([ValueListenable<Duration>? target]) {
    if (_fallbackSecondsNotifier != null) {
      (target ?? widget.positionListenable)?.removeListener(
        _onFallbackPositionChanged,
      );
      _fallbackSecondsNotifier!.dispose();
      _fallbackSecondsNotifier = null;
    }
  }

  void _onFallbackPositionChanged() {
    final sec = widget.positionListenable?.value.inSeconds ?? 0;
    if (_fallbackSecondsNotifier != null &&
        _fallbackSecondsNotifier!.value != sec) {
      _fallbackSecondsNotifier!.value = sec;
    }
  }

  @override
  void initState() {
    super.initState();
    _syncFallbackSecondsListener();
  }

  @override
  void didUpdateWidget(covariant WaveformSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.positionListenable != widget.positionListenable ||
        oldWidget.positionSecondsListenable !=
            widget.positionSecondsListenable) {
      if (oldWidget.positionListenable != null &&
          oldWidget.positionListenable != widget.positionListenable) {
        oldWidget.positionListenable!.removeListener(_onFallbackPositionChanged);
      }
      _syncFallbackSecondsListener();
    }
  }

  @override
  void dispose() {
    _detachFallbackSecondsListener();
    _dragNotifier.dispose();
    super.dispose();
  }

  Duration _currentPositionSnapshot() {
    if (_dragNotifier.isDragging) {
      return Duration(milliseconds: _dragNotifier.dragValueMs.round());
    }
    return widget.positionListenable?.value ?? widget.position ?? Duration.zero;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    if (widget.isLiveStream) {
      return RepaintBoundary(
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Colors.redAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'LIVE',
                style: textTheme.labelLarge?.copyWith(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              if (widget.bufferListenable != null)
                ValueListenableBuilder<ma.Buffer>(
                  valueListenable: widget.bufferListenable!,
                  builder: (context, buf, _) {
                    if (!buf.isBuffering && !widget.isBuffering) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      ),
                    );
                  },
                )
              else if (widget.isBuffering) ...[
                const SizedBox(width: 12),
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(width: 16),
              if (_effectiveSecondsListenable != null)
                ValueListenableBuilder<int>(
                  valueListenable: _effectiveSecondsListenable!,
                  builder: (context, sec, _) {
                    return Text(
                      Duration(
                        seconds: sec,
                      ).toFormattedString(padMinutes: true),
                      style: textTheme.bodySmall?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: colorScheme.onSurfaceVariant,
                      ),
                    );
                  },
                )
              else
                Text(
                  (widget.position ?? Duration.zero).toFormattedString(
                    padMinutes: true,
                  ),
                  style: textTheme.bodySmall?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      );
    }

    final totalMs = widget.duration.inMilliseconds.toDouble();
    final effectiveTotalMs = totalMs > 0 ? totalMs : 1.0;

    final Listenable paintRepaint = Listenable.merge([
      _dragNotifier,
      ?widget.positionListenable,
      ?widget.bufferListenable,
    ]);

    final Listenable counterListenable = Listenable.merge([
      _dragNotifier,
      ?_effectiveSecondsListenable,
    ]);

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waveform & Slider Area (0 widget rebuilds per tick or drag frame)
          SizedBox(
            height: 38,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    final fraction =
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        );
                    _dragNotifier.start(fraction * effectiveTotalMs);
                  },
                  onHorizontalDragUpdate: (details) {
                    final fraction =
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        );
                    _dragNotifier.update(fraction * effectiveTotalMs);
                  },
                  onHorizontalDragEnd: (_) {
                    final target = Duration(
                      milliseconds: _dragNotifier.dragValueMs.round(),
                    );
                    _dragNotifier.end();
                    widget.onSeek(target);
                  },
                  onHorizontalDragCancel: _dragNotifier.end,
                  onTapDown: (details) {
                    final fraction =
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        );
                    final target = Duration(
                      milliseconds: (fraction * effectiveTotalMs).round(),
                    );
                    widget.onSeek(target);
                  },
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: RepaintBoundary(
                      child: CustomPaint(
                        size: Size(constraints.maxWidth, 38),
                        painter: _WaveformSliderPainter(
                          repaint: paintRepaint,
                          dragNotifier: _dragNotifier,
                          positionListenable: widget.positionListenable,
                          bufferListenable: widget.bufferListenable,
                          fallbackPosition: widget.position ?? Duration.zero,
                          effectiveTotalMs: effectiveTotalMs,
                          isBufferingFallback: widget.isBuffering,
                          activeColor: colorScheme.primary,
                          inactiveColor: colorScheme.surfaceContainerHighest,
                          bufferedColor: colorScheme.primary.withValues(
                            alpha: 0.35,
                          ),
                          waveform: widget.waveform,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),

          // Time Counter Row quantized to 1 Hz (or live during drag)
          ListenableBuilder(
            listenable: counterListenable,
            builder: (context, _) {
              return _buildTimeCounterRow(
                _currentPositionSnapshot(),
                effectiveTotalMs,
                colorScheme,
                textTheme,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTimeCounterRow(
    Duration currentPosition,
    double effectiveTotalMs,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final currentMs = currentPosition.inMilliseconds.clamp(
      0,
      effectiveTotalMs.round(),
    );
    final elapsedDuration = Duration(milliseconds: currentMs);
    final remainingDuration = widget.duration - elapsedDuration;
    final counterStyle = textTheme.bodySmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w500,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Elapsed Time
        Text(elapsedDuration.toFormattedString(), style: counterStyle),
        if (widget.currentIndex != null && widget.totalCount != null)
          GestureDetector(
            onTap: () => setState(() {
              _showPlaylistProgressTime = !_showPlaylistProgressTime;
            }),
            child: Text(
              _showPlaylistProgressTime &&
                      widget.playlistPosition != null &&
                      widget.playlistDuration != null
                  ? '${widget.playlistPosition!().toFormattedString()} / ${widget.playlistDuration!().toFormattedString()}'
                  : '${widget.currentIndex ?? 0} / ${widget.totalCount ?? 0}',
              style: counterStyle,
            ),
          ),

        // Toggle Total / Remaining Time on tap
        GestureDetector(
          onTap: () => setState(() {
            _showRemaining = !_showRemaining;
          }),
          child: Text(
            _showRemaining
                ? remainingDuration.toFormattedString(prefix: '-')
                : widget.duration.toFormattedString(),
            style: counterStyle,
          ),
        ),
      ],
    );
  }
}

class _WaveformSliderPainter extends CustomPainter {
  final _SliderDragNotifier dragNotifier;
  final ValueListenable<Duration>? positionListenable;
  final ValueListenable<ma.Buffer>? bufferListenable;
  final Duration fallbackPosition;
  final double effectiveTotalMs;
  final bool isBufferingFallback;
  final Color activeColor;
  final Color inactiveColor;
  final Color bufferedColor;
  final List<double>? waveform;

  static const int _defaultPointCount = 120;

  // Smooth sinusoidal fallback waveform when track waveform points are not yet available
  static final List<double> _defaultSinusoidalWaveform =
      List<double>.unmodifiable(
        List<double>.generate(_defaultPointCount, (i) {
          final t = i / (_defaultPointCount - 1);
          final envelope = math.sin(math.pi * t);
          final wave =
              0.52 +
              0.36 * math.sin(2 * math.pi * t * 3.5) +
              0.12 * math.sin(2 * math.pi * t * 7.0);
          return (wave * (0.35 + 0.65 * envelope)).clamp(0.08, 0.98);
        }),
      );

  // Geometry cache keyed by Size and waveform to eliminate Path allocations during playback
  static Size? _cachedSize;
  static List<double>? _cachedWaveform;
  static Path? _cachedFullPath;

  @visibleForTesting
  static void clearGeometryCache() {
    _cachedSize = null;
    _cachedWaveform = null;
    _cachedFullPath = null;
  }

  static Path _getFullPath(Size size, List<double>? waveform) {
    final effectivePoints = (waveform != null && waveform.isNotEmpty)
        ? waveform
        : _defaultSinusoidalWaveform;

    if (_cachedSize == size &&
        identical(_cachedWaveform, effectivePoints) &&
        _cachedFullPath != null) {
      return _cachedFullPath!;
    }

    final centerY = size.height / 2;
    final halfHeight = (size.height / 2) * 0.88;
    final minAmp = halfHeight < 1.5 ? halfHeight : 1.5;
    double calcAmp(double pt) =>
        (pt.clamp(0.05, 1.0) * halfHeight).clamp(minAmp, halfHeight);
    final n = effectivePoints.length;

    final path = Path();
    if (n == 1) {
      final amp = calcAmp(effectivePoints[0]);
      path.addRect(Rect.fromLTWH(0, centerY - amp, size.width, amp * 2));
    } else {
      final dx = size.width / (n - 1);

      // Top boundary (smooth continuous quadratic Bezier contour)
      path.moveTo(0, centerY);
      for (int i = 0; i < n; i++) {
        final x = i * dx;
        final amp = calcAmp(effectivePoints[i]);
        final y = centerY - amp;
        if (i == 0) {
          path.lineTo(x, y);
        } else {
          final prevX = (i - 1) * dx;
          final prevAmp = calcAmp(effectivePoints[i - 1]);
          final prevY = centerY - prevAmp;
          final midX = (prevX + x) / 2;
          final midY = (prevY + y) / 2;
          path.quadraticBezierTo(prevX, prevY, midX, midY);
        }
      }
      final lastAmp = calcAmp(effectivePoints[n - 1]);
      path.lineTo(size.width, centerY - lastAmp);
      path.lineTo(size.width, centerY);

      // Bottom boundary (in reverse from n - 1 down to 0)
      for (int i = n - 1; i >= 0; i--) {
        final x = i * dx;
        final amp = calcAmp(effectivePoints[i]);
        final y = centerY + amp;
        if (i == n - 1) {
          path.lineTo(x, y);
        } else {
          final nextX = (i + 1) * dx;
          final nextAmp = calcAmp(effectivePoints[i + 1]);
          final nextY = centerY + nextAmp;
          final midX = (nextX + x) / 2;
          final midY = (nextY + y) / 2;
          path.quadraticBezierTo(nextX, nextY, midX, midY);
        }
      }
      final firstAmp = calcAmp(effectivePoints[0]);
      path.lineTo(0, centerY + firstAmp);
      path.close();
    }

    _cachedSize = size;
    _cachedWaveform = effectivePoints;
    _cachedFullPath = path;
    return path;
  }

  // Reusable Paint instances
  static final Paint _activePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  static final Paint _activeSheenPaint = Paint()
    ..isAntiAlias = true
    ..color = const Color(0x28FFFFFF)
    ..style = PaintingStyle.fill;
  static final Paint _activeStrokePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.1;
  static final Paint _evictedPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  static final Paint _evictedStrokePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _bufferedPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  static final Paint _bufferedStrokePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _inactivePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;
  static final Paint _inactiveStrokePaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  static final Paint _baselinePaint = Paint()
    ..isAntiAlias = true
    ..strokeWidth = 0.8;
  static final Paint _playheadLinePaint = Paint()
    ..isAntiAlias = true
    ..strokeWidth = 2.0;
  static final Paint _thumbPaint = Paint()..isAntiAlias = true;
  static final Paint _ringPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  _WaveformSliderPainter({
    required super.repaint,
    required this.dragNotifier,
    required this.positionListenable,
    required this.bufferListenable,
    required this.fallbackPosition,
    required this.effectiveTotalMs,
    required this.isBufferingFallback,
    required this.activeColor,
    required this.inactiveColor,
    required this.bufferedColor,
    this.waveform,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final fullPath = _getFullPath(size, waveform);
    final centerY = size.height / 2;

    final isDragging = dragNotifier.isDragging;
    final currentMs = isDragging
        ? dragNotifier.dragValueMs.clamp(0.0, effectiveTotalMs)
        : (positionListenable?.value ?? fallbackPosition).inMilliseconds
            .toDouble()
            .clamp(0.0, effectiveTotalMs);
    final progress = (currentMs / effectiveTotalMs).clamp(0.0, 1.0);

    final buf = bufferListenable?.value;
    final double clampedStart;
    final double clampedBuffer;
    if (buf != null && buf.end > Duration.zero) {
      clampedStart = (buf.start.inMilliseconds / effectiveTotalMs).clamp(
        0.0,
        1.0,
      );
      clampedBuffer = (buf.end.inMilliseconds / effectiveTotalMs).clamp(
        clampedStart,
        1.0,
      );
    } else if (buf?.isBuffering ?? isBufferingFallback) {
      clampedStart = progress;
      clampedBuffer = (progress + 0.15).clamp(progress, 1.0);
    } else if (bufferListenable == null) {
      clampedStart = 0.0;
      clampedBuffer = 1.0;
    } else {
      clampedStart = 0.0;
      clampedBuffer = 0.0;
    }

    final startX = size.width * clampedStart;
    final endX = size.width * clampedBuffer;
    final playheadX = (size.width * progress).clamp(0.0, size.width);

    _activePaint.color = activeColor;
    _activeStrokePaint.color = activeColor;
    _evictedPaint.color = activeColor.withValues(alpha: 0.30);
    _evictedStrokePaint.color = activeColor.withValues(alpha: 0.55);
    _bufferedPaint.color = bufferedColor;
    _bufferedStrokePaint.color = bufferedColor.withValues(alpha: 0.85);
    _inactivePaint.color = inactiveColor;
    _inactiveStrokePaint.color = inactiveColor.withValues(alpha: 0.8);
    _baselinePaint.color = activeColor.withValues(alpha: 0.18);
    _playheadLinePaint.color = activeColor;
    _thumbPaint.color = activeColor;

    // Layer 1: Background unplayed continuous waveform track
    canvas.drawPath(fullPath, _inactivePaint);
    canvas.drawPath(fullPath, _inactiveStrokePaint);

    // Layer 2: Universal preload buffer halo ahead of playhead ([aheadStartX .. endX])
    final aheadStartX = startX.clamp(playheadX, size.width);
    if (endX > aheadStartX) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(aheadStartX, 0, endX - aheadStartX, size.height),
      );
      canvas.drawPath(fullPath, _bufferedPaint);
      canvas.drawPath(fullPath, _bufferedStrokePaint);
      canvas.restore();
    }

    // Layer 3a: Unbuffered / evicted played history behind buffer start ([0 .. min(playheadX, startX)])
    final evictedEndX = playheadX.clamp(0.0, startX);
    if (evictedEndX > 0.0) {
      canvas.save();
      canvas.clipRect(Rect.fromLTWH(0, 0, evictedEndX, size.height));
      canvas.drawPath(fullPath, _evictedPaint);
      canvas.drawPath(fullPath, _evictedStrokePaint);
      canvas.restore();
    }

    // Layer 3b: Buffered played section behind playhead ([startX .. min(playheadX, endX)])
    final backBufStartX = startX.clamp(0.0, playheadX);
    final backBufEndX = endX.clamp(backBufStartX, playheadX);
    if (backBufEndX > backBufStartX) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(
          backBufStartX,
          0,
          backBufEndX - backBufStartX,
          size.height,
        ),
      );
      canvas.drawPath(fullPath, _activePaint);
      canvas.drawPath(fullPath, _activeSheenPaint);
      canvas.drawPath(fullPath, _activeStrokePaint);
      canvas.restore();
    }

    // Layer 3c: Played region beyond buffered end (if seek/position raced ahead of buffer)
    if (playheadX > endX) {
      canvas.save();
      canvas.clipRect(
        Rect.fromLTWH(endX, 0, playheadX - endX, size.height),
      );
      canvas.drawPath(
        fullPath,
        endX > 0.0 ? _evictedPaint : _activePaint,
      );
      canvas.restore();
    }

    // Layer 4: Center baseline
    canvas.drawLine(
      Offset(0, centerY),
      Offset(size.width, centerY),
      _baselinePaint,
    );

    // Layer 5: Playhead scrubber indicator line & cap
    canvas.drawLine(
      Offset(playheadX, 0),
      Offset(playheadX, size.height),
      _playheadLinePaint,
    );
    final thumbRadius = isDragging ? 5.5 : 4.0;
    canvas.drawCircle(Offset(playheadX, centerY), thumbRadius, _thumbPaint);
    if (isDragging) {
      _ringPaint.color = activeColor.withValues(alpha: 0.25);
      canvas.drawCircle(
        Offset(playheadX, centerY),
        thumbRadius * 2.2,
        _ringPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformSliderPainter oldDelegate) {
    return oldDelegate.dragNotifier != dragNotifier ||
        oldDelegate.positionListenable != positionListenable ||
        oldDelegate.bufferListenable != bufferListenable ||
        oldDelegate.fallbackPosition != fallbackPosition ||
        oldDelegate.effectiveTotalMs != effectiveTotalMs ||
        oldDelegate.isBufferingFallback != isBufferingFallback ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.bufferedColor != bufferedColor ||
        !identical(oldDelegate.waveform, waveform);
  }
}
