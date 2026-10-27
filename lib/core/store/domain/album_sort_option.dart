enum AlbumSortOption {
  title,
  artist,
  year,
  trackCount;

  static AlbumSortOption fromString(String? val) {
    return AlbumSortOption.values.firstWhere(
      (e) => e.name == val,
      orElse: () => AlbumSortOption.title,
    );
  }
}
