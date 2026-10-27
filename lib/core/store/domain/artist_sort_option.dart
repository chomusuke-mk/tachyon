enum ArtistSortOption {
  name,
  albums,
  tracks;

  static ArtistSortOption fromString(String? val) {
    return ArtistSortOption.values.firstWhere(
      (e) => e.name == val,
      orElse: () => ArtistSortOption.name,
    );
  }
}
