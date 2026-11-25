import 'package:flutter/foundation.dart';
export 'package:tachyon/shared/utils/cancellation_token.dart'
    show CancellationToken;

/// Stage states of the library scan lifecycle.
enum ScanStage {
  /// No scan is currently active.
  idle,

  /// Acquiring and preparing the database connection.
  gettingDatabase,

  /// Loading existing track records for incremental comparison.
  gettingTracks,

  /// Enumerating audio files across target directories and sources.
  discovering,

  /// Comparing discovered files against stored timestamps to detect changes.
  comparing,

  /// Extracting tags, audio properties, artwork, and waveforms.
  extracting,

  /// Writing extracted track records into the database.
  inserting,

  /// Removing deleted tracks and orphaned artists, albums, and genres.
  cleaningOrphans,

  /// Purging unused cover art files from thumbnail storage.
  cleaningThumbnails,

  /// Library scan finished successfully.
  completed,

  /// Library scan terminated with an error.
  failed,

  /// Library scan was cancelled before completion.
  cancelled,
}

/// Immutable state snapshot emitted during library scanning.
@immutable
class ScanProgress {
  /// Current stage of the scan lifecycle.
  final ScanStage stage;

  /// Optional human-readable progress counter label (for example `'12/100'`).
  final String? progressLabel;

  /// Optional normalized progress fraction between `0.0` and `1.0`.
  final double? progressValue;

  /// Error description when [stage] is [ScanStage.failed], if available.
  final String? errorMessage;

  /// Whether the scan added, updated, or removed any catalog records.
  final bool catalogModified;

  /// Creates a [ScanProgress] snapshot for [stage] and optional progress details.
  const ScanProgress({
    this.stage = ScanStage.idle,
    this.progressLabel,
    this.progressValue,
    this.errorMessage,
    this.catalogModified = true,
  });

  /// Whether the scan is currently active and has not finished.
  bool get isRunning =>
      stage != ScanStage.idle &&
      stage != ScanStage.completed &&
      stage != ScanStage.failed &&
      stage != ScanStage.cancelled;

  /// Whether the scan has reached a terminal state ([ScanStage.completed], [ScanStage.failed], or [ScanStage.cancelled]).
  bool get isDone =>
      stage == ScanStage.completed ||
      stage == ScanStage.failed ||
      stage == ScanStage.cancelled;

  /// Returns a copy of this [ScanProgress] with the specified fields updated.
  ///
  /// Setting [clearProgressLabel], [clearProgressValue], or [clearErrorMessage]
  /// to `true` explicitly resets the corresponding field to `null`.
  ScanProgress copyWith({
    ScanStage? stage,
    String? progressLabel,
    bool clearProgressLabel = false,
    double? progressValue,
    bool clearProgressValue = false,
    String? errorMessage,
    bool clearErrorMessage = false,
    bool? catalogModified,
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
      catalogModified: catalogModified ?? this.catalogModified,
    );
  }

  /// Serializes this instance to a plain [Map].
  Map<String, dynamic> toJson() => {
    'stage': stage.name,
    'progressLabel': progressLabel,
    'progressValue': progressValue,
    'errorMessage': errorMessage,
    'catalogModified': catalogModified,
  };

  /// Deserializes a plain [Map] back into a [ScanProgress].
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
      catalogModified: json['catalogModified'] as bool? ?? true,
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
          errorMessage == other.errorMessage &&
          catalogModified == other.catalogModified;

  @override
  int get hashCode => Object.hash(
    stage,
    progressLabel,
    progressValue,
    errorMessage,
    catalogModified,
  );

  @override
  String toString() =>
      'ScanProgress($stage, label: $progressLabel, value: $progressValue, error: $errorMessage)';
}
