import 'package:flutter/foundation.dart';

/// Request sent from the UI isolate to the Core Service Isolate.
@immutable
class BackendRequest {
  final int requestId;
  final String method;
  final Map<String, dynamic> params;

  const BackendRequest({
    required this.requestId,
    required this.method,
    this.params = const {},
  });
}

/// Response returned from the Core Service Isolate to the UI isolate.
@immutable
class BackendResponse {
  final int requestId;
  final dynamic data;
  final String? error;

  const BackendResponse({required this.requestId, this.data, this.error});

  bool get isSuccess => error == null;
}

/// Push notification event sent from the Core Service Isolate to the UI isolate.
@immutable
class BackendEvent {
  final String topic;
  final dynamic payload;

  const BackendEvent({required this.topic, this.payload});
}

/// Standardized RPC method names supported by the Core Service Isolate.
abstract final class BackendMethods {
  // Playback commands
  static const String playbackPlay = 'playback.play';
  static const String playbackPause = 'playback.pause';
  static const String playbackStop = 'playback.stop';
  static const String playbackSeek = 'playback.seek';
  static const String playbackNext = 'playback.next';
  static const String playbackPrevious = 'playback.previous';
  static const String playbackSetVolume = 'playback.setVolume';
  static const String playbackSetEqualizer = 'playback.setEqualizer';
  static const String playbackSetOutputDevice = 'playback.setOutputDevice';
  static const String playbackGetAudioDevices = 'playback.getAudioDevices';
  static const String playbackPlayTrack = 'playback.playTrack';
  static const String playbackPlayQueue = 'playback.playQueue';
  static const String playbackSetShuffle = 'playback.setShuffle';
  static const String playbackSetLoopMode = 'playback.setLoopMode';
  static const String playbackRemoveQueueItem = 'playback.removeQueueItem';
  static const String playbackReorderQueue = 'playback.reorderQueue';
  static const String playbackClearQueue = 'playback.clearQueue';
  static const String playbackGetState = 'playback.getState';
  static const String playbackSetCrossfadeDuration =
      'playback.setCrossfadeDuration';
  static const String playbackSetCrossfadeCurve = 'playback.setCrossfadeCurve';
  static const String playbackOpen = 'playback.open';
  static const String playbackInsertNext = 'playback.insertNext';
  static const String playbackAppend = 'playback.append';
  static const String playbackSkipToIndex = 'playback.skipToIndex';
  static const String playbackSetRate = 'playback.setRate';
  static const String playbackSetPitch = 'playback.setPitch';
  static const String playbackSetSkipSilence = 'playback.setSkipSilence';
  static const String playbackSetCrossfadeConfig =
      'playback.setCrossfadeConfig';
  static const String playbackSetInfiniteMix = 'playback.setInfiniteMix';

  // Library & Catalog queries
  static const String libraryGetCatalogSnapshot = 'library.getCatalogSnapshot';
  static const String libraryGetTracks = 'library.getTracks';
  static const String libraryGetAlbums = 'library.getAlbums';
  static const String libraryGetArtists = 'library.getArtists';
  static const String libraryGetGenres = 'library.getGenres';
  static const String libraryGetAlbumTracks = 'library.getAlbumTracks';
  static const String libraryGetArtistTracks = 'library.getArtistTracks';
  static const String libraryStartScan = 'library.startScan';
  static const String libraryCancelScan = 'library.cancelScan';
  static const String libraryDeleteTrack = 'library.deleteTrack';

  // Metadata processing (Worker Isolates)
  static const String metadataGetMetadata = 'metadata.getMetadata';

  // Playlists
  static const String playlistsCreate = 'playlists.create';
  static const String playlistsDelete = 'playlists.delete';
  static const String playlistsRename = 'playlists.rename';
  static const String playlistsAddTracks = 'playlists.addTracks';
  static const String playlistsRemoveTrack = 'playlists.removeTrack';
  static const String playlistsReorderTracks = 'playlists.reorderTracks';
  static const String playlistsToggleLike = 'playlists.toggleLike';
  static const String playlistsClearHistory = 'playlists.clearHistory';

  // Lyrics
  static const String lyricsResolve = 'lyrics.resolve';
  static const String lyricsTranslate = 'lyrics.translate';
}

/// Standardized event topic names broadcast from the Core Service Isolate.
abstract final class BackendTopics {
  static const String playbackState = 'playback.state';
  static const String playbackPosition = 'playback.position';
  static const String playbackDevices = 'playback.devices';
  static const String libraryScanProgress = 'library.scanProgress';
  static const String catalogUpdated = 'catalog.updated';
}
