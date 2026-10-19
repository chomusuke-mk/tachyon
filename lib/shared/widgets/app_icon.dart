import 'package:flutter/material.dart';

class AppIcon extends StatelessWidget {
  const AppIcon({super.key});

  static const double _iconSize = 34.0;
  static const double _rightSpacing = 12.0;
  static const double _minRequiredWidth = _iconSize + _rightSpacing;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      fit: FlexFit.loose,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Si no entra el icono completo con su margen, se oculta por completo
          if (constraints.maxWidth < _minRequiredWidth ||
              constraints.maxHeight < _iconSize) {
            return const SizedBox.shrink();
          }

          return Padding(
            padding: const EdgeInsets.only(right: _rightSpacing),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.0),
              child: Image.asset(
                'assets/icon/icon_small.webp',
                cacheHeight: 100,
                cacheWidth: 100,
                width: _iconSize,
                height: _iconSize,
                fit: BoxFit.contain,
              ),
            ),
          );
        },
      ),
    );
  }
}
