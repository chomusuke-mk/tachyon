import 'dart:async';
import 'dart:isolate';

import 'package:miniaudio_player/miniaudio_player.dart';

import 'package:tachyon/core/backend/backend_host.dart';
import 'package:tachyon/core/backend/backend_protocol.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart'
    show ExtractedTrackData;
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/features/library/domain/catalog_snapshot.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart'
    show CrossfadeCurve;

/// Abstract client interface consumed exclusively by UI controllers.
/// The UI isolate contains ZERO database queries, ZERO audio player adapters,
/// and ZERO metadata/image decoders. All operations are dispatched through this client.
abstract class TachyonBackendClient {
  // --- Streams (Pushed from Core Isolate) ---
  Stream<PlaybackState> get playbackStateStream;
  Stream<Duration> get positionStream;
  Stream<List<double>> get visualizerStream;
  Stream<List<AudioDevice>> get devicesStream;
  Stream<ScanProgress> get scanProgressStream;
  Stream<void> get catalogUpdatedStream;

  // --- Playback Commands ---
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();
  Future<void> setVolume(double volume);
  Future<void> setRate(double rate);
  Future<void> setPitch(double pitch);
  Future<void> setSkipSilence(bool enabled);
  Future<void> setVolumeNormalization(bool enabled);
  Future<void> setPreamp(double preampDb);
  Future<void> setBalance(double balance);
  Future<void> setMono(bool enabled);
  Future<void> setCrossfeed(CrossfeedMode mode);
  Future<void> setSpatializer(double width);
  Future<void> setLimiter(bool enabled);
  Future<void> setEqualizer(Equalizer equalizer);
  Future<void> setOutputDevice(AudioDevice device);
  Future<void> setVisualizerEnabled(bool enabled);
  Future<List<AudioDevice>> getAudioDevices();
  Future<void> playTrack(int trackId, {bool play = true});
  Future<void> playQueue(
    List<int> trackIds, {
    int? startIndex,
    bool play = true,
    bool shuffle = false,
  });
  Future<void> open(
    List<int> trackIds, {
    int? index,
    bool play = true,
    bool shuffle = false,
  });
  Future<void> insertNext(int trackId);
  Future<void> append(List<int> trackIds);
  Future<void> skipToIndex(int index);
  Future<void> setShuffle(bool enabled);
  Future<void> setLoopMode(Loop mode);
  Future<void> removeQueueItem(int index);
  Future<void> reorderQueue(int oldIndex, int newIndex);
  Future<void> clearQueue();
  Future<PlaybackState> getPlaybackState();
  Future<void> setCrossfadeDuration(Duration duration);
  Future<void> setCrossfadeCurve(CrossfadeCurve curve);
  Future<void> setCrossfadeConfig(CrossfadeConfig config);
  Future<void> setInfiniteMix(bool enabled);

  // --- Library & Catalog ---
  Future<CatalogSnapshot> getCatalogSnapshot();
  Future<List<Track>> getTracks({TrackSortOption? sort, bool ascending = true});
  Future<List<Album>> getAlbums();
  Future<List<Artist>> getArtists();
  Future<List<Genre>> getGenres();
  Future<List<Track>> getAlbumTracks(int albumId);
  Future<List<Track>> getArtistTracks(int artistId);
  Future<void> startScan(String directoryPath);
  Future<void> startScanDirectories(List<String> directories);
  Future<void> cancelScan();
  Future<void> deleteTrack(int trackId);

  // --- Metadata (Worker Isolates) ---
  Future<ExtractedTrackData?> getMetadata(String filePath);

  // --- Playlists ---
  Future<int> createPlaylist(String name);
  Future<void> deletePlaylist(int playlistId);
  Future<void> renamePlaylist(int playlistId, String name);
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds);
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId);
  Future<void> reorderPlaylistTracks(
    int playlistId,
    int oldIndex,
    int newIndex,
  );
  Future<bool> toggleLikeTrack(int trackId, [String? filePath]);
  Future<void> clearHistory();

  // --- Lyrics ---
  Future<LyricsResult?> resolveLyrics({
    required int trackId,
    required String filePath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    bool allowRemote = true,
    bool bypassCache = false,
    Set<LyricsSource>? allowedSources,
    LyricsCancellationToken? cancellationToken,
    void Function(int seconds)? onThresholdCountdown,
  });
  Future<List<String>?> translateLyrics({
    required int lyricsId,
    required String targetLang,
    String? sourceLang,
    required List<String> rawLines,
  });

  Future<void> dispose();
}

/// Production implementation of [TachyonBackendClient] communicating with
/// the Core Service Isolate over typed [SendPort] / [ReceivePort] RPC.
class TachyonIsolateBackendClient implements TachyonBackendClient {
  final ReceivePort _uiReceivePort = ReceivePort();
  SendPort? _hostSendPort;
  Isolate? _hostIsolate;

  final Completer<void> _initCompleter = Completer<void>();
  final Map<int, Completer<dynamic>> _pendingRequests = {};
  int _nextRequestId = 1;

  final StreamController<PlaybackState> _playbackStateController =
      StreamController<PlaybackState>.broadcast();
  final StreamController<Duration> _positionController =
      StreamController<Duration>.broadcast();
  final StreamController<List<double>> _visualizerController =
      StreamController<List<double>>.broadcast();
  final StreamController<List<AudioDevice>> _devicesController =
      StreamController<List<AudioDevice>>.broadcast();
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast();
  final StreamController<void> _catalogUpdatedController =
      StreamController<void>.broadcast();

  @override
  Stream<PlaybackState> get playbackStateStream =>
      _playbackStateController.stream;

  @override
  Stream<Duration> get positionStream => _positionController.stream;

  @override
  Stream<List<double>> get visualizerStream => _visualizerController.stream;

  @override
  Stream<List<AudioDevice>> get devicesStream => _devicesController.stream;

  @override
  Stream<ScanProgress> get scanProgressStream => _scanProgressController.stream;

  @override
  Stream<void> get catalogUpdatedStream => _catalogUpdatedController.stream;

  /// Spawns and connects to the Core Service Isolate.
  Future<void> initialize({
    required String dbPath,
    required String cacheDirPath,
  }) async {
    _uiReceivePort.listen(_handleIncomingMessage);

    final config = CoreInitConfig(
      uiSendPort: _uiReceivePort.sendPort,
      dbPath: dbPath,
      cacheDirPath: cacheDirPath,
    );

    _hostIsolate = await Isolate.spawn(
      coreBackendEntryPoint,
      config,
      debugName: 'TachyonCoreServiceIsolate',
    );

    return _initCompleter.future;
  }

  void _handleIncomingMessage(dynamic message) {
    if (message is SendPort) {
      _hostSendPort = message;
      if (!_initCompleter.isCompleted) {
        _initCompleter.complete();
      }
      return;
    }

    if (message is BackendResponse) {
      final completer = _pendingRequests.remove(message.requestId);
      if (completer != null) {
        if (message.isSuccess) {
          completer.complete(message.data);
        } else {
          completer.completeError(Exception(message.error));
        }
      }
      return;
    }

    if (message is BackendEvent) {
      _routeEvent(message);
      return;
    }
  }

  void _routeEvent(BackendEvent event) {
    switch (event.topic) {
      case BackendTopics.playbackState:
        if (event.payload is PlaybackState) {
          _playbackStateController.add(event.payload as PlaybackState);
        }
        break;

      case BackendTopics.playbackPosition:
        if (event.payload is int) {
          _positionController.add(Duration(milliseconds: event.payload as int));
        }
        break;

      case BackendTopics.playbackVisualizer:
        if (event.payload is List) {
          final list = (event.payload as List).cast<double>();
          _visualizerController.add(list);
        }
        break;

      case BackendTopics.playbackDevices:
        if (event.payload is List) {
          _devicesController.add((event.payload as List).cast<AudioDevice>());
        }
        break;

      case BackendTopics.libraryScanProgress:
        if (event.payload is ScanProgress) {
          _scanProgressController.add(event.payload as ScanProgress);
        } else if (event.payload is Map<String, dynamic>) {
          _scanProgressController.add(
            ScanProgress.fromJson(event.payload as Map<String, dynamic>),
          );
        } else if (event.payload is Map) {
          _scanProgressController.add(
            ScanProgress.fromJson(
              (event.payload as Map).cast<String, dynamic>(),
            ),
          );
        }
        break;

      case BackendTopics.catalogUpdated:
        _catalogUpdatedController.add(null);
        break;
    }
  }

  Future<T> _send<T>(
    String method, [
    Map<String, dynamic> params = const {},
  ]) async {
    if (_hostSendPort == null) {
      await _initCompleter.future;
    }

    final id = _nextRequestId++;
    final completer = Completer<T>();
    _pendingRequests[id] = completer;

    _hostSendPort!.send(
      BackendRequest(requestId: id, method: method, params: params),
    );

    return completer.future;
  }

  // ===========================================================================
  // PLAYBACK
  // ===========================================================================
  @override
  Future<void> play() => _send(BackendMethods.playbackPlay);

  @override
  Future<void> pause() => _send(BackendMethods.playbackPause);

  @override
  Future<void> stop() => _send(BackendMethods.playbackStop);

  @override
  Future<void> seek(Duration position) => _send(BackendMethods.playbackSeek, {
    'positionMs': position.inMilliseconds,
  });

  @override
  Future<void> next() => _send(BackendMethods.playbackNext);

  @override
  Future<void> previous() => _send(BackendMethods.playbackPrevious);

  @override
  Future<void> setVolume(double volume) =>
      _send(BackendMethods.playbackSetVolume, {'volume': volume});

  @override
  Future<void> setRate(double rate) =>
      _send(BackendMethods.playbackSetRate, {'rate': rate});

  @override
  Future<void> setPitch(double pitch) =>
      _send(BackendMethods.playbackSetPitch, {'pitch': pitch});

  @override
  Future<void> setSkipSilence(bool enabled) =>
      _send(BackendMethods.playbackSetSkipSilence, {'enabled': enabled});

  @override
  Future<void> setVolumeNormalization(bool enabled) =>
      _send(BackendMethods.playbackSetVolumeNormalization, {'enabled': enabled});

  @override
  Future<void> setPreamp(double preampDb) =>
      _send(BackendMethods.playbackSetPreamp, {'preampDb': preampDb});

  @override
  Future<void> setBalance(double balance) =>
      _send(BackendMethods.playbackSetBalance, {'balance': balance});

  @override
  Future<void> setMono(bool enabled) =>
      _send(BackendMethods.playbackSetMono, {'enabled': enabled});

  @override
  Future<void> setCrossfeed(CrossfeedMode mode) =>
      _send(BackendMethods.playbackSetCrossfeed, {'mode': mode.index});

  @override
  Future<void> setSpatializer(double width) =>
      _send(BackendMethods.playbackSetSpatializer, {'width': width});

  @override
  Future<void> setLimiter(bool enabled) =>
      _send(BackendMethods.playbackSetLimiter, {'enabled': enabled});

  @override
  Future<void> setEqualizer(Equalizer equalizer) =>
      _send(BackendMethods.playbackSetEqualizer, {'gains': equalizer.toList()});

  @override
  Future<void> setOutputDevice(AudioDevice device) =>
      _send(BackendMethods.playbackSetOutputDevice, {'device': device});

  @override
  Future<List<AudioDevice>> getAudioDevices() async {
    final result = await _send<List<dynamic>>(
      BackendMethods.playbackGetAudioDevices,
    );
    return result.cast<AudioDevice>();
  }

  @override
  Future<void> playTrack(int trackId, {bool play = true}) => _send(
    BackendMethods.playbackPlayTrack,
    {'trackId': trackId, 'play': play},
  );

  @override
  Future<void> playQueue(
    List<int> trackIds, {
    int? startIndex,
    bool play = true,
    bool shuffle = false,
  }) => _send(BackendMethods.playbackPlayQueue, {
    'trackIds': trackIds,
    'startIndex': startIndex,
    'play': play,
    'shuffle': shuffle,
  });

  @override
  Future<void> open(
    List<int> trackIds, {
    int? index,
    bool play = true,
    bool shuffle = false,
  }) => _send(BackendMethods.playbackOpen, {
    'trackIds': trackIds,
    'index': index,
    'play': play,
    'shuffle': shuffle,
  });

  @override
  Future<void> insertNext(int trackId) =>
      _send(BackendMethods.playbackInsertNext, {'trackId': trackId});

  @override
  Future<void> append(List<int> trackIds) =>
      _send(BackendMethods.playbackAppend, {'trackIds': trackIds});

  @override
  Future<void> skipToIndex(int index) =>
      _send(BackendMethods.playbackSkipToIndex, {'index': index});

  @override
  Future<void> setShuffle(bool enabled) =>
      _send(BackendMethods.playbackSetShuffle, {'enabled': enabled});

  @override
  Future<void> setLoopMode(Loop mode) =>
      _send(BackendMethods.playbackSetLoopMode, {'loopMode': mode.index});

  @override
  Future<void> removeQueueItem(int index) =>
      _send(BackendMethods.playbackRemoveQueueItem, {'index': index});

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) => _send(
    BackendMethods.playbackReorderQueue,
    {'oldIndex': oldIndex, 'newIndex': newIndex},
  );

  @override
  Future<void> clearQueue() => _send(BackendMethods.playbackClearQueue);

  @override
  Future<PlaybackState> getPlaybackState() =>
      _send<PlaybackState>(BackendMethods.playbackGetState);

  @override
  Future<void> setCrossfadeDuration(Duration duration) => _send(
    BackendMethods.playbackSetCrossfadeDuration,
    {'durationMs': duration.inMilliseconds},
  );

  @override
  Future<void> setCrossfadeCurve(CrossfadeCurve curve) =>
      _send(BackendMethods.playbackSetCrossfadeCurve, {'curve': curve.index});

  @override
  Future<void> setCrossfadeConfig(CrossfadeConfig config) =>
      _send(BackendMethods.playbackSetCrossfadeConfig, {'config': config});

  @override
  Future<void> setVisualizerEnabled(bool enabled) =>
      _send(BackendMethods.playbackSetVisualizerEnabled, {'enabled': enabled});

  @override
  Future<void> setInfiniteMix(bool enabled) =>
      _send(BackendMethods.playbackSetInfiniteMix, {'enabled': enabled});

  // ===========================================================================
  // LIBRARY & CATALOG
  // ===========================================================================
  @override
  Future<CatalogSnapshot> getCatalogSnapshot() async {
    final result = await _send<dynamic>(
      BackendMethods.libraryGetCatalogSnapshot,
    );
    return result as CatalogSnapshot;
  }

  @override
  Future<List<Track>> getTracks({
    TrackSortOption? sort,
    bool ascending = true,
  }) async {
    final result = await _send<List<dynamic>>(BackendMethods.libraryGetTracks, {
      'sort': sort,
      'ascending': ascending,
    });
    return result.cast<Track>();
  }

  @override
  Future<List<Album>> getAlbums() async {
    final result = await _send<List<dynamic>>(BackendMethods.libraryGetAlbums);
    return result.cast<Album>();
  }

  @override
  Future<List<Artist>> getArtists() async {
    final result = await _send<List<dynamic>>(BackendMethods.libraryGetArtists);
    return result.cast<Artist>();
  }

  @override
  Future<List<Genre>> getGenres() async {
    final result = await _send<List<dynamic>>(BackendMethods.libraryGetGenres);
    return result.cast<Genre>();
  }

  @override
  Future<List<Track>> getAlbumTracks(int albumId) async {
    final result = await _send<List<dynamic>>(
      BackendMethods.libraryGetAlbumTracks,
      {'albumId': albumId},
    );
    return result.cast<Track>();
  }

  @override
  Future<List<Track>> getArtistTracks(int artistId) async {
    final result = await _send<List<dynamic>>(
      BackendMethods.libraryGetArtistTracks,
      {'artistId': artistId},
    );
    return result.cast<Track>();
  }

  @override
  Future<void> startScan(String directoryPath) =>
      _send(BackendMethods.libraryStartScan, {'directoryPath': directoryPath});

  @override
  Future<void> cancelScan() => _send(BackendMethods.libraryCancelScan);

  @override
  Future<void> deleteTrack(int trackId) =>
      _send(BackendMethods.libraryDeleteTrack, {'trackId': trackId});

  @override
  Future<void> startScanDirectories(List<String> directories) =>
      _send(BackendMethods.libraryStartScan, {'directories': directories});

  // ===========================================================================
  // METADATA (WORKER ISOLATES)
  // ===========================================================================
  @override
  Future<ExtractedTrackData?> getMetadata(String filePath) =>
      _send<ExtractedTrackData?>(BackendMethods.metadataGetMetadata, {
        'filePath': filePath,
      });

  // ===========================================================================
  // PLAYLISTS
  // ===========================================================================
  @override
  Future<int> createPlaylist(String name) =>
      _send<int>(BackendMethods.playlistsCreate, {'name': name});

  @override
  Future<void> deletePlaylist(int playlistId) =>
      _send(BackendMethods.playlistsDelete, {'playlistId': playlistId});

  @override
  Future<void> renamePlaylist(int playlistId, String name) => _send(
    BackendMethods.playlistsRename,
    {'playlistId': playlistId, 'name': name},
  );

  @override
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) => _send(
    BackendMethods.playlistsAddTracks,
    {'playlistId': playlistId, 'trackIds': trackIds},
  );

  @override
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) => _send(
    BackendMethods.playlistsRemoveTrack,
    {'playlistId': playlistId, 'trackId': trackId},
  );

  @override
  Future<void> reorderPlaylistTracks(
    int playlistId,
    int oldIndex,
    int newIndex,
  ) => _send(BackendMethods.playlistsReorderTracks, {
    'playlistId': playlistId,
    'oldIndex': oldIndex,
    'newIndex': newIndex,
  });

  @override
  Future<bool> toggleLikeTrack(int trackId, [String? filePath]) async {
    final res = await _send<dynamic>(BackendMethods.playlistsToggleLike, {
      'trackId': trackId,
      'filePath': filePath,
    });
    return res as bool? ?? false;
  }

  @override
  Future<void> clearHistory() => _send(BackendMethods.playlistsClearHistory);

  // ===========================================================================
  // LYRICS
  // ===========================================================================
  @override
  Future<LyricsResult?> resolveLyrics({
    required int trackId,
    required String filePath,
    String? title,
    String? artist,
    String? album,
    int? durationMs,
    bool allowRemote = true,
    bool bypassCache = false,
    Set<LyricsSource>? allowedSources,
    LyricsCancellationToken? cancellationToken,
    void Function(int seconds)? onThresholdCountdown,
  }) async {
    final res = await _send<dynamic>(BackendMethods.lyricsResolve, {
      'trackId': trackId,
      'filePath': filePath,
      'title': title,
      'artist': artist,
      'album': album,
      'durationMs': durationMs,
      'allowRemote': allowRemote,
      'bypassCache': bypassCache,
      'allowedSources': allowedSources?.map((s) => s.dbValue).toList(),
    });
    if (res == null) return null;
    if (res is LyricsResult) return res;
    if (res is Map) {
      final map = Map<String, dynamic>.from(res);
      final retryAfter = map['retryAfterSeconds'] as int?;
      if (retryAfter != null) {
        onThresholdCountdown?.call(retryAfter);
        return null;
      }
      return LyricsResult.fromMap(map);
    }
    return null;
  }

  @override
  Future<List<String>?> translateLyrics({
    required int lyricsId,
    required String targetLang,
    String? sourceLang,
    required List<String> rawLines,
  }) async {
    final res = await _send<dynamic>(BackendMethods.lyricsTranslate, {
      'lyricsId': lyricsId,
      'lang': targetLang,
      'sourceLang': ?sourceLang,
      'rawLines': rawLines,
    });
    if (res == null) return null;
    if (res is List) return res.cast<String>();
    if (res is Map) {
      if (res['error'] == 'rate_limit') {
        throw LyricsTranslationException(
          res['message'] as String? ??
              'Rate limit exceeded (Too many requests)',
          statusCode: res['statusCode'] as int? ?? 429,
        );
      }
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    _uiReceivePort.close();
    await _playbackStateController.close();
    await _positionController.close();
    await _devicesController.close();
    await _scanProgressController.close();
    await _catalogUpdatedController.close();
    _hostIsolate?.kill(priority: Isolate.immediate);
    _hostIsolate = null;
  }
}
