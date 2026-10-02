import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:miniaudio_player/miniaudio_player.dart';

import 'package:tachyon/core/backend/backend_protocol.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/core/backend/services/audio_engine_service.dart';
import 'package:tachyon/core/backend/services/audio_player_adapter.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/core/backend/services/queue_manager.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart' show CrossfadeCurve;

/// Configuration passed from the UI Isolate when spawning the Core Service Isolate.
class CoreInitConfig {
  final SendPort uiSendPort;
  final String dbPath;
  final String cacheDirPath;

  CoreInitConfig({
    required this.uiSendPort,
    required this.dbPath,
    required this.cacheDirPath,
  });
}

/// Entry point function for [Isolate.spawn] to start the Core Service Isolate.
Future<void> coreBackendEntryPoint(CoreInitConfig config) async {
  final host = TachyonBackendHost(config);
  await host.start();
}

/// The Core Service Isolate backend host.
/// Runs in a background isolate and orchestrates SQLite, audio playback,
/// lyrics resolution, and metadata coordination.
class TachyonBackendHost {
  final CoreInitConfig config;

  late final ReceivePort _hostReceivePort;
  late final AppDatabase _database;
  late final CoverCacheService _coverCache;
  late final MetadataService _metadataService;
  late final QueueManager _queueManager;
  late final AudioEngineService _audioEngine;
  late final LyricsService _lyricsService;

  final List<StreamSubscription> _subscriptions = [];
  StreamSubscription<ScanProgress>? _scanSubscription;
  int _lastEmittedPositionMs = -1;
  int _lastPositionEmitTimestamp = 0;

  TachyonBackendHost(this.config);

  Future<void> start() async {
    _hostReceivePort = ReceivePort();

    // 1. Initialize audio adapter bindings in the isolate
    await AudioPlayerAdapter.ensureInitialized();

    // 2. Initialize database
    _database = AppDatabase();
    await _database.init(config.dbPath);

    // 3. Initialize cover cache and metadata service
    _coverCache = CoverCacheService(cacheDirectory: Directory(config.cacheDirPath));
    _metadataService = MetadataService(
      database: _database,
      coverCacheService: _coverCache,
    );

    // 4. Initialize playback engine
    _queueManager = QueueManager();
    _audioEngine = AudioEngineService(queueManager: _queueManager);

    // 5. Initialize lyrics service
    _lyricsService = LyricsService(database: _database);

    // 6. Set up event forwarding to the UI isolate
    _subscriptions.add(
      _audioEngine.stateStream.listen((state) {
        config.uiSendPort.send(BackendEvent(
          topic: BackendTopics.playbackState,
          payload: state,
        ));
      }),
    );

    // Throttled position updates (max ~25Hz) to keep UI isolate completely smooth
    _subscriptions.add(
      _audioEngine.positionStream.listen((pos) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final deltaMs = now - _lastPositionEmitTimestamp;
        if (deltaMs >= 40 || (pos.inMilliseconds - _lastEmittedPositionMs).abs() > 1000) {
          _lastPositionEmitTimestamp = now;
          _lastEmittedPositionMs = pos.inMilliseconds;
          config.uiSendPort.send(BackendEvent(
            topic: BackendTopics.playbackPosition,
            payload: pos.inMilliseconds,
          ));
        }
      }),
    );

    // 7. Send the host SendPort to the UI isolate so it can start sending requests
    config.uiSendPort.send(_hostReceivePort.sendPort);

    // 8. Listen for incoming requests from the UI isolate
    _hostReceivePort.listen(_onRequestReceived);
  }

  Future<void> _onRequestReceived(dynamic message) async {
    if (message is! BackendRequest) return;

    try {
      final result = await _dispatch(message.method, message.params);
      config.uiSendPort.send(BackendResponse(
        requestId: message.requestId,
        data: result,
      ));
    } catch (e, stack) {
      debugPrint('[CoreBackendHost] Error handling request ${message.method}: $e\n$stack');
      config.uiSendPort.send(BackendResponse(
        requestId: message.requestId,
        error: e.toString(),
      ));
    }
  }

  Future<dynamic> _dispatch(String method, Map<String, dynamic> params) async {
    switch (method) {
      // =======================================================================
      // PLAYBACK COMMANDS
      // =======================================================================
      case BackendMethods.playbackPlay:
        await _audioEngine.play();
        return null;

      case BackendMethods.playbackPause:
        await _audioEngine.pause();
        return null;

      case BackendMethods.playbackStop:
        await _audioEngine.stop();
        return null;

      case BackendMethods.playbackSeek:
        final ms = params['positionMs'] as int;
        await _audioEngine.seek(Duration(milliseconds: ms));
        return null;

      case BackendMethods.playbackNext:
        await _audioEngine.next();
        return null;

      case BackendMethods.playbackPrevious:
        await _audioEngine.previous();
        return null;

      case BackendMethods.playbackSetVolume:
        final volume = (params['volume'] as num).toDouble();
        await _audioEngine.setVolume(volume);
        return null;

      case BackendMethods.playbackSetEqualizer:
        final gains = (params['gains'] as List).cast<double>();
        await _audioEngine.setEqualizer(Equalizer.fromList(gains));
        return null;

      case BackendMethods.playbackSetOutputDevice:
        final device = params['device'] as AudioDevice;
        await _audioEngine.setDevice(device);
        return null;

      case BackendMethods.playbackGetAudioDevices:
        return await _audioEngine.getAudioDevices();

      case BackendMethods.playbackPlayTrack:
        final track = params['track'] as Track;
        final autoPlay = params['play'] as bool? ?? true;
        await _audioEngine.open([QueueItem.fromTrack(track)], play: autoPlay);
        return null;

      case BackendMethods.playbackPlayQueue:
        final tracks = (params['tracks'] as List).cast<Track>();
        final startIndex = params['startIndex'] as int? ?? 0;
        final autoPlay = params['play'] as bool? ?? true;
        final queueItems = tracks.map((t) => QueueItem.fromTrack(t)).toList();
        await _audioEngine.open(queueItems, index: startIndex, play: autoPlay);
        return null;

      case BackendMethods.playbackSetShuffle:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setShuffle(enabled);
        return null;

      case BackendMethods.playbackSetLoopMode:
        final modeIndex = params['loopMode'] as int;
        await _audioEngine.setLoopMode(Loop.values[modeIndex]);
        return null;

      case BackendMethods.playbackRemoveQueueItem:
        final index = params['index'] as int;
        await _audioEngine.remove(index);
        return null;

      case BackendMethods.playbackReorderQueue:
        final oldIndex = params['oldIndex'] as int;
        final newIndex = params['newIndex'] as int;
        await _audioEngine.reorder(oldIndex, newIndex);
        return null;

      case BackendMethods.playbackClearQueue:
        await _audioEngine.clearQueue();
        return null;

      case BackendMethods.playbackGetState:
        return _audioEngine.state;

      case BackendMethods.playbackSetCrossfadeDuration:
        final durationMs = params['durationMs'] as int;
        await _audioEngine.setCrossfadeDuration(Duration(milliseconds: durationMs));
        return null;

      case BackendMethods.playbackSetCrossfadeCurve:
        final curveIndex = params['curve'] as int;
        await _audioEngine.setCrossfadeCurve(CrossfadeCurve.values[curveIndex]);
        return null;

      case BackendMethods.playbackOpen:
        final items = (params['items'] as List).cast<QueueItem>();
        final index = params['index'] as int? ?? 0;
        final autoPlay = params['play'] as bool? ?? true;
        final shuffle = params['shuffle'] as bool? ?? false;
        await _audioEngine.open(items, index: index, play: autoPlay, shuffle: shuffle);
        return null;

      case BackendMethods.playbackInsertNext:
        final item = params['item'] as QueueItem;
        await _audioEngine.insertNext(item);
        return null;

      case BackendMethods.playbackAppend:
        final items = (params['items'] as List).cast<QueueItem>();
        await _audioEngine.append(items);
        return null;

      case BackendMethods.playbackSkipToIndex:
        final index = params['index'] as int;
        await _audioEngine.skipToIndex(index);
        return null;

      case BackendMethods.playbackSetRate:
        final rate = (params['rate'] as num).toDouble();
        await _audioEngine.setRate(rate);
        return null;

      case BackendMethods.playbackSetPitch:
        final pitch = (params['pitch'] as num).toDouble();
        await _audioEngine.setPitch(pitch);
        return null;

      case BackendMethods.playbackSetSkipSilence:
        final enabled = params['enabled'] as bool;
        await _audioEngine.setSkipSilence(enabled);
        return null;

      case BackendMethods.playbackSetCrossfadeConfig:
        final config = params['config'] as CrossfadeConfig;
        await _audioEngine.setCrossfadeConfig(config);
        return null;

      case BackendMethods.playbackSetInfiniteMix:
        final enabled = params['enabled'] as bool;
        _audioEngine.queueManager.setInfiniteMix(enabled);
        return null;

      // =======================================================================
      // LIBRARY & CATALOG
      // =======================================================================
      case BackendMethods.libraryGetTracks:
        final sort = params['sort'] as TrackSortOption?;
        final asc = params['ascending'] as bool? ?? true;
        return await _database.getAllTracks(sortBy: sort?.name, ascending: asc);

      case BackendMethods.libraryGetAlbums:
        return await _database.getAllAlbums();

      case BackendMethods.libraryGetArtists:
        return await _database.getAllArtists();

      case BackendMethods.libraryGetGenres:
        return await _database.getAllGenres();

      case BackendMethods.libraryGetAlbumTracks:
        final albumId = params['albumId'] as int;
        return await _database.getTracksByAlbumId(albumId);

      case BackendMethods.libraryGetArtistTracks:
        final artistId = params['artistId'] as int;
        return await _database.getTracksByArtistId(artistId);

      case BackendMethods.libraryStartScan:
        final directories = params['directories'] != null
            ? (params['directories'] as List).cast<String>()
            : [params['directoryPath'] as String];
        await _scanSubscription?.cancel();
        _scanSubscription = _metadataService.scanDirectories(directories).listen((progress) {
          config.uiSendPort.send(BackendEvent(
            topic: BackendTopics.libraryScanProgress,
            payload: progress,
          ));
        });
        return null;

      case BackendMethods.libraryCancelScan:
        await _scanSubscription?.cancel();
        _metadataService.cancelScan();
        return null;

      case BackendMethods.libraryDeleteTrack:
        final trackId = params['trackId'] as int;
        await _database.deleteTrack(trackId);
        return null;

      case BackendMethods.libraryDeleteTracksInFolder:
        final folderPath = params['folderPath'] as String;
        await _database.deleteTracksInFolder(folderPath);
        return null;

      // =======================================================================
      // METADATA & THUMBNAILS (WORKER ISOLATES)
      // =======================================================================
      case BackendMethods.metadataGetMetadata:
        final filePath = params['filePath'] as String;
        return await _metadataService.getMetadata(filePath);

      case BackendMethods.metadataGetThumbnail:
        final filePath = params['filePath'] as String;
        final isHighQuality = params['isHighQuality'] as bool? ?? false;
        return await _metadataService.getThumbnail(filePath, isHighQuality: isHighQuality);

      case BackendMethods.metadataGetArtistCover:
        final artistName = params['artistName'] as String;
        final isHighQuality = params['isHighQuality'] as bool? ?? false;
        return await _metadataService.getArtistCover(artistName, isHighQuality: isHighQuality);

      case BackendMethods.metadataClearCoverCache:
        await _metadataService.clearCoverCache();
        return null;

      // =======================================================================
      // PLAYLISTS
      // =======================================================================
      case BackendMethods.playlistsGetAll:
        return await _database.getAllPlaylists();

      case BackendMethods.playlistsCreate:
        final name = params['name'] as String;
        return await _database.createPlaylist(name);

      case BackendMethods.playlistsDelete:
        final playlistId = params['playlistId'] as int;
        await _database.deletePlaylist(playlistId);
        return null;

      case BackendMethods.playlistsRename:
        final playlistId = params['playlistId'] as int;
        final name = params['name'] as String;
        await _database.renamePlaylist(playlistId, name);
        return null;

      case BackendMethods.playlistsGetTracks:
        final playlistId = params['playlistId'] as int;
        return await _database.getTracksForPlaylist(playlistId);

      case BackendMethods.playlistsAddTracks:
        final playlistId = params['playlistId'] as int;
        final trackIds = (params['trackIds'] as List).cast<int>();
        await _database.addTracksToPlaylist(playlistId, trackIds);
        return null;

      case BackendMethods.playlistsRemoveTrack:
        final playlistId = params['playlistId'] as int;
        final trackId = params['trackId'] as int;
        await _database.removeTrackFromPlaylist(playlistId, trackId);
        return null;

      case BackendMethods.playlistsReorderTracks:
        final playlistId = params['playlistId'] as int;
        final oldIndex = params['oldIndex'] as int;
        final newIndex = params['newIndex'] as int;
        await _database.reorderPlaylistEntries(playlistId, oldIndex, newIndex);
        return null;

      case BackendMethods.playlistsGetTrackIds:
        final playlistId = params['playlistId'] as int;
        final trackIds = await _database.getTrackIdsForPlaylist(playlistId);
        return trackIds.toList();

      case BackendMethods.playlistsToggleLike:
        final trackId = params['trackId'] as int;
        final filePath = params['filePath'] as String?;
        await _database.toggleLikeTrack(trackId, filePath);
        return await _database.isTrackLiked(trackId);

      case BackendMethods.playlistsIsLiked:
        final trackId = params['trackId'] as int;
        return await _database.isTrackLiked(trackId);

      case BackendMethods.playlistsClearHistory:
        await _database.clearHistory();
        return null;

      // =======================================================================
      // SEARCH
      // =======================================================================
      case BackendMethods.searchQuery:
        final query = params['query'] as String;
        final tracks = await _database.searchTracks(query);
        final albums = await _database.searchAlbums(query);
        final artists = await _database.searchArtists(query);
        return {
          'tracks': tracks,
          'albums': albums,
          'artists': artists,
        };

      // =======================================================================
      // LYRICS
      // =======================================================================
      case BackendMethods.lyricsResolve:
        final track = params['track'] as Track;
        final allowRemote = params['allowRemote'] as bool? ?? false;
        final bypassCache = params['bypassCache'] as bool? ?? false;
        final allowedSources = params['allowedSources'] as Set<LyricsSource>?;
        return await _lyricsService.resolveLyricsForTrack(
          track,
          allowRemote: allowRemote,
          forceRefresh: bypassCache,
          enabledSources: allowedSources,
        );

      case BackendMethods.lyricsTranslate:
        final keyHash = params['keyHash'] as String;
        final source = params['source'] as LyricsSource;
        final targetLang = params['targetLang'] as String;
        final rawLines = (params['rawLines'] as List).cast<String>();

        // Check SQLite cache first
        final cached = await _database.getLyricsTranslation(
          keyHash: keyHash,
          source: source.dbValue,
          targetLang: targetLang,
        );
        if (cached != null && cached.isNotEmpty) {
          return cached.join('\n');
        }

        // Cache miss: call translation client
        final client = LyricsTranslationClient();
        final translationResult = await client.translate(
          rawLines,
          targetLanguage: targetLang,
        );

        if (translationResult.isSuccess) {
          final translatedLines = translationResult.translatedLines;
          await _database.saveLyricsTranslation(
            keyHash: keyHash,
            source: source.dbValue,
            targetLang: targetLang,
            translatedLines: translatedLines,
          );
          return translatedLines.join('\n');
        }

        return null;

      default:
        throw UnimplementedError('Backend method not recognized: $method');
    }
  }

  Future<void> dispose() async {
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    _subscriptions.clear();
    await _scanSubscription?.cancel();
    _metadataService.cancelScan();
    _hostReceivePort.close();
    await _audioEngine.dispose();
    await _database.close();
  }
}
