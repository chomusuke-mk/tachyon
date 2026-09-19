import 'package:flutter/material.dart';

enum ControllerType { switchCtrl, dropdown, slider, text, complex }

class SettingRow extends StatelessWidget {
  final String title;
  final String? description;
  final ControllerType type;
  final Widget child;

  const SettingRow({
    super.key,
    required this.title,
    this.description,
    required this.type,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        bool stackVertically = false;
        double requiredWidth = 0;

        switch (type) {
          case ControllerType.switchCtrl:
            requiredWidth = 60;
            break;
          case ControllerType.dropdown:
            requiredWidth = 180;
            break;
          case ControllerType.slider:
            requiredWidth = 240;
            break;
          case ControllerType.text:
            requiredWidth = 250;
            break;
          case ControllerType.complex:
            stackVertically = true;
            break;
        }

        if (!stackVertically && constraints.maxWidth < (180 + requiredWidth)) {
          stackVertically = true;
        }

        final textSection = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(
                description!,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ],
          ],
        );

        Widget controllerWidget = child;
        if (type == ControllerType.dropdown) {
          controllerWidget = SizedBox(
            width: stackVertically ? double.infinity : 180,
            child: child,
          );
        } else if (type == ControllerType.slider) {
          controllerWidget = SizedBox(
            width: stackVertically ? double.infinity : 240,
            child: child,
          );
        }

        final alignedChild = Align(
          alignment: stackVertically
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth),
            child: controllerWidget,
          ),
        );

        if (stackVertically) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [textSection, const SizedBox(height: 10), alignedChild],
            ),
          );
        } else {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: textSection),
                const SizedBox(width: 16),
                alignedChild,
              ],
            ),
          );
        }
      },
    );
  }
}
