import 'package:meta/meta.dart';

/// Lifecycle state of a recording.
///
/// Sealed-class-style enum + a small status payload (path, error,
/// timestamps). The [RecordingTask.copyWith] helpers make state
/// transitions explicit so the service stays in lockstep with what
/// the UI sees from the watch stream.
enum RecordingStatus {
  /// Persisted but not started yet — used for scheduled recordings
  /// whose `scheduledAt` is still in the future.
  scheduled,

  /// Currently writing bytes to disk.
  running,

  /// Stopped successfully — output file exists at [RecordingTask.outputPath].
  completed,

  /// Stopped with an error — see [RecordingTask.error].
  failed,

  /// User cancelled before completion (file may be partial / removed).
  cancelled,
}

/// Backend used to record. We pick this once per task so a task that
/// succeeded with `ffmpeg` re-attempts with `ffmpeg` on retry instead
/// of accidentally falling through to the slower Dart copy path.
enum RecordingBackend {
  /// Bundled / system ffmpeg detected at start time (`which ffmpeg`).
  ffmpeg,

  /// Pure-Dart stream copy via Dio. Lower fidelity (TS only) but works
  /// when ffmpeg isn't installed.
  dioCopy,

  /// No valid backend on this platform (web, restricted sandbox).
  unsupported,
}

/// One scheduled / running / finished recording.
@immutable
class RecordingTask {
  const RecordingTask({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.streamUrl,
    required this.status,
    required this.createdAt,
    this.backend = RecordingBackend.dioCopy,
    this.scheduledAt,
    this.startedAt,
    this.finishedAt,
    this.duration,
    this.bytesWritten = 0,
    this.outputPath,
    this.posterUrl,
    this.error,
    this.userAgent,
    this.referer,
  });

  /// Stable id (UUID) — Hive key.
  final String id;

  /// Channel this recording came from. Used when restoring after restart.
  final String channelId;

  /// Display name (channel title) — denormalized so the UI can render
  /// rows without a second lookup.
  final String channelName;

  /// Source URL (resolved playable URL at time of scheduling).
  final String streamUrl;

  /// Optional logo for thumbnails.
  final String? posterUrl;

  /// Lifecycle.
  final RecordingStatus status;

  /// Backend the task is or was using.
  final RecordingBackend backend;

  /// When the task entered the queue.
  final DateTime createdAt;

  /// When the task should auto-start. Null for "right now".
  final DateTime? scheduledAt;

  /// When recording actually began.
  final DateTime? startedAt;

  /// When recording stopped (success, failure, cancel).
  final DateTime? finishedAt;

  /// Target duration. Null for "until user stops".
  final Duration? duration;

  /// Bytes written so far — used for progress UI on running tasks and
  /// final size on completed ones.
  final int bytesWritten;

  /// Absolute path on disk once the file exists.
  final String? outputPath;

  /// Last error message — only set when [status] == [RecordingStatus.failed].
  final String? error;

  /// HTTP `User-Agent` header to set on the request.
  final String? userAgent;

  /// HTTP `Referer` header — required by some panels.
  final String? referer;

  RecordingTask copyWith({
    RecordingStatus? status,
    RecordingBackend? backend,
    DateTime? startedAt,
    DateTime? finishedAt,
    Duration? duration,
    int? bytesWritten,
    String? outputPath,
    String? error,
  }) {
    return RecordingTask(
      id: id,
      channelId: channelId,
      channelName: channelName,
      streamUrl: streamUrl,
      posterUrl: posterUrl,
      status: status ?? this.status,
      backend: backend ?? this.backend,
      createdAt: createdAt,
      scheduledAt: scheduledAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      duration: duration ?? this.duration,
      bytesWritten: bytesWritten ?? this.bytesWritten,
      outputPath: outputPath ?? this.outputPath,
      error: error ?? this.error,
      userAgent: userAgent,
      referer: referer,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'channelId': channelId,
        'channelName': channelName,
        'streamUrl': streamUrl,
        'posterUrl': posterUrl,
        'status': status.name,
        'backend': backend.name,
        'createdAt': createdAt.toIso8601String(),
        'scheduledAt': scheduledAt?.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'durationMs': duration?.inMilliseconds,
        'bytesWritten': bytesWritten,
        'outputPath': outputPath,
        'error': error,
        'userAgent': userAgent,
        'referer': referer,
      };

  factory RecordingTask.fromJson(Map<String, dynamic> json) {
    return RecordingTask(
      id: json['id'] as String,
      channelId: json['channelId'] as String,
      channelName: json['channelName'] as String,
      streamUrl: json['streamUrl'] as String,
      posterUrl: json['posterUrl'] as String?,
      status: RecordingStatus.values.firstWhere(
        (RecordingStatus s) => s.name == json['status'],
        orElse: () => RecordingStatus.scheduled,
      ),
      backend: RecordingBackend.values.firstWhere(
        (RecordingBackend b) => b.name == json['backend'],
        orElse: () => RecordingBackend.dioCopy,
      ),
      createdAt: DateTime.parse(json['createdAt'] as String),
      scheduledAt: json['scheduledAt'] == null
          ? null
          : DateTime.parse(json['scheduledAt'] as String),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      duration: json['durationMs'] == null
          ? null
          : Duration(milliseconds: (json['durationMs'] as num).toInt()),
      bytesWritten: (json['bytesWritten'] as num?)?.toInt() ?? 0,
      outputPath: json['outputPath'] as String?,
      error: json['error'] as String?,
      userAgent: json['userAgent'] as String?,
      referer: json['referer'] as String?,
    );
  }
}
