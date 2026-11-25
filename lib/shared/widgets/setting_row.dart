import 'package:material_ui/material_ui.dart';

/// Control layout category that determines responsive row sizing in [SettingRow].
enum ControllerType {
  /// Compact toggle switch control requiring minimal horizontal space.
  switchCtrl,

  /// Fixed-width dropdown selector control.
  dropdown,

  /// Continuous slider control rendered at a fixed width on wide layouts.
  slider,

  /// Text or input field control requiring extra horizontal width.
  text,

  /// Multi-line or composite control that always stacks below the label.
  complex,
}

/// Responsive settings row pairing a title and description with a control widget.
class SettingRow extends StatelessWidget {
  /// Primary label identifying the setting.
  final String title;

  /// Optional secondary helper text displayed below [title].
  final String? description;

  /// Control layout category governing width reservation and vertical stacking.
  final ControllerType type;

  /// Interactive control widget rendered beside or below the text section.
  final Widget child;

  /// Creates a [SettingRow].
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
