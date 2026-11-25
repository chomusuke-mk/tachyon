import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Studio rotary knob / circular interactive dial for continuous DSP parameters.
class StudioKnob extends StatefulWidget {
  /// Current numeric parameter value.
  final double value;

  /// Minimum selectable value.
  final double min;

  /// Maximum selectable value.
  final double max;

  /// Short caption displayed beneath the knob.
  final String label;

  /// Optional unit suffix appended to the formatted value readout.
  ///
  /// When set to `'%'`, the readout formats the normalized position between
  /// [min] and [max] as a percentage.
  final String? unit;

  /// Number of decimal places shown when [unit] is not `'%'`.
  final int decimals;

  /// Accent color of the active arc and indicator dot.
  final Color activeColor;

  /// Callback invoked with the clamped value during vertical drag gestures.
  final ValueChanged<double> onChanged;

  /// Diameter of the circular knob in logical pixels.
  final double size;

  /// Creates a [StudioKnob].
  const StudioKnob({
    super.key,
    required this.value,
    this.min = 0.0,
    this.max = 1.0,
    required this.label,
    this.unit,
    this.decimals = 2,
    this.activeColor = const Color(0xFF9D4EDD),
    required this.onChanged,
    this.size = 64.0,
  });

  @override
  State<StudioKnob> createState() => _StudioKnobState();
}

class _StudioKnobState extends State<StudioKnob> {
  double _dragAccumulator = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final normalized = ((widget.value - widget.min) / (widget.max - widget.min))
        .clamp(0.0, 1.0);
    final String valueText;
    if (widget.unit == '%') {
      valueText = '${(normalized * 100).round()}%';
    } else {
      valueText =
          '${widget.value.toStringAsFixed(widget.decimals)}${widget.unit ?? ''}';
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onVerticalDragStart: (_) => _dragAccumulator = widget.value,
          onVerticalDragUpdate: (details) {
            final range = widget.max - widget.min;
            final sensitivity = range / 120.0;
            _dragAccumulator -= details.primaryDelta! * sensitivity;
            final clamped = _dragAccumulator.clamp(widget.min, widget.max);
            widget.onChanged(clamped);
          },
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: Size(widget.size, widget.size),
                  painter: _KnobPainter(
                    normalizedValue: normalized,
                    activeColor: widget.activeColor,
                    trackColor: colorScheme.outlineVariant.withValues(
                      alpha: 0.35,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Text(
                    valueText,
                    style: TextStyle(
                      fontSize: widget.size > 60 ? 11 : 9.5,
                      fontWeight: FontWeight.w800,
                      color: colorScheme.onSurface,
                      fontFamily: 'monospace',
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.label,
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: colorScheme.onSurfaceVariant,
            letterSpacing: 0.2,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _KnobPainter extends CustomPainter {
  final double normalizedValue;
  final Color activeColor;
  final Color trackColor;

  const _KnobPainter({
    required this.normalizedValue,
    required this.activeColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 8) / 2;
    const startAngle = 0.75 * math.pi; // 135 deg
    const sweepRange = 1.5 * math.pi; // 270 deg

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    // Background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepRange,
      false,
      trackPaint,
    );

    // Active arc
    final activeSweep = sweepRange * normalizedValue;
    if (activeSweep > 0.01) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        activeSweep,
        false,
        activePaint,
      );

      // Indicator tip dot
      final tipAngle = startAngle + activeSweep;
      final tipOffset = Offset(
        center.dx + radius * math.cos(tipAngle),
        center.dy + radius * math.sin(tipAngle),
      );
      final tipPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;
      canvas.drawCircle(tipOffset, 2.5, tipPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _KnobPainter oldDelegate) {
    return oldDelegate.normalizedValue != normalizedValue ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.trackColor != trackColor;
  }
}
