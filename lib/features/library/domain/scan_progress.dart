import 'package:flutter/foundation.dart';

/// Stage states of the library scan lifecycle.
enum ScanStage {
  idle,
  gettingDatabase,
  gettingTracks,
  discovering,
  comparing,
  extracting,
  inserting,
  cleaningOrphans,
  cleaningThumbnails,
  completed,
  failed,
  cancelled,
}

/// Immutable state snapshot emitted during library scanning.
@immutable
class ScanProgress {
  final ScanStage stage;
  final String? progressLabel;
  final double? progressValue;
  final String? errorMessage;

  const ScanProgress({
    this.stage = ScanStage.idle,
    this.progressLabel,
    this.progressValue,
    this.errorMessage,
  });

  bool get isRunning =>
      stage != ScanStage.idle &&
      stage != ScanStage.completed &&
      stage != ScanStage.failed &&
      stage != ScanStage.cancelled;

  bool get isDone =>
      stage == ScanStage.completed ||
      stage == ScanStage.failed ||
      stage == ScanStage.cancelled;

  ScanProgress copyWith({
    ScanStage? stage,
    String? progressLabel,
    bool clearProgressLabel = false,
    double? progressValue,
    bool clearProgressValue = false,
    String? errorMessage,
    bool clearErrorMessage = false,
  }) {
    return ScanProgress(
      stage: stage ?? this.stage,
      progressLabel: clearProgressLabel
          ? null
          : (progressLabel ?? this.progressLabel),
      progressValue: clearProgressValue
          ? null
          : (progressValue ?? this.progressValue),
      errorMessage: clearErrorMessage
          ? null
          : (errorMessage ?? this.errorMessage),
    );
  }

  /// Serializes this instance to a plain [Map] that can cross Isolate boundaries.
  Map<String, dynamic> toJson() => {
    'stage': stage.name,
    'progressLabel': progressLabel,
    'progressValue': progressValue,
    'errorMessage': errorMessage,
  };

  /// Deserializes a [Map] received from a secondary Isolate back into a [ScanProgress].
  factory ScanProgress.fromJson(Map<String, dynamic> json) {
    final stageName = json['stage'] as String? ?? 'idle';
    final stage = ScanStage.values.firstWhere(
      (e) => e.name == stageName,
      orElse: () => ScanStage.idle,
    );
    return ScanProgress(
      stage: stage,
      progressLabel: json['progressLabel'] as String?,
      progressValue: (json['progressValue'] as num?)?.toDouble(),
      errorMessage: json['errorMessage'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScanProgress &&
          runtimeType == other.runtimeType &&
          stage == other.stage &&
          progressLabel == other.progressLabel &&
          progressValue == other.progressValue &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode =>
      Object.hash(stage, progressLabel, progressValue, errorMessage);

  @override
  String toString() =>
      'ScanProgress($stage, label: $progressLabel, value: $progressValue, error: $errorMessage)';
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
