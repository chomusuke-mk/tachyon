/// Sorting criteria available for track lists.
enum TrackSortOption {
  /// Sort alphabetically by track title.
  title,

  /// Sort alphabetically by primary artist name.
  artist,

  /// Sort alphabetically by album title.
  album,

  /// Sort chronologically by release year.
  year,

  /// Sort by track duration.
  duration,

  /// Sort by file modification / date-added timestamp.
  dateAdded;

  /// Parses [val] into a [TrackSortOption], defaulting to [TrackSortOption.title].
  static TrackSortOption fromString(String? val) {
    return TrackSortOption.values.firstWhere(
      (e) => e.name == val,
      orElse: () => TrackSortOption.title,
    );
  }
}
