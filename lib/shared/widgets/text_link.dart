import 'dart:async';
import 'package:material_ui/material_ui.dart';

/// A generic text link widget that handles hover states, cursor, optional underline,
/// and properly manages hover cleanup across asynchronous callbacks (e.g., navigation).
class TextLink extends StatefulWidget {
  /// Label text rendered inside the interactive link.
  final String text;

  /// Optional synchronous or asynchronous callback invoked when tapped.
  final FutureOr<void> Function()? onTap;

  /// Base text style whose color and decoration update on hover.
  final TextStyle? style;

  /// Text and underline color applied while hovered.
  final Color? hoverColor;

  /// Text color applied when not hovered.
  final Color? defaultColor;

  /// Whether an underline decoration appears beneath [text] while hovered.
  final bool underlineOnHover;

  /// Ink ripple corner radius around the padded link area.
  final BorderRadius? borderRadius;

  /// Internal padding surrounding [text] inside the ink well.
  final EdgeInsetsGeometry? padding;

  /// Maximum number of lines permitted for [text].
  final int? maxLines;

  /// How visual overflow of [text] is handled.
  final TextOverflow? overflow;

  /// Whether the underlying [InkWell] can receive keyboard focus.
  final bool canRequestFocus;

  /// Creates a [TextLink].
  const TextLink({
    super.key,
    required this.text,
    this.onTap,
    this.style,
    this.hoverColor,
    this.defaultColor,
    this.underlineOnHover = true,
    this.borderRadius,
    this.padding = const EdgeInsets.symmetric(horizontal: 2.0, vertical: 1.0),
    this.maxLines = 1,
    this.overflow,
    this.canRequestFocus = false,
  });

  @override
  State<TextLink> createState() => _TextLinkState();
}

class _TextLinkState extends State<TextLink> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeHoverColor = widget.hoverColor ?? colorScheme.primary;
    final activeDefaultColor =
        widget.defaultColor ?? widget.style?.color ?? colorScheme.onSurfaceVariant;

    return InkWell(
      canRequestFocus: widget.canRequestFocus,
      borderRadius: widget.borderRadius ?? BorderRadius.circular(4),
      onHover: (hovering) {
        if (_isHovered != hovering) {
          setState(() => _isHovered = hovering);
        }
      },
      onTap: widget.onTap == null
          ? null
          : () async {
              setState(() => _isHovered = false);
              await widget.onTap!();
              if (mounted) {
                setState(() => _isHovered = false);
              }
            },
      child: Padding(
        padding: widget.padding ?? EdgeInsets.zero,
        child: Text(
          widget.text,
          maxLines: widget.maxLines,
          overflow: widget.overflow,
          style: widget.style?.copyWith(
            color: _isHovered ? activeHoverColor : activeDefaultColor,
            decoration: (_isHovered && widget.underlineOnHover)
                ? TextDecoration.underline
                : TextDecoration.none,
            decorationColor: activeHoverColor,
          ),
        ),
      ),
    );
  }
}
