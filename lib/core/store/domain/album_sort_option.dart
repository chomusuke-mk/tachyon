/// Sorting criteria available for album lists.
enum AlbumSortOption {
  /// Sort alphabetically by album title.
  title,

  /// Sort alphabetically by primary artist name.
  artist,

  /// Sort chronologically by release year.
  year,

  /// Sort by number of tracks in the album.
  trackCount;

  /// Parses [val] into an [AlbumSortOption], defaulting to [AlbumSortOption.title].
  static AlbumSortOption fromString(String? val) {
    return AlbumSortOption.values.firstWhere(
      (e) => e.name == val,
      orElse: () => AlbumSortOption.title,
    );
  }
}
