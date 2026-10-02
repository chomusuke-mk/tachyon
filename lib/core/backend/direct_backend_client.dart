import 'dart:async';

import 'package:miniaudio_player/miniaudio_player.dart';

import 'package:tachyon/core/backend/backend_client.dart';
import 'package:tachyon/core/database/app_database.dart';
import 'package:tachyon/core/network/lyrics_rate_limiter.dart';
import 'package:tachyon/core/network/lyrics_translation_client.dart';
import 'package:tachyon/core/backend/services/audio_engine_service.dart';
import 'package:tachyon/core/backend/services/cover_cache_service.dart';
import 'package:tachyon/core/backend/services/lyrics_service.dart';
import 'package:tachyon/core/backend/services/metadata_service.dart';
import 'package:tachyon/features/library/domain/album.dart';
import 'package:tachyon/features/library/domain/artist.dart';
import 'package:tachyon/features/library/domain/genre.dart';
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/scan_progress.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/library/domain/track_sort_option.dart';
import 'package:tachyon/features/playback/domain/crossfade_config.dart';
import 'package:tachyon/features/playback/domain/lyric_source.dart';
import 'package:tachyon/features/playback/domain/playback_state.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';
import 'package:tachyon/features/settings/data/settings_repository.dart'
    show CrossfadeCurve;

/// In-process direct implementation of [TachyonBackendClient].
/// Useful for unit testing and test suites where spawning a background isolate
/// is not necessary.
class DirectTachyonBackendClient implements TachyonBackendClient {
  final AudioEngineService? audioEngine;
  final AppDatabase? database;
  final MetadataService? metadataService;
  final CoverCacheService? coverCacheService;
  final LyricsService? lyricsService;
  final LyricsTranslationClient _translationClient;

  final StreamController<List<AudioDevice>> _devicesController =
      StreamController<List<AudioDevice>>.broadcast();
  final StreamController<ScanProgress> _scanProgressController =
      StreamController<ScanProgress>.broadcast();
  StreamSubscription<ScanProgress>? _scanSubscription;

  DirectTachyonBackendClient({
    this.audioEngine,
    this.database,
    this.metadataService,
    this.coverCacheService,
    this.lyricsService,
    LyricsTranslationClient? translationClient,
  }) : _translationClient = translationClient ?? LyricsTranslationClient();

  @override
  Stream<PlaybackState> get playbackStateStream {
    try {
      return audioEngine?.stateStream ?? const Stream.empty();
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Stream<Duration> get positionStream {
    try {
      return audioEngine?.positionStream ?? const Stream.empty();
    } catch (_) {
      return const Stream.empty();
    }
  }

  @override
  Stream<List<AudioDevice>> get devicesStream => _devicesController.stream;

  @override
  Stream<ScanProgress> get scanProgressStream => _scanProgressController.stream;

  @override
  Future<void> play() async => await audioEngine?.play();

  @override
  Future<void> pause() async => await audioEngine?.pause();

  @override
  Future<void> stop() async => await audioEngine?.stop();

  @override
  Future<void> seek(Duration position) async =>
      await audioEngine?.seek(position);

  @override
  Future<void> next() async => await audioEngine?.next();

  @override
  Future<void> previous() async => await audioEngine?.previous();

  @override
  Future<void> setVolume(double volume) async =>
      await audioEngine?.setVolume(volume);

  @override
  Future<void> setRate(double rate) async => await audioEngine?.setRate(rate);

  @override
  Future<void> setPitch(double pitch) async =>
      await audioEngine?.setPitch(pitch);

  @override
  Future<void> setSkipSilence(bool enabled) async =>
      await audioEngine?.setSkipSilence(enabled);

  @override
  Future<void> setEqualizer(Equalizer equalizer) async =>
      await audioEngine?.setEqualizer(equalizer);

  @override
  Future<void> setOutputDevice(AudioDevice device) async =>
      await audioEngine?.setDevice(device);

  @override
  Future<List<AudioDevice>> getAudioDevices() async =>
      await audioEngine?.getAudioDevices() ?? const [];

  @override
  Future<void> playTrack(Track track, {bool play = true}) async {
    await audioEngine?.open([QueueItem.fromTrack(track)], play: play);
  }

  @override
  Future<void> playQueue(
    List<Track> tracks, {
    int startIndex = 0,
    bool play = true,
  }) async {
    final queueItems = tracks.map((t) => QueueItem.fromTrack(t)).toList();
    await audioEngine?.open(queueItems, index: startIndex, play: play);
  }

  @override
  Future<void> open(
    List<QueueItem> items, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    await audioEngine?.open(items, index: index, play: play, shuffle: shuffle);
  }

  @override
  Future<void> insertNext(QueueItem item) async =>
      await audioEngine?.insertNext(item);

  @override
  Future<void> append(List<QueueItem> items) async =>
      await audioEngine?.append(items);

  @override
  Future<void> skipToIndex(int index) async =>
      await audioEngine?.skipToIndex(index);

  @override
  Future<void> setShuffle(bool enabled) async =>
      await audioEngine?.setShuffle(enabled);

  @override
  Future<void> setLoopMode(Loop mode) async =>
      await audioEngine?.setLoopMode(mode);

  @override
  Future<void> removeQueueItem(int index) async =>
      await audioEngine?.remove(index);

  @override
  Future<void> reorderQueue(int oldIndex, int newIndex) async =>
      await audioEngine?.reorder(oldIndex, newIndex);

  @override
  Future<void> clearQueue() async => await audioEngine?.clearQueue();

  @override
  Future<PlaybackState> getPlaybackState() async =>
      audioEngine?.state ?? const PlaybackState.initial();

  @override
  Future<void> setCrossfadeDuration(Duration duration) async =>
      await audioEngine?.setCrossfadeDuration(duration);

  @override
  Future<void> setCrossfadeCurve(CrossfadeCurve curve) async =>
      await audioEngine?.setCrossfadeCurve(curve);

  @override
  Future<void> setCrossfadeConfig(CrossfadeConfig config) async =>
      await audioEngine?.setCrossfadeConfig(config);

  @override
  Future<void> setInfiniteMix(bool enabled) async =>
      audioEngine?.queueManager.setInfiniteMix(enabled);

  @override
  Future<List<Track>> getTracks({
    TrackSortOption? sort,
    bool ascending = true,
  }) async {
    return await database?.getAllTracks(
          sortBy: sort?.name,
          ascending: ascending,
        ) ??
        const [];
  }

  @override
  Future<List<Album>> getAlbums() async =>
      await database?.getAllAlbums() ?? const [];

  @override
  Future<List<Artist>> getArtists() async =>
      await database?.getAllArtists() ?? const [];

  @override
  Future<List<Genre>> getGenres() async =>
      await database?.getAllGenres() ?? const [];

  @override
  Future<List<Track>> getAlbumTracks(int albumId) async =>
      await database?.getTracksByAlbumId(albumId) ?? const [];

  @override
  Future<List<Track>> getArtistTracks(int artistId) async =>
      await database?.getTracksByArtistId(artistId) ?? const [];

  @override
  Future<void> startScan(String directoryPath) async {
    await startScanDirectories([directoryPath]);
  }

  @override
  Future<void> startScanDirectories(List<String> directories) async {
    final scanner = metadataService;
    if (scanner == null) return;
    await _scanSubscription?.cancel();
    _scanSubscription = scanner.scanDirectories(directories).listen((progress) {
      _scanProgressController.add(progress);
    });
  }

  @override
  Future<void> cancelScan() async {
    await _scanSubscription?.cancel();
    metadataService?.cancelScan();
  }

  @override
  Future<void> deleteTrack(int trackId) async {
    await database?.deleteTrack(trackId);
  }

  @override
  Future<void> deleteTracksInFolder(String folderPath) async {
    await database?.deleteTracksInFolder(folderPath);
  }

  @override
  Future<Track?> getMetadata(String filePath) async {
    if (metadataService != null) {
      return await metadataService!.getMetadata(filePath);
    }
    return await database?.getTrackByFilePath(filePath);
  }

  @override
  Future<String?> getThumbnail(
    String filePath, {
    bool isHighQuality = false,
  }) async {
    if (metadataService != null) {
      return await metadataService!.getThumbnail(
        filePath,
        isHighQuality: isHighQuality,
      );
    }
    if (coverCacheService != null) {
      final q = isHighQuality ? ThumbnailQuality.high : ThumbnailQuality.low;
      if (coverCacheService!.hasCachedCover(filePath, quality: q)) {
        return coverCacheService!.getCoverFile(filePath, quality: q).path;
      }
    }
    return null;
  }

  @override
  Future<String?> getArtistCover(
    String artistName, {
    bool isHighQuality = false,
  }) async {
    if (metadataService != null) {
      return await metadataService!.getArtistCover(
        artistName,
        isHighQuality: isHighQuality,
      );
    }
    if (coverCacheService != null) {
      final q = isHighQuality ? ThumbnailQuality.high : ThumbnailQuality.low;
      if (coverCacheService!.hasCachedArtistCover(artistName, quality: q)) {
        return coverCacheService!
            .getArtistCoverFile(artistName, quality: q)
            .path;
      }
    }
    return null;
  }

  @override
  Future<void> clearCoverCache() async {
    if (metadataService != null) {
      await metadataService!.clearCoverCache();
    } else if (coverCacheService != null) {
      await coverCacheService!.clearCache();
    }
  }

  @override
  Future<List<Playlist>> getPlaylists() async =>
      await database?.getAllPlaylists() ?? const [];

  @override
  Future<int> createPlaylist(String name) async =>
      await database?.createPlaylist(name) ?? -1;

  @override
  Future<void> deletePlaylist(int playlistId) async =>
      await database?.deletePlaylist(playlistId);

  @override
  Future<void> renamePlaylist(int playlistId, String name) async =>
      await database?.renamePlaylist(playlistId, name);

  @override
  Future<List<Track>> getPlaylistTracks(int playlistId) async =>
      await database?.getTracksForPlaylist(playlistId) ?? const [];

  @override
  Future<List<int>> getPlaylistTrackIds(int playlistId) async {
    final ids = await database?.getTrackIdsForPlaylist(playlistId);
    return ids?.toList() ?? const [];
  }

  @override
  Future<void> addTracksToPlaylist(int playlistId, List<int> trackIds) async {
    if (database == null) return;
    try {
      await database!.addTracksToPlaylist(playlistId, trackIds);
    } catch (_) {
      for (final id in trackIds) {
        try {
          await database!.addTrackToPlaylist(playlistId, id);
        } catch (_) {}
      }
    }
  }

  @override
  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    await database?.removeTrackFromPlaylist(playlistId, trackId);
  }

  @override
  Future<void> reorderPlaylistTracks(
    int playlistId,
    int oldIndex,
    int newIndex,
  ) async {
    await database?.reorderPlaylistEntries(playlistId, oldIndex, newIndex);
  }

  @override
  Future<bool> toggleLikeTrack(int trackId, [String? filePath]) async {
    if (database == null) return false;
    await database!.toggleLikeTrack(trackId, filePath);
    return await database!.isTrackLiked(trackId);
  }

  @override
  Future<bool> isTrackLiked(int trackId) async {
    return await database?.isTrackLiked(trackId) ?? false;
  }

  @override
  Future<void> clearHistory() async {
    await database?.clearHistory();
  }

  @override
  Future<Map<String, dynamic>> search(String query) async {
    if (database == null) {
      return {'tracks': <Track>[], 'albums': <Album>[], 'artists': <Artist>[]};
    }
    final tracks = await database!.searchTracks(query);
    final albums = await database!.searchAlbums(query);
    final artists = await database!.searchArtists(query);
    return {'tracks': tracks, 'albums': albums, 'artists': artists};
  }

  @override
  Future<LyricsResult?> resolveLyrics(
    Track track, {
    bool allowRemote = false,
    bool bypassCache = false,
    Set<LyricsSource>? allowedSources,
    LyricsCancellationToken? cancellationToken,
    void Function(int seconds)? onThresholdCountdown,
  }) async {
    return await lyricsService?.resolveLyricsForTrack(
      track,
      allowRemote: allowRemote,
      forceRefresh: bypassCache,
      enabledSources: allowedSources,
      cancellationToken: cancellationToken,
      onThresholdCountdown: onThresholdCountdown,
    );
  }

  @override
  Future<String?> translateLyrics({
    required String keyHash,
    required LyricsSource source,
    required String targetLang,
    required List<String> rawLines,
  }) async {
    if (database != null) {
      final cached = await database!.getLyricsTranslation(
        keyHash: keyHash,
        source: source.dbValue,
        targetLang: targetLang,
      );
      if (cached != null && cached.isNotEmpty) return cached.join('\n');
    }

    final translationResult = await _translationClient.translate(
      rawLines,
      targetLanguage: targetLang,
    );

    if (translationResult.isSuccess) {
      final translatedLines = translationResult.translatedLines;
      if (database != null) {
        await database!.saveLyricsTranslation(
          keyHash: keyHash,
          source: source.dbValue,
          targetLang: targetLang,
          translatedLines: translatedLines,
        );
      }
      return translatedLines.join('\n');
    }
    return null;
  }

  @override
  Future<void> dispose() async {
    await _scanSubscription?.cancel();
    await _devicesController.close();
    await _scanProgressController.close();
  }
}
