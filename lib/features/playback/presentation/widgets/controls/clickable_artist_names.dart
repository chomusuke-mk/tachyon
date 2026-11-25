import 'package:material_ui/material_ui.dart';
import 'package:tachyon/core/store/domain/artist.dart';
import 'package:tachyon/features/library/presentation/screens/artist_detail_screen.dart';
import 'package:tachyon/shared/widgets/text_link.dart';

/// Displays comma-separated clickable [artists] that navigate to each artist's
/// detail screen, or renders [fallbackName] when artist records are unavailable.
class ClickableArtistNames extends StatelessWidget {
  /// Resolved catalog [Artist] objects linked from the current track.
  final List<Artist> artists;

  /// Plain fallback text displayed when [artists] is empty.
  final String? fallbackName;

  /// Base text style applied to separators and fallback labels.
  final TextStyle? style;

  /// Active color scheme used for default and hovered artist link tints.
  final ColorScheme colorScheme;

  /// Creates a [ClickableArtistNames].
  const ClickableArtistNames({
    super.key,
    required this.artists,
    this.fallbackName,
    this.style,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveStyle =
        style ??
        Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(color: colorScheme.onSurfaceVariant);

    if (artists.isEmpty) {
      if (fallbackName != null && fallbackName!.isNotEmpty) {
        return Center(
          child: Text(
            fallbackName!,
            style: effectiveStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Center(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (int i = 0; i < artists.length; i++) ...[
              if (i > 0) Text(', ', style: effectiveStyle),
              TextLink(
                text: artists[i].name,
                style: effectiveStyle,
                hoverColor: colorScheme.primary,
                defaultColor: colorScheme.onSurfaceVariant,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArtistDetailScreen(artist: artists[i]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
