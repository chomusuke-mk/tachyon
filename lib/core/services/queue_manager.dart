import 'dart:async';
import 'dart:math' as math;

import 'package:tachyon/features/library/domain/track.dart';
import 'package:tachyon/features/playback/domain/queue_item.dart';

typedef LibraryTrackProvider = Future<List<Track>> Function(int count);

/// High-performance Queue Manager for Tachyon Music Player.
///
/// Implements:
/// - Fisher-Yates shuffle pinning the currently playing track at index 0.
/// - Un-shuffle capability restoring the exact original playlist/album order
///   while preserving the active track pointer.
/// - Repeat modes: [Loop.off], [Loop.one], [Loop.all].
/// - Queue operations: [insertNext], [append], [remove], [reorder], [jumpTo], [clear].
/// - Infinite Library Mix: automatic appending of randomized library tracks
///   when the queue reaches the end and [Loop.off] is set.
class QueueManager {
  List<QueueItem> _activeQueue = [];
  List<QueueItem> _originalQueue = [];
  int _currentIndex = -1;
  bool _isShuffled = false;
  Loop _loopMode = Loop.off;
  bool _infiniteMixEnabled = false;
  int? _mixOffset;
  final LibraryTrackProvider? libraryTrackProvider;
  final math.Random _random;

  QueueManager({this.libraryTrackProvider, math.Random? random})
    : _random = random ?? math.Random();

  // --------------------------------------------------------------------------
  // Getters
  // --------------------------------------------------------------------------

  /// Read-only snapshot of the active playback queue.
  List<QueueItem> get activeQueue => List.unmodifiable(_activeQueue);

  /// Read-only snapshot of the original un-shuffled playlist sequence.
  List<QueueItem> get originalQueue => List.unmodifiable(_originalQueue);

  /// Current zero-based index into [activeQueue], or -1 if the queue is empty.
  int get currentIndex => _currentIndex;

  /// Whether the queue is currently in shuffled order.
  bool get isShuffled => _isShuffled;

  /// Current repeat mode: [Loop.off], [Loop.one], [Loop.all].
  Loop get loopMode => _loopMode;

  /// Whether Infinite Library Mix is enabled.
  bool get infiniteMixEnabled => _infiniteMixEnabled;

  /// Index where dynamically appended infinite mix tracks begin, or null.
  int? get mixOffset => _mixOffset;

  /// The currently active [QueueItem], or null if queue is empty.
  QueueItem? get currentTrack =>
      (_currentIndex >= 0 && _currentIndex < _activeQueue.length)
      ? _activeQueue[_currentIndex]
      : null;

  /// Whether there is a subsequent track available according to [loopMode].
  bool get hasNext =>
      _loopMode == Loop.all ||
      _loopMode == Loop.one ||
      _currentIndex < _activeQueue.length - 1;

  /// Whether there is a prior track available.
  bool get hasPrevious => _loopMode == Loop.all || _currentIndex > 0;

  // --------------------------------------------------------------------------
  // Queue Initialization & Reset
  // --------------------------------------------------------------------------

  /// Sets or replaces the entire queue.
  ///
  /// If [shuffle] is true, the item at [startIndex] is pinned to index 0,
  /// and the remaining items are shuffled via Fisher-Yates without immediate repetitions.
  void setQueue(
    List<QueueItem> items, {
    int startIndex = 0,
    bool shuffle = false,
  }) {
    if (items.isEmpty) {
      _activeQueue = [];
      _originalQueue = [];
      _currentIndex = -1;
      _isShuffled = false;
      _mixOffset = null;
      return;
    }

    final clampedIndex = startIndex.clamp(0, items.length - 1);
    _originalQueue = List<QueueItem>.from(items);
    _mixOffset = null;

    if (!shuffle) {
      _activeQueue = List<QueueItem>.from(items);
      _currentIndex = clampedIndex;
      _isShuffled = false;
    } else {
      _isShuffled = true;
      final current = items[clampedIndex];
      final remaining = List<QueueItem>.from(items)..removeAt(clampedIndex);

      _fisherYatesShuffle(remaining);

      // Prevent immediate consecutive duplicate if adjacent track matches
      _avoidImmediateDuplicate(current, remaining);

      _activeQueue = [current, ...remaining];
      _currentIndex = 0;
    }
  }

  /// Finds the first element in [remaining] with a different URI than [current]
  /// and moves it to index 0 to avoid immediate consecutive duplicates.
  void _avoidImmediateDuplicate(QueueItem current, List<QueueItem> remaining) {
    if (remaining.isNotEmpty &&
        remaining[0].uri == current.uri &&
        remaining.length > 1) {
      final nonDupIdx = remaining.indexWhere((it) => it.uri != current.uri);
      if (nonDupIdx != -1) {
        final nonDup = remaining.removeAt(nonDupIdx);
        remaining.insert(0, nonDup);
      }
    }
  }

  /// Internal Fisher-Yates uniform random shuffle algorithm ($O(n)$ complexity).
  void _fisherYatesShuffle(List<QueueItem> list) {
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
    if (_activeQueue.isEmpty) {
      _isShuffled = enabled;
      return;
    }

    if (enabled) {
      // Shuffling: pin current track at index 0, shuffle remaining
      final current = _activeQueue[_currentIndex];
      final remaining = List<QueueItem>.from(_activeQueue)
        ..removeAt(_currentIndex);

      _fisherYatesShuffle(remaining);

      // Prevent immediate consecutive repetition
      _avoidImmediateDuplicate(current, remaining);

      _activeQueue = [current, ...remaining];
      _currentIndex = 0;
      _isShuffled = true;
    } else {
      // Un-shuffling: restore original order, preserving current track pointer
      final current = _activeQueue[_currentIndex];
      int origIdx = _originalQueue.indexWhere((item) => item.id == current.id);
      if (origIdx == -1) {
        origIdx = _originalQueue.indexWhere((item) => item.uri == current.uri);
      }

      _activeQueue = List<QueueItem>.from(_originalQueue);
      if (origIdx != -1) {
        _currentIndex = origIdx;
      } else {
        _currentIndex = _currentIndex.clamp(0, _activeQueue.length - 1);
      }
      _isShuffled = false;
    }
  }

  // --------------------------------------------------------------------------
  // Repeat Modes & Configuration
  // --------------------------------------------------------------------------

  /// Sets repeat mode ([Loop.off], [Loop.one], [Loop.all]).
  void setLoopMode(Loop loop) {
    _loopMode = loop;
  }

  /// Cycles repeat mode in order: off -> all -> one -> off.
  Loop cycleLoopMode() {
    _loopMode = _loopMode.next();
    return _loopMode;
  }

  /// Enables or disables Infinite Library Mix.
  void setInfiniteMix(bool enabled) {
    _infiniteMixEnabled = enabled;
  }

  // --------------------------------------------------------------------------
  // Queue Manipulations
  // --------------------------------------------------------------------------

  /// Inserts a track immediately after the currently playing track.
  ///
  /// Updates both [_activeQueue] and [_originalQueue] (inserted after current).
  void insertNext(QueueItem item) {
    if (_activeQueue.isEmpty) {
      _activeQueue = [item];
      _originalQueue = [item];
      _currentIndex = 0;
      return;
    }

    final insertIdx = _currentIndex + 1;
    _activeQueue.insert(insertIdx, item);

    if (_isShuffled) {
      final current = _activeQueue[_currentIndex];
      final origIdx = _originalQueue.indexWhere((it) => it.id == current.id);
      if (origIdx != -1) {
        _originalQueue.insert(origIdx + 1, item);
      } else {
        _originalQueue.add(item);
      }
    } else {
      _originalQueue.insert(insertIdx, item);
    }

    if (_mixOffset != null && insertIdx <= _mixOffset!) {
      _mixOffset = _mixOffset! + 1;
    }
  }

  /// Appends tracks to the end of the queue.
  ///
  /// If Infinite Library Mix is active, items are inserted prior to the mix tracks.
  void append(List<QueueItem> items) {
    if (items.isEmpty) return;

    if (_activeQueue.isEmpty) {
      setQueue(items);
      return;
    }

    final currentMixOffset = _mixOffset;
    if (currentMixOffset != null) {
      _activeQueue.insertAll(currentMixOffset, items);
      _mixOffset = currentMixOffset + items.length;
      _originalQueue.addAll(items);
    } else {
      _activeQueue.addAll(items);
      _originalQueue.addAll(items);
    }
  }

  /// Removes the track at [index] from the active queue and original queue.
  ///
  /// Adjusts [_currentIndex] appropriately if the deleted track was before or
  /// was the currently playing track.
  QueueItem? remove(int index) {
    if (index < 0 || index >= _activeQueue.length) return null;

    final removedItem = _activeQueue.removeAt(index);
    if (!_isShuffled) {
      if (index < _originalQueue.length) {
        _originalQueue.removeAt(index);
      }
    } else {
      int origIdx = _originalQueue.indexWhere((it) => it.id == removedItem.id);
      if (origIdx == -1) {
        origIdx = _originalQueue.indexWhere((it) => it.uri == removedItem.uri);
      }
      if (origIdx != -1) {
        _originalQueue.removeAt(origIdx);
      }
    }

    final currentMixOffset = _mixOffset;
    if (currentMixOffset != null) {
      if (index < currentMixOffset) {
        _mixOffset = currentMixOffset - 1;
      } else if (_activeQueue.length <= currentMixOffset) {
        _mixOffset = null;
      }
    }

    if (_activeQueue.isEmpty) {
      _currentIndex = -1;
      return removedItem;
    }

    if (index < _currentIndex) {
      _currentIndex--;
    } else if (index == _currentIndex) {
      if (_currentIndex >= _activeQueue.length) {
        _currentIndex = _activeQueue.length - 1;
      }
    }

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

    if (!_isShuffled) {
      final origItem = _originalQueue.removeAt(from);
      _originalQueue.insert(to, origItem);
    }
  }

  /// Jumps directly to the specified [index] in the active queue.
  QueueItem? jumpTo(int index) {
    if (index >= 0 && index < _activeQueue.length) {
      _currentIndex = index;
      return currentTrack;
    }
    return null;
  }

  /// Clears the entire queue.
  void clear() {
    _activeQueue.clear();
    _originalQueue.clear();
    _currentIndex = -1;
    _isShuffled = false;
    _mixOffset = null;
  }

  // --------------------------------------------------------------------------
  // Track Navigation & Transitions
  // --------------------------------------------------------------------------

  /// Advances to the next track in the queue.
  ///
  /// Handles:
  /// - Automatic vs manual skip behavior.
  /// - [Loop.one]: auto-advance repeats the same track without crossfade.
  /// - Infinite Library Mix: fetches tracks when the queue completes.
  /// - [Loop.all]: loops back to index 0.
  /// - [Loop.off]: returns null when reaching the end.
  Future<QueueItem?> next({bool isManual = true}) async {
    if (_activeQueue.isEmpty) return null;

    // Loop.one check for natural/auto completion
    if (!isManual && _loopMode == Loop.one) {
      return currentTrack;
    }

    if (_currentIndex < _activeQueue.length - 1) {
      _currentIndex++;
      return currentTrack;
    }

    // At end of queue: check Infinite Library Mix
    final provider = libraryTrackProvider;
    if (_loopMode == Loop.off && _infiniteMixEnabled && provider != null) {
      final rawTracks = await provider(25);
      if (rawTracks.isNotEmpty) {
        final existingUris = _activeQueue.map((it) => it.uri).toSet();
        var mixTracks = rawTracks
            .where((t) => !existingUris.contains(t.uri))
            .map((t) => QueueItem.fromTrack(t))
            .toList();

        if (mixTracks.isEmpty) {
          mixTracks = rawTracks.map((t) => QueueItem.fromTrack(t)).toList();
        }

        if (mixTracks.isNotEmpty) {
          _mixOffset ??= _activeQueue.length;
          _activeQueue.addAll(mixTracks);
          _originalQueue.addAll(mixTracks);
          _currentIndex++;
          return currentTrack;
        }
      }
    }

    if (_loopMode == Loop.all) {
      _currentIndex = 0;
      return currentTrack;
    }

    if (_loopMode == Loop.one && isManual) {
      _currentIndex = 0;
      return currentTrack;
    }

    // Loop.off reached end
    return null;
  }

  /// Moves to the previous track or restarts the current track.
  ///
  /// If playback progress exceeds 3 seconds, returns currentTrack to prompt
  /// the player engine to seek to beginning.
  QueueItem? previous({Duration position = Duration.zero}) {
    if (_activeQueue.isEmpty) return null;

    // Standard player convention: restart track if > 3 seconds in
    if (position.inSeconds > 3) {
      return currentTrack;
    }

    if (_currentIndex > 0) {
      _currentIndex--;
      return currentTrack;
    }

    // At index 0
    if (_loopMode == Loop.all) {
      _currentIndex = _activeQueue.length - 1;
      return currentTrack;
    }

    return currentTrack;
  }
}
