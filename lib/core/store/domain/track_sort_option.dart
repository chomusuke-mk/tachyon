enum TrackSortOption {
  title,
  artist,
  album,
  year,
  duration,
  dateAdded;

  static TrackSortOption fromString(String? val) {
    return TrackSortOption.values.firstWhere(
      (e) => e.name == val,
      orElse: () => TrackSortOption.title,
    );
  }
}
