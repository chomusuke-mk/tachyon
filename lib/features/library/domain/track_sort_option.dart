enum TrackSortOption {
  title,
  artist,
  album,
  year,
  duration,
  dateAdded;

  String toDbKey() {
    switch (this) {
      case TrackSortOption.title:
        return 'title';
      case TrackSortOption.artist:
        return 'artist';
      case TrackSortOption.album:
        return 'album';
      case TrackSortOption.year:
        return 'year';
      case TrackSortOption.duration:
        return 'duration';
      case TrackSortOption.dateAdded:
        return 'dateadded';
    }
  }

  static TrackSortOption fromString(String? val) {
    return TrackSortOption.values.firstWhere(
      (e) => e.name == val,
      orElse: () => TrackSortOption.title,
    );
  }
}
