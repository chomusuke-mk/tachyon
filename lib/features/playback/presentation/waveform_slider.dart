import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Interactive seek slider with optimistic local drag state, simulated aesthetic
/// waveform rendering, buffered progress indicator, and tabular numeric time readouts.
class WaveformSlider extends StatefulWidget {
  final Duration? position;
  final ValueListenable<Duration>? positionListenable;
  final Duration duration;
  final bool isBuffering;
  final ValueChanged<Duration> onSeek;
  final int? currentIndex;
  final int? totalCount;
  final Duration Function()? playlistDuration;
  final Duration Function()? playlistPosition;

  @visibleForTesting
  static void clearGeometryCache() {
    _WaveformSliderPainter.clearGeometryCache();
  }

  const WaveformSlider({
    super.key,
    this.position,
    this.positionListenable,
    required this.duration,
    required this.onSeek,
    this.isBuffering = false,
    this.currentIndex,
    this.totalCount,
    this.playlistDuration,
    this.playlistPosition,
  }) : assert(
          position != null || positionListenable != null,
          'Either position or positionListenable must be provided',
        );

  @override
  State<WaveformSlider> createState() => _WaveformSliderState();
}

class _WaveformSliderState extends State<WaveformSlider> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _showRemaining = true;
  bool _showPlaylistProgressTime = false;

  String _formatDuration(Duration duration, {String? prefix}) {
    final totalSeconds = duration.inSeconds.abs();
    final hours = (totalSeconds ~/ 3600); //.padLeft(2, '0');
    final minutes = ((totalSeconds % 3600) ~/ 60)
        .toString(); //.padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '${prefix ?? ""}$hours:${minutes.padLeft(2, '0')}:$seconds';
    }
    return '${prefix ?? ""}$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.positionListenable != null) {
      return ValueListenableBuilder<Duration>(
        valueListenable: widget.positionListenable!,
        builder: (context, pos, _) {
          return _buildSlider(context, pos);
        },
      );
    }
    return _buildSlider(context, widget.position ?? Duration.zero);
  }

  Widget _buildSlider(BuildContext context, Duration currentPosition) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final totalMs = widget.duration.inMilliseconds.toDouble();
    final effectiveTotalMs = totalMs > 0 ? totalMs : 1.0;

    final currentMs = _isDragging
        ? _dragValue
        : currentPosition.inMilliseconds.toDouble().clamp(
            0.0,
            effectiveTotalMs,
          );

    final progressFraction = (currentMs / effectiveTotalMs).clamp(0.0, 1.0);
    final remainingDuration =
        widget.duration - Duration(milliseconds: currentMs.round());

    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Waveform & Slider Area
          SizedBox(
            height: 38,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onHorizontalDragStart: (details) {
                    setState(() {
                      _isDragging = true;
                      final fraction =
                          (details.localPosition.dx / constraints.maxWidth)
                              .clamp(0.0, 1.0);
                      _dragValue = fraction * effectiveTotalMs;
                    });
                  },
                  onHorizontalDragUpdate: (details) {
                    setState(() {
                      final fraction =
                          (details.localPosition.dx / constraints.maxWidth)
                              .clamp(0.0, 1.0);
                      _dragValue = fraction * effectiveTotalMs;
                    });
                  },
                  onHorizontalDragEnd: (details) {
                    final target = Duration(milliseconds: _dragValue.round());
                    widget.onSeek(target);
                    setState(() {
                      _isDragging = false;
                    });
                  },
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
                          progress: progressFraction,
                          bufferedFraction: widget.isBuffering
                              ? (progressFraction + 0.15).clamp(0.0, 1.0)
                              : 1.0,
                          activeColor: colorScheme.primary,
                          inactiveColor: colorScheme.surfaceContainerHighest,
                          bufferedColor:
                              colorScheme.primary.withValues(alpha: 0.35),
                          isDragging: _isDragging,
                          positionMs: currentMs.round(),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 4),

          // Time Counter Row with Tabular Figures
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Elapsed Time
              Text(
                _formatDuration(Duration(milliseconds: currentMs.round())),
                style: textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (widget.currentIndex != null && widget.totalCount != null)
                GestureDetector(
                  onTap: () => setState(
                    () =>
                        _showPlaylistProgressTime = !_showPlaylistProgressTime,
                  ),
                  child: Text(
                    _showPlaylistProgressTime &&
                            widget.playlistPosition != null &&
                            widget.playlistDuration != null
                        ? '${_formatDuration(widget.playlistPosition!())} / ${_formatDuration(widget.playlistDuration!())}'
                        : '${widget.currentIndex ?? 0} / ${widget.totalCount ?? 0}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),

              // Toggle Total / Remaining Time on tap
              GestureDetector(
                onTap: () => setState(() => _showRemaining = !_showRemaining),
                child: Text(
                  _showRemaining
                      ? _formatDuration(remainingDuration, prefix: "-")
                      : _formatDuration(widget.duration),
                  style: textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WaveformSliderPainter extends CustomPainter {
  final double progress;
  final double bufferedFraction;
  final Color activeColor;
  final Color inactiveColor;
  final Color bufferedColor;
  final bool isDragging;
  final int positionMs;

  static const int _barCount = 55;
  static const double _barWidth = 3.5;
  static const double _barRadius = 2.0;
  static const int _positionQuantizationMs = 50;

  // Precomputed static waveform amplitude multipliers (0.3 to 0.9)
  static final List<double> _waveformAmplitudes = List<double>.generate(
    _barCount,
    (i) {
      final angle = (i / _barCount) * math.pi * 3;
      return math.sin(angle).abs() * 0.6 + 0.3;
    },
    growable: false,
  );

  // Precomputed bar fractions [0.0 ... 1.0]
  static final List<double> _barFractions = List<double>.generate(
    _barCount,
    (i) => i / (_barCount - 1),
    growable: false,
  );

  // Geometry cache keyed by Size to eliminate RRect allocations during playback
  static Size? _cachedSize;
  static List<RRect>? _cachedBars;

  @visibleForTesting
  static void clearGeometryCache() {
    _cachedSize = null;
    _cachedBars = null;
  }

  static List<RRect> _getBars(Size size) {
    if (_cachedSize == size && _cachedBars != null) {
      return _cachedBars!;
    }
    final centerY = size.height / 2;
    final spacing = (size.width - (_barCount * _barWidth)) / (_barCount - 1);
    final heightFactor = size.height * 0.75;

    final bars = List<RRect>.generate(_barCount, (i) {
      final x = i * (_barWidth + spacing);
      final amplitude = _waveformAmplitudes[i] * heightFactor;
      final halfHeight = math.max(3.0, amplitude / 2);
      return RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + _barWidth / 2, centerY),
          width: _barWidth,
          height: halfHeight * 2,
        ),
        const Radius.circular(_barRadius),
      );
    }, growable: false);

    _cachedSize = size;
    _cachedBars = bars;
    return bars;
  }

  // Reusable Path objects to avoid per-frame allocations
  static final Path _playedPath = Path();
  static final Path _bufferedPath = Path();
  static final Path _inactivePath = Path();

  // Reusable Paint instances
  static final Paint _activePaint = Paint()..isAntiAlias = true;
  static final Paint _bufferedPaint = Paint()..isAntiAlias = true;
  static final Paint _inactivePaint = Paint()..isAntiAlias = true;
  static final Paint _thumbPaint = Paint()..isAntiAlias = true;
  static final Paint _ringPaint = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  _WaveformSliderPainter({
    required this.progress,
    required this.bufferedFraction,
    required this.activeColor,
    required this.inactiveColor,
    required this.bufferedColor,
    required this.isDragging,
    this.positionMs = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final bars = _getBars(size);
    final centerY = size.height / 2;

    _activePaint.color = activeColor;
    _bufferedPaint.color = bufferedColor;
    _inactivePaint.color = inactiveColor;
    _thumbPaint.color = activeColor;

    _playedPath.reset();
    _bufferedPath.reset();
    _inactivePath.reset();

    int playedCount = 0;
    int bufferedCount = 0;
    int inactiveCount = 0;

    // Batch 55 bars into played, buffered, and inactive Paths
    for (int i = 0; i < _barCount; i++) {
      final fraction = _barFractions[i];
      if (fraction <= progress) {
        _playedPath.addRRect(bars[i]);
        playedCount++;
      } else if (fraction <= bufferedFraction) {
        _bufferedPath.addRRect(bars[i]);
        bufferedCount++;
      } else {
        _inactivePath.addRRect(bars[i]);
        inactiveCount++;
      }
    }

    // Execute batched drawPath calls (only 2 calls when bufferedFraction >= 1.0)
    if (playedCount > 0) {
      canvas.drawPath(_playedPath, _activePaint);
    }
    if (bufferedCount > 0) {
      canvas.drawPath(_bufferedPath, _bufferedPaint);
    }
    if (inactiveCount > 0) {
      canvas.drawPath(_inactivePath, _inactivePaint);
    }

    // Playhead thumb circle
    final thumbX = progress * size.width;
    final thumbRadius = isDragging ? 6.5 : 5.0;

    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, _thumbPaint);
    if (isDragging) {
      _ringPaint.color = activeColor.withValues(alpha: 0.25);
      canvas.drawCircle(Offset(thumbX, centerY), thumbRadius * 2.2, _ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformSliderPainter oldDelegate) {
    if (identical(this, oldDelegate)) return false;
    if (oldDelegate.isDragging != isDragging) return true;
    if (isDragging && oldDelegate.progress != progress) return true;
    if (oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor ||
        oldDelegate.bufferedColor != bufferedColor) {
      return true;
    }

    // Active bar boundary check: 55 discrete bar positions
    final oldBar = (oldDelegate.progress * (_barCount - 1)).floor();
    final newBar = (progress * (_barCount - 1)).floor();
    if (oldBar != newBar) return true;

    // Buffered bar boundary check
    final oldBufferedBar =
        (oldDelegate.bufferedFraction * (_barCount - 1)).floor();
    final newBufferedBar =
        (bufferedFraction * (_barCount - 1)).floor();
    if (oldBufferedBar != newBufferedBar) return true;

    // Quantize position into 50ms buckets (~20fps maximum thumb repaint rate)
    final oldBucket = oldDelegate.positionMs ~/ _positionQuantizationMs;
    final newBucket = positionMs ~/ _positionQuantizationMs;
    if (oldBucket != newBucket) return true;

    return false;
  }
}
