import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show VoidCallback, debugPrint;
import 'package:tachyon/core/playback/domain/loop_mode.dart';
import 'package:tachyon/core/store/domain/playlist.dart';
import 'package:tachyon/core/store/domain/track.dart';

typedef LibraryTrackProvider = FutureOr<List<Track>> Function(int count);

/// High-performance Queue Manager for Tachyon Music Player.
class QueueManager {
  /// Playback position after which [previous] restarts the current track
  /// instead of moving to the prior one.
  static const Duration restartThreshold = Duration(seconds: 3);

  int _nextEntryId = 0;
  List<PlaylistEntry> _activeQueue = [];
  List<PlaylistEntry> _originalQueue = [];
  int _currentIndex = -1;
  bool _isShuffled = false;
  Loop _loopMode = Loop.off;
  bool _infiniteMixEnabled = false;
  bool _prefetchExhausted = false;
  Future<void>? _pendingPrefetch;

  /// Callback notified whenever queue items are mutated in the background
  /// (e.g. by infinite mix proactive prefetch).
  VoidCallback? onQueueMutated;

  final LibraryTrackProvider? libraryTrackProvider;
  final math.Random _random;

  int _version = 0;
  List<PlaylistEntry>? _activeView;

  final StreamController<PlaylistEntry?> _nextTrackController =
      StreamController<PlaylistEntry?>.broadcast(sync: true);
  PlaylistEntry? _lastEmittedNextTrack;

  /// Reactive stream broadcasting the candidate next track for auto-crossfade.
  Stream<PlaylistEntry?> get nextTrackStream => _nextTrackController.stream;

  QueueManager({this.libraryTrackProvider, math.Random? random})
    : _random = random ?? math.Random();

  /// Whether [a] and [b] refer to the same queue entry.
  static bool isSameItem(PlaylistEntry? a, PlaylistEntry? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.id == b.id && a.track?.filePath == b.track?.filePath;
  }

  List<PlaylistEntry> get activeQueue =>
      _activeView ??= List<PlaylistEntry>.unmodifiable(_activeQueue);

  List<PlaylistEntry> get originalQueue => List.unmodifiable(_originalQueue);

  int get length => _activeQueue.length;
  bool get isEmpty => _activeQueue.isEmpty;
  int get currentIndex => _currentIndex;
  bool get isShuffled => _isShuffled;
  Loop get loopMode => _loopMode;
  bool get infiniteMixEnabled => _infiniteMixEnabled;

  PlaylistEntry? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _activeQueue.length)
      ? _activeQueue[_currentIndex]
      : null;

  bool get hasNext =>
      _loopMode == Loop.all ||
      _loopMode == Loop.one ||
      _currentIndex < _activeQueue.length - 1 ||
      (_infiniteMixEnabled && !_prefetchExhausted && _activeQueue.isNotEmpty);

  bool get hasNextDifferent => peekNext(distinct: true) != null;

  bool get hasPrevious => _loopMode == Loop.all || _currentIndex > 0;

  int? _peekNextIndex({required bool distinct}) {
    if (_activeQueue.isEmpty ||
        _currentIndex < 0 ||
        _currentIndex >= _activeQueue.length) {
      return null;
    }
    if (_loopMode == Loop.one) {
      return distinct ? null : _currentIndex;
    }

    int? candidateIdx;
    if (_currentIndex < _activeQueue.length - 1) {
      candidateIdx = _currentIndex + 1;
    } else if (_loopMode == Loop.all) {
      candidateIdx = 0;
    }
    if (candidateIdx == null) return null;

    if (distinct &&
        _activeQueue[candidateIdx].track?.filePath ==
            _activeQueue[_currentIndex].track?.filePath) {
      return null;
    }
    return candidateIdx;
  }

  PlaylistEntry? peekNext({bool distinct = true}) {
    final idx = _peekNextIndex(distinct: distinct);
    return idx == null ? null : _activeQueue[idx];
  }

  PlaylistEntry? commitNext(PlaylistEntry expected) {
    final idx = _peekNextIndex(distinct: true);
    if (idx == null || !isSameItem(_activeQueue[idx], expected)) return null;
    _currentIndex = idx;
    _touch();
    _notifyNextTrack();
    _maybePrefetchInfiniteMix();
    return currentTrack;
  }

  void _notifyNextTrack() {
    if (_nextTrackController.isClosed) return;
    final currentNext = peekNext(distinct: true);
    if (!isSameItem(_lastEmittedNextTrack, currentNext)) {
      _lastEmittedNextTrack = currentNext;
      _nextTrackController.add(currentNext);
    }
  }

  void _touch() {
    _version++;
    _activeView = null;
  }

  void _syncOriginalIfUnshuffled() {
    if (!_isShuffled) {
      _originalQueue = List<PlaylistEntry>.from(_activeQueue);
    }
  }

  int _indexInOriginal(PlaylistEntry item) {
    final byIdentity = _originalQueue.indexWhere((it) => identical(it, item));
    if (byIdentity != -1) return byIdentity;
    if (item.id != null) {
      final byId = _originalQueue.indexWhere((it) => it.id == item.id);
      if (byId != -1) return byId;
    }
    return _originalQueue.indexWhere(
      (it) => it.track?.filePath == item.track?.filePath,
    );
  }

  bool get _shouldPrefetchInfiniteMix =>
      _infiniteMixEnabled &&
      _loopMode == Loop.off &&
      !_prefetchExhausted &&
      _pendingPrefetch == null &&
      libraryTrackProvider != null &&
      _activeQueue.isNotEmpty &&
      _currentIndex >= _activeQueue.length - 1;

  Future<void> _maybePrefetchInfiniteMix() async {
    if (!_shouldPrefetchInfiniteMix) return;

    final provider = libraryTrackProvider!;
    final versionBeforeFetch = _version;
    final fetchFuture = () async {
      List<Track> rawTracks;
      try {
        rawTracks = await provider(25);
      } catch (e) {
        debugPrint('[QueueManager] Infinite mix provider failed: $e');
        rawTracks = const [];
      }

      if (!_infiniteMixEnabled || _loopMode != Loop.off) {
        return;
      }
      if (versionBeforeFetch != _version) {
        unawaited(_maybePrefetchInfiniteMix());
        return;
      }

      if (rawTracks.isEmpty) {
        _prefetchExhausted = true;
        _notifyNextTrack();
        return;
      }

      final existingFilePaths = _activeQueue
          .map((it) => it.track?.filePath)
          .whereType<String>()
          .toSet();
      var candidateTracks = rawTracks
          .where((t) => !existingFilePaths.contains(t.filePath))
          .toList();

      if (candidateTracks.isEmpty) {
        candidateTracks = rawTracks;
      }

      if (candidateTracks.isNotEmpty) {
        _touch();
        final mixEntries = [
          for (int i = 0; i < candidateTracks.length; i++)
            PlaylistEntry.forQueue(
              id: _nextEntryId++,
              position: _activeQueue.length + i,
              track: candidateTracks[i],
            ),
        ];
        _activeQueue.addAll(mixEntries);
        if (_isShuffled) {
          _originalQueue.addAll(mixEntries);
        } else {
          _syncOriginalIfUnshuffled();
        }
        _notifyNextTrack();
        onQueueMutated?.call();
      }
    }();

    _pendingPrefetch = fetchFuture;
    try {
      await fetchFuture;
    } finally {
      if (identical(_pendingPrefetch, fetchFuture)) {
        _pendingPrefetch = null;
      }
    }
  }

  void dispose() {
    _nextTrackController.close();
    onQueueMutated = null;
  }

  void setTracks(
    List<Track> tracks, {
    int? startIndex,
    bool shuffle = false,
  }) {
    _nextEntryId = 0;
    final entries = [
      for (int i = 0; i < tracks.length; i++)
        PlaylistEntry.forQueue(
          id: _nextEntryId++,
          position: i,
          track: tracks[i],
        ),
    ];
    setQueue(entries, startIndex: startIndex, shuffle: shuffle);
  }

  void setQueue(
    List<PlaylistEntry> items, {
    int? startIndex,
    bool shuffle = false,
  }) {
    _touch();
    _prefetchExhausted = false;
    _nextEntryId = 0;
    if (items.isEmpty) {
      _activeQueue = [];
      _originalQueue = [];
      _currentIndex = -1;
      _isShuffled = false;
      _notifyNextTrack();
      return;
    }

    final normalized = [
      for (int i = 0; i < items.length; i++)
        items[i].copyWith(id: _nextEntryId++, position: i),
    ];

    _originalQueue = List<PlaylistEntry>.from(normalized);

    if (!shuffle) {
      _activeQueue = List<PlaylistEntry>.from(normalized);
      _currentIndex = (startIndex ?? 0).clamp(0, normalized.length - 1);
      _isShuffled = false;
    } else {
      _isShuffled = true;
      final int chosenIndex = startIndex != null
          ? startIndex.clamp(0, normalized.length - 1)
          : _random.nextInt(normalized.length);
      final current = normalized[chosenIndex];
      final remaining = List<PlaylistEntry>.from(normalized)
        ..removeAt(chosenIndex);

      _fisherYatesShuffle(remaining);
      _avoidImmediateDuplicate(current, remaining);

      _activeQueue = [current, ...remaining];
      _currentIndex = 0;
    }
    _notifyNextTrack();
    _maybePrefetchInfiniteMix();
  }

  void _avoidImmediateDuplicate(
    PlaylistEntry current,
    List<PlaylistEntry> remaining,
  ) {
    if (remaining.isNotEmpty &&
        remaining[0].track?.filePath == current.track?.filePath &&
        remaining.length > 1) {
      final nonDupIdx = remaining.indexWhere(
        (it) => it.track?.filePath != current.track?.filePath,
      );
      if (nonDupIdx != -1) {
        final nonDup = remaining.removeAt(nonDupIdx);
        remaining.insert(0, nonDup);
      }
    }
  }

  void _fisherYatesShuffle(List<PlaylistEntry> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  void toggleShuffle() => setShuffle(!_isShuffled);

  void setShuffle(bool enabled) {
    if (_isShuffled == enabled) return;
    final current = currentTrack;
    if (current == null) {
      _isShuffled = enabled;
      return;
    }
    _touch();

    if (enabled) {
      final remaining = List<PlaylistEntry>.from(_activeQueue)
        ..removeAt(_currentIndex);

      _fisherYatesShuffle(remaining);
      _avoidImmediateDuplicate(current, remaining);

      _activeQueue = [current, ...remaining];
      _currentIndex = 0;
      _isShuffled = true;
    } else {
      final origIdx = _indexInOriginal(current);

      _activeQueue = List<PlaylistEntry>.from(_originalQueue);
      if (origIdx != -1) {
        _currentIndex = origIdx;
      } else {
        _currentIndex = _currentIndex.clamp(0, _activeQueue.length - 1);
      }
      _isShuffled = false;
    }
    _notifyNextTrack();
    _maybePrefetchInfiniteMix();
  }

  void setLoopMode(Loop loop) {
    if (_loopMode == loop) return;
    _loopMode = loop;
    if (loop == Loop.off) {
      _maybePrefetchInfiniteMix();
    }
    _notifyNextTrack();
  }

  Loop cycleLoopMode() {
    _loopMode = _loopMode.next();
    if (_loopMode == Loop.off) {
      _maybePrefetchInfiniteMix();
    }
    _notifyNextTrack();
    return _loopMode;
  }

  void setInfiniteMix(bool enabled) {
    if (_infiniteMixEnabled == enabled) return;
    _infiniteMixEnabled = enabled;
    if (enabled) {
      _prefetchExhausted = false;
      _maybePrefetchInfiniteMix();
    }
    _notifyNextTrack();
  }

  void insertNext(PlaylistEntry item) {
    _touch();
    _prefetchExhausted = false;
    final entry = item.copyWith(id: _nextEntryId++);
    if (_activeQueue.isEmpty) {
      _activeQueue = [entry];
      _originalQueue = [entry];
      _currentIndex = 0;
      _notifyNextTrack();
      _maybePrefetchInfiniteMix();
      return;
    }

    final insertIdx = _currentIndex + 1;
    _activeQueue.insert(insertIdx, entry);

    if (_isShuffled) {
      final origIdx = _indexInOriginal(_activeQueue[_currentIndex]);
      if (origIdx != -1) {
        _originalQueue.insert(origIdx + 1, entry);
      } else {
        _originalQueue.add(entry);
      }
    } else {
      _syncOriginalIfUnshuffled();
    }
    _notifyNextTrack();
    _maybePrefetchInfiniteMix();
  }

  void append(List<PlaylistEntry> items) {
    if (items.isEmpty) return;

    final normalized = [
      for (int i = 0; i < items.length; i++)
        items[i].copyWith(
          id: _nextEntryId++,
          position: _activeQueue.length + i,
        ),
    ];

    if (_activeQueue.isEmpty) {
      setQueue(normalized);
      return;
    }
    _touch();
    _prefetchExhausted = false;

    _activeQueue.addAll(normalized);

    if (_isShuffled) {
      _originalQueue.addAll(normalized);
    } else {
      _syncOriginalIfUnshuffled();
    }
    _notifyNextTrack();
    _maybePrefetchInfiniteMix();
  }

  PlaylistEntry? remove(int index) {
    if (index < 0 || index >= _activeQueue.length) return null;
    _touch();
    _prefetchExhausted = false;

    final removedItem = _activeQueue.removeAt(index);
    if (_isShuffled) {
      final origIdx = _indexInOriginal(removedItem);
      if (origIdx != -1) {
        _originalQueue.removeAt(origIdx);
      }
    } else {
      _syncOriginalIfUnshuffled();
    }

    if (_activeQueue.isEmpty) {
      _currentIndex = -1;
      _notifyNextTrack();
      return removedItem;
    }

    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _activeQueue.length) {
        _currentIndex = _activeQueue.length - 1;
      }
    }

    _notifyNextTrack();
    _maybePrefetchInfiniteMix();
    return removedItem;
  }

  void reorder(int from, int to) {
    if (from < 0 ||
        from >= _activeQueue.length ||
        to < 0 ||
        to >= _activeQueue.length) {
      return;
    }
    if (from == to) return;
    _touch();

    final item = _activeQueue.removeAt(from);
    _activeQueue.insert(to, item);

    if (_currentIndex == from) {
      _currentIndex = to;
    } else if (from < _currentIndex && to >= _currentIndex) {
      _currentIndex--;
    } else if (from > _currentIndex && to <= _currentIndex) {
      _currentIndex++;
    }

    _syncOriginalIfUnshuffled();
    _notifyNextTrack();
    _maybePrefetchInfiniteMix();
  }

  PlaylistEntry? jumpTo(int index) {
    if (index >= 0 && index < _activeQueue.length) {
      _currentIndex = index;
      _touch();
      _notifyNextTrack();
      _maybePrefetchInfiniteMix();
      return currentTrack;
    }
    return null;
  }

  void clear({bool keepCurrent = false}) {
    _touch();
    _prefetchExhausted = false;
    final current = keepCurrent ? currentTrack : null;
    if (current != null) {
      final entry = current.copyWith(position: 0);
      _activeQueue = [entry];
      _originalQueue = [entry];
      _currentIndex = 0;
      _isShuffled = false;
      _nextEntryId = math.max(_nextEntryId, (entry.id ?? 0) + 1);
    } else {
      _nextEntryId = 0;
      _activeQueue = [];
      _originalQueue = [];
      _currentIndex = -1;
      _isShuffled = false;
    }
    _notifyNextTrack();
    if (keepCurrent) {
      _maybePrefetchInfiniteMix();
    }
  }

  Future<PlaylistEntry?> next({bool isManual = true}) async {
    if (_activeQueue.isEmpty) return null;

    if (!isManual && _loopMode == Loop.one) {
      return currentTrack;
    }

    if (_pendingPrefetch != null) {
      await _pendingPrefetch;
    }

    if (_currentIndex < _activeQueue.length - 1) {
      _currentIndex++;
      _touch();
      _notifyNextTrack();
      _maybePrefetchInfiniteMix();
      return currentTrack;
    }

    if (_loopMode == Loop.off &&
        _infiniteMixEnabled &&
        !_prefetchExhausted &&
        libraryTrackProvider != null) {
      await _maybePrefetchInfiniteMix();
      if (_currentIndex < _activeQueue.length - 1) {
        _currentIndex++;
        _touch();
        _notifyNextTrack();
        _maybePrefetchInfiniteMix();
        return currentTrack;
      }
    }

    if (_loopMode == Loop.all) {
      _currentIndex = 0;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }

    if (_loopMode == Loop.one && isManual) {
      _currentIndex = 0;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }

    return null;
  }

  PlaylistEntry? previous({Duration position = Duration.zero}) {
    if (_activeQueue.isEmpty) return null;

    if (position > restartThreshold) {
      return null;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }

    if (_loopMode == Loop.all && _activeQueue.length > 1) {
      _currentIndex = _activeQueue.length - 1;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }

    return null;
  }
}
