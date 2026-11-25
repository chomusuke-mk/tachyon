import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';

/// Studio spectrum analyzer painter rendering clean, fluid, audio-reactive
/// vertical gradient bars across the full width of the artwork, floating
/// transparently with peak caps and zero dB/Hz clutter.
class SpectrumBarsPainter extends CustomPainter {
  /// Fallback per-band spectrum magnitudes (`0.0` to `1.0`) when [magnitudesProvider] is `null`.
  final List<double> magnitudes;

  /// Optional callback providing live spectrum magnitudes without widget rebuilds.
  final List<double> Function()? magnitudesProvider;

  /// Whether playback is active when [isActiveProvider] is `null`.
  final bool isActive;

  /// Optional callback returning whether playback is currently active.
  final bool Function()? isActiveProvider;

  /// Corner radius hint retained for parity with artwork-aligned visualizers.
  final double cornerRadius;

  /// Optional base color used to generate the vertical bar gradient.
  ///
  /// Falls back to [defaultSpectrumGradient] when `null`.
  final Color? accentColor;

  /// Default multi-stop vertical gradient applied when [accentColor] is `null`.
  static const LinearGradient defaultSpectrumGradient = LinearGradient(
    colors: [
      Color(0xFF06B6D4), // Cyan
      Color(0xFF3B82F6), // Blue
      Color(0xFF8B5CF6), // Violet
      Color(0xFFF43F5E), // Rose
    ],
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
  );

  final Paint _barPaint = Paint()..style = PaintingStyle.fill;
  final Paint _capPaint = Paint()
    ..color = Colors.white.withValues(alpha: 0.95)
    ..strokeWidth = 2.0;

  Size? _cachedShaderSize;
  Color? _cachedAccentColor;
  Shader? _cachedShader;

  /// Creates a [SpectrumBarsPainter].
  SpectrumBarsPainter({
    super.repaint,
    required this.magnitudes,
    this.magnitudesProvider,
    this.isActive = true,
    this.isActiveProvider,
    this.cornerRadius = 20.0,
    this.accentColor,
  });

  Shader _resolveShader(Size size) {
    if (_cachedShader != null &&
        _cachedShaderSize == size &&
        _cachedAccentColor == accentColor) {
      return _cachedShader!;
    }
    final gradient = accentColor != null
        ? LinearGradient(
            colors: [
              accentColor!,
              HSLColor.fromColor(accentColor!)
                  .withLightness(
                    (HSLColor.fromColor(accentColor!).lightness + 0.15)
                        .clamp(0.0, 1.0),
                  )
                  .toColor(),
              Colors.white.withValues(alpha: 0.95),
            ],
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
          )
        : defaultSpectrumGradient;
    _cachedShader = gradient.createShader(Offset.zero & size);
    _cachedShaderSize = size;
    _cachedAccentColor = accentColor;
    return _cachedShader!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final activeMagnitudes = magnitudesProvider?.call() ?? magnitudes;
    final active = isActiveProvider?.call() ?? isActive;
    final bandCount = math.max(
      1,
      activeMagnitudes.isEmpty ? 10 : activeMagnitudes.length,
    );
    const spacing = 4.0;
    final totalSpacing = spacing * (bandCount - 1);
    final barWidth = math.max(2.0, (size.width - totalSpacing) / bandCount);

    _barPaint.shader = _resolveShader(size);

    for (int i = 0; i < bandCount; i++) {
      final mag = (i < activeMagnitudes.length && active)
          ? activeMagnitudes[i].clamp(0.0, 1.0)
          : 0.03;

      final x = i * (barWidth + spacing);
      final barHeight = math.max(6.0, size.height * mag);
      final y = size.height - barHeight;

      final barRect = Rect.fromLTWH(x, y, barWidth, barHeight);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          barRect,
          Radius.circular(math.min(barWidth / 2, 4.0)),
        ),
        _barPaint,
      );

      // Peak cap line
      if (active && mag > 0.06) {
        canvas.drawLine(
          Offset(x, y - 3),
          Offset(x + barWidth, y - 3),
          _capPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SpectrumBarsPainter oldDelegate) {
    if (oldDelegate.isActive != isActive ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.accentColor != accentColor ||
        oldDelegate.magnitudesProvider != magnitudesProvider ||
        oldDelegate.isActiveProvider != isActiveProvider) {
      return true;
    }
    if (magnitudesProvider != null) {
      return false;
    }
    return oldDelegate.magnitudes != magnitudes;
  }
}
