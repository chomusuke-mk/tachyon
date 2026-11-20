import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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

  static const int _barCount = 55;
  static const double _barWidth = 3.5;
  static const double _barRadius = 2.0;

  // Precomputed bar fractions [0.0 ... 1.0]
  static final List<double> _barFractions = List<double>.generate(
    _barCount,
    (i) => i / (_barCount - 1),
    growable: false,
  );

  // Geometry cache keyed by Size and waveform to eliminate RRect allocations during playback
  static Size? _cachedSize;
  static List<double>? _cachedWaveform;
  static List<RRect>? _cachedBars;

  @visibleForTesting
  static void clearGeometryCache() {
    _cachedSize = null;
    _cachedWaveform = null;
    _cachedBars = null;
  }

  static List<RRect> _getBars(Size size, List<double>? waveform) {
    if (_cachedSize == size &&
        identical(_cachedWaveform, waveform) &&
        _cachedBars != null) {
      return _cachedBars!;
    }
    final centerY = size.height / 2;
    final spacing = (size.width - (_barCount * _barWidth)) / (_barCount - 1);
    final heightFactor = size.height * 0.75;
    final hasWaveform = waveform != null && waveform.isNotEmpty;

    final bars = List<RRect>.generate(_barCount, (i) {
      final x = i * (_barWidth + spacing);
      final double amp;
      if (hasWaveform) {
        final t = i / (_barCount - 1);
        final wIndex = (t * (waveform.length - 1)).round();
        amp = 0.2 + (waveform[wIndex].clamp(0.0, 1.0) * 0.8);
      } else {
        amp = 0.35;
      }
      final halfHeight = math.max(3.0, (amp * heightFactor) / 2);
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
    _cachedWaveform = waveform;
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
    final bars = _getBars(size, waveform);
    final centerY = size.height / 2;

    final isDragging = dragNotifier.isDragging;
    final currentMs = isDragging
        ? dragNotifier.dragValueMs.clamp(0.0, effectiveTotalMs)
        : (positionListenable?.value ?? fallbackPosition).inMilliseconds
            .toDouble()
            .clamp(0.0, effectiveTotalMs);
    final progress = (currentMs / effectiveTotalMs).clamp(0.0, 1.0);

    final buf = bufferListenable?.value;
    final double bufStartFraction;
    final double bufEndFraction;
    if (buf != null && buf.end > Duration.zero) {
      bufStartFraction = (buf.start.inMilliseconds / effectiveTotalMs).clamp(
        0.0,
        1.0,
      );
      bufEndFraction = (buf.end.inMilliseconds / effectiveTotalMs).clamp(
        0.0,
        1.0,
      );
    } else if (buf?.isBuffering ?? isBufferingFallback) {
      bufStartFraction = progress;
      bufEndFraction = (progress + 0.15).clamp(0.0, 1.0);
    } else {
      bufStartFraction = progress;
      bufEndFraction = 1.0;
    }

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

    // Batch 55 bars into played, buffered (real Buffer range), and inactive Paths
    for (int i = 0; i < _barCount; i++) {
      final fraction = _barFractions[i];
      if (fraction <= progress) {
        _playedPath.addRRect(bars[i]);
        playedCount++;
      } else if (fraction >= bufStartFraction && fraction <= bufEndFraction) {
        _bufferedPath.addRRect(bars[i]);
        bufferedCount++;
      } else {
        _inactivePath.addRRect(bars[i]);
        inactiveCount++;
      }
    }

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
