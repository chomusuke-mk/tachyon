/// Sorting criteria available for artist lists.
enum ArtistSortOption {
  /// Sort alphabetically by artist name.
  name,

  /// Sort by number of associated albums.
  albums,

  /// Sort by number of associated tracks.
  tracks;

  /// Parses [val] into an [ArtistSortOption], defaulting to [ArtistSortOption.name].
  static ArtistSortOption fromString(String? val) {
    return ArtistSortOption.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ArtistSortOption.name,
    );
  }
}
