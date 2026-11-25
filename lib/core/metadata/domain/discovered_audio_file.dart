/// Discovered audio file entity awaiting metadata extraction.
class DiscoveredAudioFile {
  /// File path, OPFS path, or URL of the discovered audio source.
  final String path;

  /// File size in bytes (`0` when unknown, such as for remote URLs).
  final int size;

  /// Last modification timestamp used for incremental scan diffing.
  final int modifiedAt;

  /// Creates a [DiscoveredAudioFile] with [path], [size], and [modifiedAt].
  const DiscoveredAudioFile({
    required this.path,
    required this.size,
    required this.modifiedAt,
  });

  @override
  String toString() => 'DiscoveredAudioFile($path, $size bytes)';
}
