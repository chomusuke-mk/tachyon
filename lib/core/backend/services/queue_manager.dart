import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:tachyon/features/library/domain/playlist.dart';
import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/loop_mode.dart';

typedef LibraryTrackProvider = Future<List<Track>> Function(int count);

/// High-performance Queue Manager for Tachyon Music Player.
///
/// The queue is the **single source of truth** for navigation policy:
/// which item is current, which item comes next, how repeat modes behave and
/// when "previous" restarts the current track. The audio engine never
/// recomputes indices; it only asks the queue and executes the result.
///
/// Implements:
/// - Fisher-Yates shuffle pinning the currently playing track at index 0.
/// - Un-shuffle capability restoring the exact original playlist/album order
///   while preserving the active track pointer.
/// - Repeat modes: [Loop.off], [Loop.one], [Loop.all].
/// - Queue operations: [insertNext], [append], [remove], [reorder], [jumpTo], [clear].
/// - Infinite Library Mix: automatic appending of randomized library tracks
///   when the queue reaches the end and [Loop.off] is set.
/// - [nextTrackStream]: synchronous notifications whenever the upcoming
///   candidate changes, so the engine can invalidate tentative transitions.
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
  final LibraryTrackProvider? libraryTrackProvider;
  final math.Random _random;

  /// Monotonic mutation counter. Used to detect concurrent mutations across
  /// asynchronous gaps (e.g. while the infinite mix provider is fetching).
  int _version = 0;

  /// Cached read-only view of [_activeQueue], invalidated on every mutation.
  List<PlaylistEntry>? _activeView;

  final StreamController<PlaylistEntry?> _nextTrackController =
      StreamController<PlaylistEntry?>.broadcast(sync: true);
  PlaylistEntry? _lastEmittedNextTrack;

  /// Reactive stream broadcasting the candidate next track for auto-crossfade.
  ///
  /// Emits synchronously whenever the next track changes or becomes null.
  Stream<PlaylistEntry?> get nextTrackStream => _nextTrackController.stream;

  QueueManager({this.libraryTrackProvider, math.Random? random})
    : _random = random ?? math.Random();

  /// Whether [a] and [b] refer to the same queue entry.
  static bool isSameItem(PlaylistEntry? a, PlaylistEntry? b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    return a.id == b.id && a.track?.filePath == b.track?.filePath;
  }

  // --------------------------------------------------------------------------
  // Getters
  // --------------------------------------------------------------------------

  /// Read-only snapshot of the active playback queue.
  ///
  /// The returned list is cached until the next mutation, so repeated reads
  /// are O(1) and return the identical instance.
  List<PlaylistEntry> get activeQueue =>
      _activeView ??= List<PlaylistEntry>.unmodifiable(_activeQueue);

  /// Read-only snapshot of the original un-shuffled playlist sequence.
  List<PlaylistEntry> get originalQueue => List.unmodifiable(_originalQueue);

  /// Number of items in the active queue.
  int get length => _activeQueue.length;

  /// Whether the active queue has no items.
  bool get isEmpty => _activeQueue.isEmpty;

  /// Current zero-based index into [activeQueue], or -1 if the queue is empty.
  int get currentIndex => _currentIndex;

  /// Whether the queue is currently in shuffled order.
  bool get isShuffled => _isShuffled;

  /// Current repeat mode: [Loop.off], [Loop.one], [Loop.all].
  Loop get loopMode => _loopMode;

  /// Whether Infinite Library Mix is enabled.
  bool get infiniteMixEnabled => _infiniteMixEnabled;

  /// The currently active [PlaylistEntry], or null if queue is empty.
  PlaylistEntry? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _activeQueue.length)
      ? _activeQueue[_currentIndex]
      : null;

  /// Whether there is a subsequent track available according to [loopMode].
  bool get hasNext =>
      _loopMode == Loop.all ||
      _loopMode == Loop.one ||
      _currentIndex < _activeQueue.length - 1;

  /// Whether there is a subsequent track available that is different from the current track.
  bool get hasNextDifferent => peekNext(distinct: true) != null;

  /// Whether there is a prior track available.
  bool get hasPrevious => _loopMode == Loop.all || _currentIndex > 0;

  /// Index of the candidate next track, or null if there is none.
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

  /// Peeks the candidate next track without modifying queue state.
  ///
  /// When [distinct] is true (default for crossfade calculations):
  /// - Returns `null` if [loopMode] is [Loop.one].
  /// - Returns `null` if the candidate track shares the same filePath
  ///   as the currently playing track (e.g. single-track queue in [Loop.all]
  ///   or adjacent duplicate tracks).
  PlaylistEntry? peekNext({bool distinct = true}) {
    final idx = _peekNextIndex(distinct: distinct);
    return idx == null ? null : _activeQueue[idx];
  }

  /// Atomically advances to [expected] if, and only if, it is still the
  /// candidate returned by [peekNext].
  ///
  /// Used by the audio engine to commit a tentative (automatic) crossfade.
  /// Returns the new current track, or `null` if the queue no longer agrees
  /// with the transition (in which case nothing is modified).
  PlaylistEntry? commitNext(PlaylistEntry expected) {
    final idx = _peekNextIndex(distinct: true);
    if (idx == null || !isSameItem(_activeQueue[idx], expected)) return null;
    _currentIndex = idx;
    _touch();
    _notifyNextTrack();
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

  /// Marks the queue as mutated (invalidates cached views).
  void _touch() {
    _version++;
    _activeView = null;
  }

  /// While not shuffled, the original order must mirror the active order
  /// exactly. Keeping this invariant avoids index drift between both lists
  /// (e.g. after appending before infinite-mix tracks).
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

  /// Disposes the queue manager resources and closes reactive streams.
  void dispose() {
    _nextTrackController.close();
  }

  // --------------------------------------------------------------------------
  // Queue Initialization & Reset
  // --------------------------------------------------------------------------

  /// Sets or replaces the entire queue using [Track] objects.
  void setTracks(
    List<Track> tracks, {
    int startIndex = 0,
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

  /// Sets or replaces the entire queue.
  ///
  /// Resets `_nextEntryId = 0` to assign monotonically increasing IDs.
  /// If [shuffle] is true, the item at [startIndex] is pinned to index 0,
  /// and the remaining items are shuffled via Fisher-Yates without immediate repetitions.
  void setQueue(
    List<PlaylistEntry> items, {
    int startIndex = 0,
    bool shuffle = false,
  }) {
    _touch();
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

    final clampedIndex = startIndex.clamp(0, normalized.length - 1);
    _originalQueue = List<PlaylistEntry>.from(normalized);

    if (!shuffle) {
      _activeQueue = List<PlaylistEntry>.from(normalized);
      _currentIndex = clampedIndex;
      _isShuffled = false;
    } else {
      _isShuffled = true;
      final current = normalized[clampedIndex];
      final remaining = List<PlaylistEntry>.from(normalized)
        ..removeAt(clampedIndex);

      _fisherYatesShuffle(remaining);

      // Prevent immediate consecutive duplicate if adjacent track matches
      _avoidImmediateDuplicate(current, remaining);

      _activeQueue = [current, ...remaining];
      _currentIndex = 0;
    }
    _notifyNextTrack();
  }

  /// Finds the first element in [remaining] with a different filePath than [current]
  /// and moves it to index 0 to avoid immediate consecutive duplicates.
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

  /// Internal Fisher-Yates uniform random shuffle algorithm ($O(n)$ complexity).
  void _fisherYatesShuffle(List<PlaylistEntry> list) {
    for (int i = list.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = list[i];
      list[i] = list[j];
      list[j] = temp;
    }
  }

  // --------------------------------------------------------------------------
  // Shuffle & Un-shuffle Controls
  // --------------------------------------------------------------------------

  /// Toggles the shuffle state on or off.
  void toggleShuffle() => setShuffle(!_isShuffled);

  /// Sets the shuffle state explicitly.
  ///
  /// When enabling shuffle:
  /// - The currently playing track is preserved at index 0.
  /// - All other tracks are shuffled using Fisher-Yates.
  /// - No playback restart or audible disruption occurs.
  ///
  /// When disabling shuffle (Un-shuffle):
  /// - The original playlist/album sequence is 100% restored.
  /// - The current track pointer is resolved to its original position.
  void setShuffle(bool enabled) {
    if (_isShuffled == enabled) return;
    final current = currentTrack;
    if (current == null) {
      _isShuffled = enabled;
      return;
    }
    _touch();

    if (enabled) {
      // Shuffling: pin current track at index 0, shuffle remaining
      final remaining = List<PlaylistEntry>.from(_activeQueue)
        ..removeAt(_currentIndex);

      _fisherYatesShuffle(remaining);

      // Prevent immediate consecutive repetition
      _avoidImmediateDuplicate(current, remaining);

      _activeQueue = [current, ...remaining];
      _currentIndex = 0;
      _isShuffled = true;
    } else {
      // Un-shuffling: restore original order, preserving current track pointer
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
  }

  // --------------------------------------------------------------------------
  // Repeat Modes & Configuration
  // --------------------------------------------------------------------------

  /// Sets repeat mode ([Loop.off], [Loop.one], [Loop.all]).
  void setLoopMode(Loop loop) {
    if (_loopMode == loop) return;
    _loopMode = loop;
    _notifyNextTrack();
  }

  /// Cycles repeat mode in order: off -> all -> one -> off.
  Loop cycleLoopMode() {
    _loopMode = _loopMode.next();
    _notifyNextTrack();
    return _loopMode;
  }

  /// Enables or disables Infinite Library Mix.
  void setInfiniteMix(bool enabled) {
    if (_infiniteMixEnabled == enabled) return;
    _infiniteMixEnabled = enabled;
    _notifyNextTrack();
  }

  // --------------------------------------------------------------------------
  // Queue Manipulations
  // --------------------------------------------------------------------------

  /// Inserts a track immediately after the currently playing track.
  ///
  /// Updates both [_activeQueue] and [_originalQueue] (inserted after current).
  void insertNext(PlaylistEntry item) {
    _touch();
    final entry = item.copyWith(id: _nextEntryId++);
    if (_activeQueue.isEmpty) {
      _activeQueue = [entry];
      _originalQueue = [entry];
      _currentIndex = 0;
      _notifyNextTrack();
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
  }

  /// Appends tracks to the end of the queue.
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

    _activeQueue.addAll(normalized);

    if (_isShuffled) {
      _originalQueue.addAll(normalized);
    } else {
      _syncOriginalIfUnshuffled();
    }
    _notifyNextTrack();
  }

  /// Removes the track at [index] from the active queue and original queue.
  ///
  /// Adjusts [_currentIndex] appropriately if the deleted track was before or
  /// was the currently playing track. When the current track is removed, the
  /// following item becomes current (or the new last item if it was the last).
  PlaylistEntry? remove(int index) {
    if (index < 0 || index >= _activeQueue.length) return null;
    _touch();

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
    return removedItem;
  }

  /// Reorders a track from [from] index to [to] index.
  ///
  /// Updates [_currentIndex] if the moved item was the current track or
  /// if the move shifted the position of the current track.
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

    // Update current index pointer
    if (_currentIndex == from) {
      _currentIndex = to;
    } else if (from < _currentIndex && to >= _currentIndex) {
      _currentIndex--;
    } else if (from > _currentIndex && to <= _currentIndex) {
      _currentIndex++;
    }

    _syncOriginalIfUnshuffled();
    _notifyNextTrack();
  }

  /// Jumps directly to the specified [index] in the active queue.
  PlaylistEntry? jumpTo(int index) {
    if (index >= 0 && index < _activeQueue.length) {
      _currentIndex = index;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }
    return null;
  }

  /// Clears the queue.
  ///
  /// If [keepCurrent] is true and there is an active current track,
  /// that track is retained as the sole entry at index 0.
  /// Otherwise, the entire queue is emptied.
  void clear({bool keepCurrent = false}) {
    _touch();
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
  }

  // --------------------------------------------------------------------------
  // Track Navigation & Transitions
  // --------------------------------------------------------------------------

  /// Advances to the next track in the queue.
  ///
  /// Handles:
  /// - Automatic vs manual skip behavior.
  /// - [Loop.one]: auto-advance returns the **same** current item (the caller
  ///   must restart it); a manual skip moves forward as usual.
  /// - Infinite Library Mix: fetches tracks when the queue completes.
  /// - [Loop.all]: loops back to index 0.
  /// - [Loop.off]: returns null when reaching the end.
  Future<PlaylistEntry?> next({bool isManual = true}) async {
    if (_activeQueue.isEmpty) return null;

    // Loop.one check for natural/auto completion
    if (!isManual && _loopMode == Loop.one) {
      return currentTrack;
    }

    if (_currentIndex < _activeQueue.length - 1) {
      _currentIndex++;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }

    // At end of queue: check Infinite Library Mix
    final provider = libraryTrackProvider;
    if (_loopMode == Loop.off && _infiniteMixEnabled && provider != null) {
      final versionBeforeFetch = _version;
      List<Track> rawTracks;
      try {
        rawTracks = await provider(25);
      } catch (e) {
        debugPrint('[QueueManager] Infinite mix provider failed: $e');
        rawTracks = const [];
      }

      // The queue may have been mutated while awaiting the provider. Never
      // apply a stale decision: re-evaluate against the current state.
      if (versionBeforeFetch != _version) {
        return next(isManual: isManual);
      }

      if (rawTracks.isNotEmpty) {
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
          _currentIndex++;
          _notifyNextTrack();
          return currentTrack;
        }
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

    // Loop.off reached end
    return null;
  }

  /// Moves to the previous track.
  ///
  /// Returns the new current track after moving, or `null` when the caller
  /// should **restart the current track** instead:
  /// - playback progress exceeds [restartThreshold], or
  /// - there is no prior track ([Loop.off] at index 0).
  PlaylistEntry? previous({Duration position = Duration.zero}) {
    if (_activeQueue.isEmpty) return null;

    // Standard player convention: restart track if past the threshold
    if (position > restartThreshold) {
      return null;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }

    // At index 0
    if (_loopMode == Loop.all && _activeQueue.length > 1) {
      _currentIndex = _activeQueue.length - 1;
      _touch();
      _notifyNextTrack();
      return currentTrack;
    }

    return null;
  }
}
