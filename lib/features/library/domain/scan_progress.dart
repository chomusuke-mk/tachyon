import 'package:flutter/foundation.dart';

/// Phase states of the library scan lifecycle.
enum ScanPhase {
  idle,
  discovering,
  extracting,
  persisting,
  completed,
  failed,
  cancelled,
}

/// Immutable state snapshot emitted during library scanning.
@immutable
class ScanProgress {
  final ScanPhase phase;
  final String? currentFile;
  final int scannedFiles;
  final int totalFiles;
  final int newTracks;
  final int updatedTracks;
  final int skippedTracks;
  final int failedTracks;
  final double progress;
  final String? errorMessage;
  final Duration elapsedTime;

  const ScanProgress({
    this.phase = ScanPhase.idle,
    this.currentFile,
    this.scannedFiles = 0,
    this.totalFiles = 0,
    this.newTracks = 0,
    this.updatedTracks = 0,
    this.skippedTracks = 0,
    this.failedTracks = 0,
    this.progress = 0.0,
    this.errorMessage,
    this.elapsedTime = Duration.zero,
  });

  bool get isRunning =>
      phase == ScanPhase.discovering ||
      phase == ScanPhase.extracting ||
      phase == ScanPhase.persisting;

  bool get isDone =>
      phase == ScanPhase.completed ||
      phase == ScanPhase.failed ||
      phase == ScanPhase.cancelled;

  ScanProgress copyWith({
    ScanPhase? phase,
    String? currentFile,
    bool clearCurrentFile = false,
    int? scannedFiles,
    int? totalFiles,
    int? newTracks,
    int? updatedTracks,
    int? skippedTracks,
    int? failedTracks,
    double? progress,
    String? errorMessage,
    Duration? elapsedTime,
  }) {
    return ScanProgress(
      phase: phase ?? this.phase,
      currentFile: clearCurrentFile ? null : (currentFile ?? this.currentFile),
      scannedFiles: scannedFiles ?? this.scannedFiles,
      totalFiles: totalFiles ?? this.totalFiles,
      newTracks: newTracks ?? this.newTracks,
      updatedTracks: updatedTracks ?? this.updatedTracks,
      skippedTracks: skippedTracks ?? this.skippedTracks,
      failedTracks: failedTracks ?? this.failedTracks,
      progress: progress ?? this.progress,
      errorMessage: errorMessage ?? this.errorMessage,
      elapsedTime: elapsedTime ?? this.elapsedTime,
    );
  }

  /// Serializes this instance to a plain [Map] that can cross Isolate boundaries.
  Map<String, dynamic> toJson() => {
    'phase': phase.name,
    'currentFile': currentFile,
    'scannedFiles': scannedFiles,
    'totalFiles': totalFiles,
    'newTracks': newTracks,
    'updatedTracks': updatedTracks,
    'skippedTracks': skippedTracks,
    'failedTracks': failedTracks,
    'progress': progress,
    'errorMessage': errorMessage,
    'elapsedMs': elapsedTime.inMilliseconds,
  };

  /// Deserializes a [Map] received from a secondary Isolate back into a [ScanProgress].
  factory ScanProgress.fromJson(Map<String, dynamic> json) {
    final phaseName = json['phase'] as String? ?? 'idle';
    final phase = ScanPhase.values.firstWhere(
      (e) => e.name == phaseName,
      orElse: () => ScanPhase.idle,
    );
    return ScanProgress(
      phase: phase,
      currentFile: json['currentFile'] as String?,
      scannedFiles: (json['scannedFiles'] as num?)?.toInt() ?? 0,
      totalFiles: (json['totalFiles'] as num?)?.toInt() ?? 0,
      newTracks: (json['newTracks'] as num?)?.toInt() ?? 0,
      updatedTracks: (json['updatedTracks'] as num?)?.toInt() ?? 0,
      skippedTracks: (json['skippedTracks'] as num?)?.toInt() ?? 0,
      failedTracks: (json['failedTracks'] as num?)?.toInt() ?? 0,
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      errorMessage: json['errorMessage'] as String?,
      elapsedTime: Duration(
        milliseconds: (json['elapsedMs'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanProgress &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          currentFile == other.currentFile &&
          scannedFiles == other.scannedFiles &&
          totalFiles == other.totalFiles &&
          newTracks == other.newTracks &&
          updatedTracks == other.updatedTracks &&
          skippedTracks == other.skippedTracks &&
          failedTracks == other.failedTracks &&
          progress == other.progress &&
          errorMessage == other.errorMessage &&
          elapsedTime == other.elapsedTime;

  @override
  int get hashCode => Object.hash(
    phase,
    currentFile,
    scannedFiles,
    totalFiles,
    newTracks,
    updatedTracks,
    skippedTracks,
    failedTracks,
    progress,
    errorMessage,
    elapsedTime,
  );

  @override
  String toString() =>
      'ScanProgress($phase: $scannedFiles/$totalFiles, new: $newTracks, updated: $updatedTracks, skipped: $skippedTracks, ${(progress * 100).toStringAsFixed(1)}%)';
}

/// Token enabling cooperative cancellation of asynchronous scan pipelines.
class CancellationToken {
  bool _isCancelled = false;
  final List<VoidCallback> _callbacks = [];

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final callback in _callbacks) {
      try {
        callback();
      } catch (_) {}
    }
    _callbacks.clear();
  }

  void onCancel(VoidCallback callback) {
    if (_isCancelled) {
      callback();
    } else {
      _callbacks.add(callback);
    }
  }
}
