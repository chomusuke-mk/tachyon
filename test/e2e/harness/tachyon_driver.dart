import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'package:path/path.dart' as p;

import 'e2e_models.dart';
import 'e2e_math_utils.dart';

class TachyonTestDriver {
  // --------------------------------------------------------------------------
  // Reactive Playback State
  // --------------------------------------------------------------------------
  PlayerStateSnapshot _state = const PlayerStateSnapshot();
  final StreamController<PlayerStateSnapshot> _stateController =
      StreamController<PlayerStateSnapshot>.broadcast();

  Stream<PlayerStateSnapshot> get stateStream => _stateController.stream;
  PlayerStateSnapshot get currentState => _state;

  void _emit(PlayerStateSnapshot newState) {
    _state = newState;
    _stateController.add(_state);
  }

  // --------------------------------------------------------------------------
  // Playback Operations (R1)
  // --------------------------------------------------------------------------
  Future<void> openQueue(
    List<TrackInfo> tracks, {
    int index = 0,
    bool play = true,
    bool shuffle = false,
  }) async {
    if (tracks.isEmpty) {
      _emit(const PlayerStateSnapshot());
      return;
    }

    var effectiveQueue = List<TrackInfo>.from(tracks);
    var effectiveIndex = index.clamp(0, effectiveQueue.length - 1);

    if (shuffle && effectiveQueue.length > 1) {
      final current = effectiveQueue.removeAt(effectiveIndex);
      _fisherYatesShuffle(effectiveQueue);
      effectiveQueue.insert(0, current);
      effectiveIndex = 0;
    }

    final currentTrack = effectiveQueue[effectiveIndex];
    _emit(_state.copyWith(
      queue: effectiveQueue,
      index: effectiveIndex,
      playing: play,
      buffering: false,
      completed: false,
      position: Duration.zero,
      duration: currentTrack.duration,
      shuffle: shuffle,
      instanceAVolume: _state.volume,
      instanceBVolume: 0.0,
      crossfadeActive: false,
      crossfadeProgress: 0.0,
    ));
  }

  void _fisherYatesShuffle(List<TrackInfo> list) {
    final random = math.Random(42); // Deterministic seed for reproducible tests
    for (int i = list.length - 1; i > 0; i--) {
      int j = random.nextInt(i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  Future<void> play() async {
    if (_state.queue.isEmpty) return;
    _emit(_state.copyWith(playing: true, completed: false));
  }

  Future<void> pause() async {
    _emit(_state.copyWith(playing: false));
  }

  Future<void> stop() async {
    _emit(_state.copyWith(
      playing: false,
      position: Duration.zero,
      completed: false,
      crossfadeActive: false,
      crossfadeProgress: 0.0,
    ));
  }

  Future<void> next() async {
    if (_state.queue.isEmpty) return;

    // If in active crossfade, fast-forward transition
    if (_state.crossfadeActive) {
      _emit(_state.copyWith(
        crossfadeActive: false,
        crossfadeProgress: 0.0,
        instanceAVolume: _state.volume,
        instanceBVolume: 0.0,
      ));
    }

    if (_state.loopMode == LoopMode.one) {
      _emit(_state.copyWith(
        position: Duration.zero,
        playing: true,
      ));
      return;
    }

    if (_state.index < _state.queue.length - 1) {
      final nextIndex = _state.index + 1;
      final nextTrack = _state.queue[nextIndex];
      _emit(_state.copyWith(
        index: nextIndex,
        position: Duration.zero,
        duration: nextTrack.duration,
        playing: true,
        completed: false,
      ));
    } else if (_state.loopMode == LoopMode.all) {
      final firstTrack = _state.queue[0];
      _emit(_state.copyWith(
        index: 0,
        position: Duration.zero,
        duration: firstTrack.duration,
        playing: true,
        completed: false,
      ));
    } else {
      _emit(_state.copyWith(
        playing: false,
        completed: true,
        position: _state.duration,
      ));
    }
  }

  Future<void> previous() async {
    if (_state.queue.isEmpty) return;

    // If played > 3 seconds, restart current track
    if (_state.position > const Duration(seconds: 3)) {
      _emit(_state.copyWith(position: Duration.zero));
      return;
    }

    if (_state.index > 0) {
      final prevIndex = _state.index - 1;
      final prevTrack = _state.queue[prevIndex];
      _emit(_state.copyWith(
        index: prevIndex,
        position: Duration.zero,
        duration: prevTrack.duration,
        playing: true,
      ));
    } else if (_state.loopMode == LoopMode.all) {
      final lastIndex = _state.queue.length - 1;
      final lastTrack = _state.queue[lastIndex];
      _emit(_state.copyWith(
        index: lastIndex,
        position: Duration.zero,
        duration: lastTrack.duration,
        playing: true,
      ));
    } else {
      _emit(_state.copyWith(position: Duration.zero));
    }
  }

  Future<void> seek(Duration targetPosition) async {
    if (_state.queue.isEmpty) return;

    // If seeking during crossfade, abort crossfade automation
    final wasCrossfading = _state.crossfadeActive;
    final clampedPos = Duration(
      milliseconds: targetPosition.inMilliseconds
          .clamp(0, _state.duration.inMilliseconds),
    );

    _emit(_state.copyWith(
      position: clampedPos,
      crossfadeActive: wasCrossfading ? false : _state.crossfadeActive,
      crossfadeProgress: wasCrossfading ? 0.0 : _state.crossfadeProgress,
      instanceAVolume: wasCrossfading ? _state.volume : _state.instanceAVolume,
      instanceBVolume: wasCrossfading ? 0.0 : _state.instanceBVolume,
    ));
  }

  Future<void> setVolume(double volume) async {
    final clampedVol = volume.clamp(0.0, 200.0);
    _emit(_state.copyWith(
      volume: clampedVol,
      instanceAVolume: clampedVol,
    ));
  }

  Future<void> setRate(double rate) async {
    final clampedRate = rate.clamp(0.5, 1.5);
    _emit(_state.copyWith(rate: clampedRate));
  }

  Future<void> setPitch(double pitch) async {
    final clampedPitch = pitch.clamp(0.5, 1.5);
    _emit(_state.copyWith(pitch: clampedPitch));
  }

  Future<void> setLoopMode(LoopMode mode) async {
    _emit(_state.copyWith(loopMode: mode));
  }

  Future<void> toggleShuffle() async {
    if (_state.queue.length <= 1) {
      _emit(_state.copyWith(shuffle: !_state.shuffle));
      return;
    }

    final newShuffle = !_state.shuffle;
    if (newShuffle) {
      final queue = List<TrackInfo>.from(_state.queue);
      final current = queue.removeAt(_state.index);
      _fisherYatesShuffle(queue);
      queue.insert(0, current);
      _emit(_state.copyWith(
        shuffle: true,
        queue: queue,
        index: 0,
      ));
    } else {
      // Preserve current playing track
      _emit(_state.copyWith(shuffle: false));
    }
  }

  Future<void> setCrossfadeConfig({
    required Duration duration,
    CrossfadeCurve curve = CrossfadeCurve.equalPower,
  }) async {
    _emit(_state.copyWith(
      crossfadeDuration: duration,
      crossfadeCurve: curve,
    ));
  }

  Future<void> insertNext(TrackInfo track) async {
    final newQueue = List<TrackInfo>.from(_state.queue);
    final insertPos = (_state.index + 1).clamp(0, newQueue.length);
    newQueue.insert(insertPos, track);
    _emit(_state.copyWith(queue: newQueue));
  }

  Future<void> append(List<TrackInfo> tracks) async {
    final newQueue = List<TrackInfo>.from(_state.queue)..addAll(tracks);
    _emit(_state.copyWith(queue: newQueue));
  }

  Future<void> removeQueueItem(int index) async {
    if (index < 0 || index >= _state.queue.length) return;

    final newQueue = List<TrackInfo>.from(_state.queue);
    newQueue.removeAt(index);

    if (newQueue.isEmpty) {
      _emit(const PlayerStateSnapshot());
      return;
    }

    int newIndex = _state.index;
    if (index == _state.index) {
      if (newIndex >= newQueue.length) {
        newIndex = newQueue.length - 1;
      }
      final newTrack = newQueue[newIndex];
      _emit(_state.copyWith(
        queue: newQueue,
        index: newIndex,
        position: Duration.zero,
        duration: newTrack.duration,
      ));
    } else {
      if (index < _state.index) {
        newIndex--;
      }
      _emit(_state.copyWith(
        queue: newQueue,
        index: newIndex,
      ));
    }
  }

  Future<void> reorderQueue(int fromIndex, int toIndex) async {
    if (fromIndex < 0 ||
        fromIndex >= _state.queue.length ||
        toIndex < 0 ||
        toIndex >= _state.queue.length) {
      return;
    }

    final newQueue = List<TrackInfo>.from(_state.queue);
    final item = newQueue.removeAt(fromIndex);
    newQueue.insert(toIndex, item);

    int newIndex = _state.index;
    if (_state.index == fromIndex) {
      newIndex = toIndex;
    } else if (fromIndex < _state.index && toIndex >= _state.index) {
      newIndex--;
    } else if (fromIndex > _state.index && toIndex <= _state.index) {
      newIndex++;
    }

    _emit(_state.copyWith(queue: newQueue, index: newIndex));
  }

  /// Simulates crossfade volume interpolation ticks (e.g. 20Hz - 50Hz)
  void simulateCrossfadeTick(double progress) {
    final p = progress.clamp(0.0, 1.0);
    final masterVol = _state.volume;

    final double volA;
    final double volB;

    if (_state.crossfadeCurve == CrossfadeCurve.equalPower) {
      final res = CrossfadeMath.calculateEqualPower(
        progress: p,
        masterVolume: masterVol,
      );
      volA = res.volumeA;
      volB = res.volumeB;
    } else {
      final res = CrossfadeMath.calculateLinear(
        progress: p,
        masterVolume: masterVol,
      );
      volA = res.volumeA;
      volB = res.volumeB;
    }

    if (p >= 1.0) {
      // Transition completed: advance to next track
      final nextIdx = _state.index + 1;
      if (nextIdx < _state.queue.length) {
        final nextTrack = _state.queue[nextIdx];
        _emit(_state.copyWith(
          index: nextIdx,
          position: Duration.zero,
          duration: nextTrack.duration,
          crossfadeActive: false,
          crossfadeProgress: 0.0,
          instanceAVolume: masterVol,
          instanceBVolume: 0.0,
        ));
      } else {
        _emit(_state.copyWith(
          crossfadeActive: false,
          crossfadeProgress: 0.0,
          instanceAVolume: masterVol,
          instanceBVolume: 0.0,
        ));
      }
    } else {
      _emit(_state.copyWith(
        crossfadeActive: true,
        crossfadeProgress: p,
        instanceAVolume: volA,
        instanceBVolume: volB,
      ));
    }
  }

  void simulatePositionTick(Duration newPosition) {
    _emit(_state.copyWith(position: newPosition));
  }

  // --------------------------------------------------------------------------
  // Metadata & ffprobe Extraction (R2)
  // --------------------------------------------------------------------------
  TrackInfo parseFfprobeJson(
    String jsonString, {
    required String filePath,
    int trackId = 1,
  }) {
    final Map<String, dynamic> data;
    try {
      data = json.decode(jsonString) as Map<String, dynamic>;
    } catch (_) {
      // Corrupt JSON fallback
      return TrackInfo(
        id: trackId,
        uri: filePath,
        title: p.basenameWithoutExtension(filePath),
        artist: 'Unknown Artist',
        album: 'Unknown Album',
        duration: Duration.zero,
      );
    }

    final format = data['format'] as Map<String, dynamic>? ?? {};
    final tags = format['tags'] as Map<String, dynamic>? ?? {};
    final streams = (data['streams'] as List<dynamic>? ?? [])
        .map((e) => e as Map<String, dynamic>)
        .toList();

    // Tag case normalization
    String? getTag(String key) {
      return tags[key.toLowerCase()]?.toString() ??
          tags[key.toUpperCase()]?.toString() ??
          tags[key]?.toString();
    }

    // Title
    final title = getTag('title') ?? p.basenameWithoutExtension(filePath);

    // Multi-artist splitting
    final rawArtist = getTag('artist') ?? 'Unknown Artist';
    final artists = normalizeArtists(rawArtist);
    final artist = artists.isNotEmpty ? artists.first : 'Unknown Artist';

    // Album & Album Artist
    final album = getTag('album') ?? 'Unknown Album';
    final albumArtist = getTag('album_artist') ?? getTag('albumartist') ?? artist;

    // Track number parsing (e.g. "03", "3/12")
    final rawTrack = getTag('track') ?? '1';
    final trackNumber = normalizeTrackNumber(rawTrack);

    // Disc number parsing
    final rawDisc = getTag('disc') ?? '1';
    final discNumber = normalizeDiscNumber(rawDisc);

    // Year parsing
    final rawDate = getTag('date') ?? getTag('year') ?? '';
    final year = normalizeYear(rawDate);

    // Duration float seconds to ms
    final durationSec = double.tryParse(format['duration']?.toString() ?? '0') ?? 0.0;
    final durationMs = (durationSec * 1000).round();

    // Stream info
    var bitrate = int.tryParse(format['bit_rate']?.toString() ?? '0') ?? 0;
    var sampleRate = 44100;
    var codec = 'unknown';
    var hasCover = false;

    for (final stream in streams) {
      if (stream['codec_type'] == 'audio') {
        sampleRate = int.tryParse(stream['sample_rate']?.toString() ?? '44100') ?? 44100;
        codec = stream['codec_name']?.toString() ?? codec;
        if (bitrate == 0) {
          bitrate = int.tryParse(stream['bit_rate']?.toString() ?? '0') ?? 0;
        }
      } else if (stream['codec_type'] == 'video') {
        final disposition = stream['disposition'] as Map<String, dynamic>? ?? {};
        if (disposition['attached_pic'] == 1 || disposition['attached_pic'] == '1') {
          hasCover = true;
        }
      }
    }

    final rawLyrics = getTag('lyrics') ?? getTag('unsyncedlyrics');

    return TrackInfo(
      id: trackId,
      uri: filePath,
      title: title.isEmpty ? p.basenameWithoutExtension(filePath) : title,
      artist: artist,
      artists: artists,
      album: album,
      albumArtist: albumArtist,
      trackNumber: trackNumber,
      discNumber: discNumber,
      year: year,
      duration: Duration(milliseconds: durationMs),
      bitrate: bitrate,
      sampleRate: sampleRate,
      codec: codec,
      fileSize: int.tryParse(format['size']?.toString() ?? '0') ?? 0,
      hasCover: hasCover,
      rawLyrics: rawLyrics,
      format: AudioFormat.fromExtension(p.extension(filePath)),
    );
  }

  List<String> normalizeArtists(String raw) {
    if (raw.trim().isEmpty) return ['Unknown Artist'];
    final delimiterRegex = RegExp(r'(\s*[/;,]\s*|\s*(?:feat\.|ft\.)\s*)', caseSensitive: false);
    final parts = raw
        .split(delimiterRegex)
        .map((e) => e.replaceAll(RegExp(r'^(?:feat\.|ft\.)\s*', caseSensitive: false), '').trim())
        .where((e) => e.isNotEmpty && !delimiterRegex.hasMatch(e))
        .toList();
    return parts.isEmpty ? [raw.trim()] : parts;
  }

  int normalizeTrackNumber(String raw) {
    final parts = raw.split('/');
    return int.tryParse(parts.first.trim()) ?? 1;
  }

  int normalizeDiscNumber(String raw) {
    final parts = raw.split('/');
    return int.tryParse(parts.first.trim()) ?? 1;
  }

  int normalizeYear(String raw) {
    final yearRegex = RegExp(r'\b(19\d{2}|20\d{2})\b');
    final match = yearRegex.firstMatch(raw);
    return match != null ? (int.tryParse(match.group(1)!) ?? 0) : 0;
  }

  String resolveCoverArt({
    required TrackInfo track,
    required List<String> directoryFiles,
    required String defaultAssetPath,
  }) {
    if (track.hasCover) {
      return '/cache/covers/${track.id}.jpg';
    }

    // Directory artwork fallback priority: cover.jpg, folder.jpg, album.jpg, front.jpg
    final priorityNames = ['cover.jpg', 'cover.png', 'folder.jpg', 'album.jpg', 'front.jpg'];
    for (final name in priorityNames) {
      for (final file in directoryFiles) {
        if (p.basename(file).toLowerCase() == name) {
          return file;
        }
      }
    }

    // First image in directory fallback
    for (final file in directoryFiles) {
      final ext = p.extension(file).toLowerCase();
      if (ext == '.jpg' || ext == '.jpeg' || ext == '.png') {
        return file;
      }
    }

    return defaultAssetPath;
  }

  // --------------------------------------------------------------------------
  // Relational Database & Persistence (R3)
  // --------------------------------------------------------------------------
  final Map<int, TrackInfo> _dbTracks = {};
  final Map<int, AlbumInfo> _dbAlbums = {};
  final Map<int, ArtistInfo> _dbArtists = {};
  final Map<int, GenreInfo> _dbGenres = {};
  final Map<int, Set<int>> _dbTrackGenres = {}; // trackId -> Set<genreId>
  final Map<int, PlaylistInfo> _dbPlaylists = {};
  final Map<int, List<PlaylistEntry>> _dbPlaylistEntries = {}; // playlistId -> entries

  int _nextTrackId = 1;
  int _nextAlbumId = 1;
  int _nextArtistId = 1;
  int _nextGenreId = 1;
  int _nextPlaylistId = 1;
  int _nextPlaylistEntryId = 1;

  void resetDatabase() {
    _dbTracks.clear();
    _dbAlbums.clear();
    _dbArtists.clear();
    _dbGenres.clear();
    _dbTrackGenres.clear();
    _dbPlaylists.clear();
    _dbPlaylistEntries.clear();
    _nextTrackId = 1;
    _nextAlbumId = 1;
    _nextArtistId = 1;
    _nextGenreId = 1;
    _nextPlaylistId = 1;
    _nextPlaylistEntryId = 1;

    // Initialize special playlists (Liked Songs = 1, History = 2)
    _dbPlaylists[1] = PlaylistInfo(
      id: 1,
      name: 'Liked Songs',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isSpecial: 1,
    );
    _dbPlaylistEntries[1] = [];

    _dbPlaylists[2] = PlaylistInfo(
      id: 2,
      name: 'History',
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isSpecial: 2,
    );
    _dbPlaylistEntries[2] = [];
  }

  Future<void> insertOrUpdateTrack(TrackInfo track) async {
    final trackId = track.id > 0 ? track.id : _nextTrackId++;
    final storedTrack = track.copyWith(id: trackId);
    _dbTracks[trackId] = storedTrack;

    // Relational Artist
    ArtistInfo? artist = _dbArtists.values
        .where((a) => a.name.toLowerCase() == track.artist.toLowerCase())
        .firstOrNull;
    if (artist == null) {
      final aId = _nextArtistId++;
      artist = ArtistInfo(id: aId, name: track.artist, trackCount: 1, albumCount: 1);
      _dbArtists[aId] = artist;
    } else {
      _dbArtists[artist.id] = ArtistInfo(
        id: artist.id,
        name: artist.name,
        trackCount: artist.trackCount + 1,
        albumCount: artist.albumCount,
      );
    }

    // Relational Album
    AlbumInfo? album = _dbAlbums.values
        .where((a) =>
            a.name.toLowerCase() == track.album.toLowerCase() &&
            a.artistName.toLowerCase() == track.artist.toLowerCase())
        .firstOrNull;
    if (album == null) {
      final alId = _nextAlbumId++;
      album = AlbumInfo(
        id: alId,
        name: track.album,
        artistName: track.artist,
        year: track.year,
        trackCount: 1,
      );
      _dbAlbums[alId] = album;
    } else {
      _dbAlbums[album.id] = AlbumInfo(
        id: album.id,
        name: album.name,
        artistName: album.artistName,
        year: album.year,
        trackCount: album.trackCount + 1,
      );
    }
  }

  Future<void> batchInsertTracks(List<TrackInfo> tracks) async {
    for (final track in tracks) {
      await insertOrUpdateTrack(track);
    }
  }

  Future<List<TrackInfo>> getAllTracks({String? sortBy, bool ascending = true}) async {
    var tracks = _dbTracks.values.toList();
    if (sortBy == 'title') {
      tracks.sort((a, b) => ascending
          ? a.title.toLowerCase().compareTo(b.title.toLowerCase())
          : b.title.toLowerCase().compareTo(a.title.toLowerCase()));
    } else if (sortBy == 'duration') {
      tracks.sort((a, b) => ascending
          ? a.duration.compareTo(b.duration)
          : b.duration.compareTo(a.duration));
    } else if (sortBy == 'year') {
      tracks.sort((a, b) => ascending
          ? a.year.compareTo(b.year)
          : b.year.compareTo(a.year));
    }
    return tracks;
  }

  Future<List<AlbumInfo>> getAllAlbums() async => _dbAlbums.values.toList();
  Future<List<ArtistInfo>> getAllArtists() async => _dbArtists.values.toList();
  Future<List<GenreInfo>> getAllGenres() async => _dbGenres.values.toList();
  Future<List<PlaylistInfo>> getAllPlaylists() async => _dbPlaylists.values.toList();

  Future<int> addGenre(String name) async {
    final existing = _dbGenres.values.where((g) => g.name.toLowerCase() == name.toLowerCase()).firstOrNull;
    if (existing != null) return existing.id;
    final id = _nextGenreId++;
    _dbGenres[id] = GenreInfo(id: id, name: name);
    return id;
  }

  Future<int> createPlaylist(String name, {int isSpecial = 0}) async {
    final id = _nextPlaylistId++;
    _dbPlaylists[id] = PlaylistInfo(
      id: id,
      name: name,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      isSpecial: isSpecial,
    );
    _dbPlaylistEntries[id] = [];
    return id;
  }

  Future<void> addTrackToPlaylist(int playlistId, int trackId) async {
    final track = _dbTracks[trackId];
    if (track == null || !_dbPlaylists.containsKey(playlistId)) return;

    final entries = _dbPlaylistEntries[playlistId] ?? [];
    final entryId = _nextPlaylistEntryId++;
    final entry = PlaylistEntry(
      id: entryId,
      playlistId: playlistId,
      trackId: trackId,
      uri: track.uri,
      position: entries.length,
    );
    entries.add(entry);
    _dbPlaylistEntries[playlistId] = entries;

    // Update track count
    final pl = _dbPlaylists[playlistId]!;
    _dbPlaylists[playlistId] = PlaylistInfo(
      id: pl.id,
      name: pl.name,
      createdAt: pl.createdAt,
      isSpecial: pl.isSpecial,
      trackCount: entries.length,
    );
  }

  Future<void> removeTrackFromPlaylist(int playlistId, int trackId) async {
    final entries = _dbPlaylistEntries[playlistId];
    if (entries == null) return;

    entries.removeWhere((e) => e.trackId == trackId);
    // Re-index positions
    for (int i = 0; i < entries.length; i++) {
      entries[i] = PlaylistEntry(
        id: entries[i].id,
        playlistId: playlistId,
        trackId: entries[i].trackId,
        uri: entries[i].uri,
        position: i,
      );
    }
  }

  Future<void> reorderPlaylistEntries(
    int playlistId,
    int fromIndex,
    int toIndex,
  ) async {
    final entries = _dbPlaylistEntries[playlistId];
    if (entries == null ||
        fromIndex < 0 ||
        fromIndex >= entries.length ||
        toIndex < 0 ||
        toIndex >= entries.length) {
      return;
    }

    final item = entries.removeAt(fromIndex);
    entries.insert(toIndex, item);

    for (int i = 0; i < entries.length; i++) {
      entries[i] = PlaylistEntry(
        id: entries[i].id,
        playlistId: playlistId,
        trackId: entries[i].trackId,
        uri: entries[i].uri,
        position: i,
      );
    }
  }

  Future<List<TrackInfo>> getTracksForPlaylist(int playlistId) async {
    final entries = _dbPlaylistEntries[playlistId] ?? [];
    return entries
        .map((e) => _dbTracks[e.trackId])
        .whereType<TrackInfo>()
        .toList();
  }

  Future<List<TrackInfo>> searchTracks(String query) async {
    if (query.trim().isEmpty) return [];
    final q = query.toLowerCase();
    return _dbTracks.values.where((t) {
      return t.title.toLowerCase().contains(q) ||
          t.artist.toLowerCase().contains(q) ||
          t.album.toLowerCase().contains(q);
    }).toList();
  }

  // --------------------------------------------------------------------------
  // Synchronized Lyrics Parser & SplayTreeMap Engine (R4 / M5)
  // --------------------------------------------------------------------------
  List<LyricEntry> parseLrc(String rawLrc) {
    if (rawLrc.trim().isEmpty) return [];

    final lines = rawLrc.split('\n');
    final parsed = <LyricEntry>[];
    int headerOffset = 0;

    // Check for [offset:+/-ms] header
    final offsetRegex = RegExp(r'\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);
    final timestampRegex = RegExp(r'\[(\d{1,}):(\d{2})\.(\d{2,3})\]');

    for (final line in lines) {
      final offsetMatch = offsetRegex.firstMatch(line);
      if (offsetMatch != null) {
        headerOffset = int.tryParse(offsetMatch.group(1)!) ?? 0;
        continue;
      }

      final matches = timestampRegex.allMatches(line).toList();
      if (matches.isNotEmpty) {
        // Strip timestamps to get lyric text
        final text = line.replaceAll(timestampRegex, '').trim();
        for (final match in matches) {
          final minutes = int.parse(match.group(1)!);
          final seconds = int.parse(match.group(2)!);
          final rawFrac = match.group(3)!;
          final millis = rawFrac.length == 2
              ? int.parse(rawFrac) * 10
              : int.parse(rawFrac);

          final totalMs = math.max(
            0,
            (minutes * 60 * 1000) + (seconds * 1000) + millis + headerOffset,
          );
          parsed.add(LyricEntry(timestampMs: totalMs, text: text, isSynced: true));
        }
      } else if (line.trim().isNotEmpty && !line.trim().startsWith('[')) {
        // Unsynced plain lyric line
        parsed.add(LyricEntry(timestampMs: 0, text: line.trim(), isSynced: false));
      }
    }

    parsed.sort((a, b) => a.timestampMs.compareTo(b.timestampMs));
    return parsed;
  }

  SplayTreeMap<int, int> buildLyricsIndex(List<LyricEntry> lyrics) {
    final map = SplayTreeMap<int, int>();
    for (int i = 0; i < lyrics.length; i++) {
      if (lyrics[i].isSynced) {
        map[lyrics[i].timestampMs] = i;
      }
    }
    return map;
  }

  int getActiveLyricIndex(int positionMs, SplayTreeMap<int, int> indexMap) {
    return LyricsMath.findActiveLyricIndex(
      positionMs: positionMs,
      timestampToIndexMap: indexMap,
    );
  }

  // --------------------------------------------------------------------------
  // Preferences & App Settings (R3)
  // --------------------------------------------------------------------------
  AppSettings _settings = const AppSettings();

  AppSettings get settings => _settings;

  void updateSettings(AppSettings newSettings) {
    _settings = newSettings;
  }

  // --------------------------------------------------------------------------
  // Localization (i18n) Foundation (R5)
  // --------------------------------------------------------------------------
  final Map<String, Map<String, String>> _localeBundles = {};
  String _currentLocale = 'en';

  void registerLocaleBundle(String localeCode, Map<String, String> strings) {
    _localeBundles[localeCode] = Map.unmodifiable(strings);
  }

  void switchLocale(String localeCode) {
    _currentLocale = localeCode;
    _settings = _settings.copyWith(locale: localeCode);
  }

  String getString(String key) {
    final currentBundle = _localeBundles[_currentLocale] ?? {};
    if (currentBundle.containsKey(key)) {
      return currentBundle[key]!;
    }
    // Fallback to English
    final fallbackBundle = _localeBundles['en'] ?? {};
    return fallbackBundle[key] ?? key;
  }

  // --------------------------------------------------------------------------
  // Update Checker & GitHub Releases Client (R5)
  // --------------------------------------------------------------------------
  ReleaseUpdateInfo checkReleaseUpdate({
    required String currentVersion,
    required Map<String, dynamic> releaseJson,
  }) {
    final tagName = releaseJson['tag_name']?.toString() ?? 'v0.0.0';
    final remoteVersion = tagName.replaceAll(RegExp(r'^v'), '');
    final changelog = releaseJson['body']?.toString() ?? '';
    final assets = releaseJson['assets'] as List<dynamic>? ?? [];

    String assetUrl = '';
    for (final asset in assets) {
      if (asset is Map<String, dynamic>) {
        final name = asset['name']?.toString() ?? '';
        if (name.endsWith('.apk') || name.endsWith('.tar.gz') || name.endsWith('.zip')) {
          assetUrl = asset['browser_download_url']?.toString() ?? '';
          break;
        }
      }
    }

    final isNewer = isVersionNewer(currentVersion, remoteVersion);

    return ReleaseUpdateInfo(
      tagName: tagName,
      version: remoteVersion,
      changelog: changelog,
      assetUrl: assetUrl,
      isNewer: isNewer,
    );
  }

  bool isVersionNewer(String current, String remote) {
    final currentParts = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
    final remoteParts = remote.split('.').map((e) => int.tryParse(e) ?? 0).toList();

    for (int i = 0; i < 3; i++) {
      final c = i < currentParts.length ? currentParts[i] : 0;
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      if (r > c) return true;
      if (r < c) return false;
    }
    return false;
  }

  void dispose() {
    _stateController.close();
  }
}
