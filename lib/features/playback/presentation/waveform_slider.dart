import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Interactive seek slider with optimistic local drag state, simulated aesthetic
/// waveform rendering, buffered progress indicator, and tabular numeric time readouts.
class WaveformSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final bool isBuffering;
  final ValueChanged<Duration> onSeek;

  const WaveformSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
    this.isBuffering = false,
  });

  @override
  State<WaveformSlider> createState() => _WaveformSliderState();
}

class _WaveformSliderState extends State<WaveformSlider> {
  bool _isDragging = false;
  double _dragValue = 0.0;
  bool _showRemaining = true;

  String _formatDuration(Duration duration, {bool isNegative = false}) {
    final totalSeconds = duration.inSeconds.abs();
    final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
    return '${isNegative ? "-" : ""}$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final totalMs = widget.duration.inMilliseconds.toDouble();
    final effectiveTotalMs = totalMs > 0 ? totalMs : 1.0;

    final currentMs = _isDragging
        ? _dragValue
        : widget.position.inMilliseconds.toDouble().clamp(
            0.0,
            effectiveTotalMs,
          );

    final progressFraction = (currentMs / effectiveTotalMs).clamp(0.0, 1.0);
    final remainingDuration =
        widget.duration - Duration(milliseconds: currentMs.round());

    return Column(
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
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        );
                    _dragValue = fraction * effectiveTotalMs;
                  });
                },
                onHorizontalDragUpdate: (details) {
                  setState(() {
                    final fraction =
                        (details.localPosition.dx / constraints.maxWidth).clamp(
                          0.0,
                          1.0,
                        );
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
                child: CustomPaint(
                  size: Size(constraints.maxWidth, 38),
                  painter: _WaveformSliderPainter(
                    progress: progressFraction,
                    bufferedFraction: widget.isBuffering
                        ? (progressFraction + 0.15).clamp(0.0, 1.0)
                        : 1.0,
                    activeColor: colorScheme.primary,
                    inactiveColor: colorScheme.surfaceContainerHighest,
                    bufferedColor: colorScheme.primary.withValues(alpha: 0.35),
                    isDragging: _isDragging,
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

            // Toggle Total / Remaining Time on tap
            GestureDetector(
              onTap: () => setState(() => _showRemaining = !_showRemaining),
              child: Text(
                _showRemaining
                    ? _formatDuration(remainingDuration, isNegative: true)
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

  static const int _barCount = 55;
  static const double _barWidth = 3.5;
  static const double _barRadius = 2.0;

  _WaveformSliderPainter({
    required this.progress,
    required this.bufferedFraction,
    required this.activeColor,
    required this.inactiveColor,
    required this.bufferedColor,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final activePaint = Paint()..color = activeColor;
    final bufferedPaint = Paint()..color = bufferedColor;
    final inactivePaint = Paint()..color = inactiveColor;

    final centerY = size.height / 2;
    final spacing = (size.width - (_barCount * _barWidth)) / (_barCount - 1);

    for (int i = 0; i < _barCount; i++) {
      final x = i * (_barWidth + spacing);
      final fraction = i / (_barCount - 1);

      // Aesthetic simulated waveform amplitude curve
      final angle = (i / _barCount) * math.pi * 3;
      final amplitude =
          (math.sin(angle).abs() * 0.6 + 0.3) * (size.height * 0.75);
      final halfHeight = math.max(3.0, amplitude / 2);

      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x + _barWidth / 2, centerY),
          width: _barWidth,
          height: halfHeight * 2,
        ),
        const Radius.circular(_barRadius),
      );

      if (fraction <= progress) {
        canvas.drawRRect(rect, activePaint);
      } else if (fraction <= bufferedFraction) {
        canvas.drawRRect(rect, bufferedPaint);
      } else {
        canvas.drawRRect(rect, inactivePaint);
      }
    }

    // Playhead thumb circle
    final thumbX = progress * size.width;
    final thumbPaint = Paint()..color = activeColor;
    final thumbRadius = isDragging ? 6.5 : 5.0;

    canvas.drawCircle(Offset(thumbX, centerY), thumbRadius, thumbPaint);
    if (isDragging) {
      final ringPaint = Paint()
        ..color = activeColor.withValues(alpha: 0.25)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(Offset(thumbX, centerY), thumbRadius * 2.2, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformSliderPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.bufferedFraction != bufferedFraction ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.activeColor != activeColor;
  }
}
