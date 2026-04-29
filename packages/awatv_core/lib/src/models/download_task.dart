import 'package:meta/meta.dart';

/// Lifecycle of a VOD download.
enum DownloadStatus {
  /// In the queue, waiting for a slot under the parallelism cap.
  pending,

  /// Bytes are flowing right now.
  running,

  /// User paused. Resumable.
  paused,

  /// Finished — file exists at [DownloadTask.localPath].
  completed,

  /// Stopped with an error. See [DownloadTask.error].
  failed,

  /// User cancelled (file deleted).
  cancelled,
}

/// Persistable model for a single VOD download.
///
/// Designed to round-trip through Hive as JSON so we don't need to
/// register a `TypeAdapter` (matching the rest of `AwatvStorage`).
@immutable
class DownloadTask {
  const DownloadTask({
    required this.id,
    required this.itemId,
    required this.title,
    required this.sourceUrl,
    required this.status,
    required this.createdAt,
    this.posterUrl,
    this.containerExt = 'mp4',
    this.totalBytes = 0,
    this.bytesReceived = 0,
    this.localPath,
    this.startedAt,
    this.finishedAt,
    this.error,
    this.userAgent,
    this.referer,
  });

  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      itemId: (json['itemId'] as String?) ?? json['id'] as String,
      title: json['title'] as String,
      posterUrl: json['posterUrl'] as String?,
      sourceUrl: json['sourceUrl'] as String,
      containerExt: (json['containerExt'] as String?) ?? 'mp4',
      status: DownloadStatus.values.firstWhere(
        (DownloadStatus s) => s.name == json['status'],
        orElse: () => DownloadStatus.pending,
      ),
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      bytesReceived: (json['bytesReceived'] as num?)?.toInt() ?? 0,
      localPath: json['localPath'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      startedAt: json['startedAt'] == null
          ? null
          : DateTime.parse(json['startedAt'] as String),
      finishedAt: json['finishedAt'] == null
          ? null
          : DateTime.parse(json['finishedAt'] as String),
      error: json['error'] as String?,
      userAgent: json['userAgent'] as String?,
      referer: json['referer'] as String?,
    );
  }

  /// Stable id (typically the VOD id) used as the Hive key.
  final String id;

  /// Underlying VOD/episode id — same as [id] in the common case but kept
  /// separate because the player uses [id] for history bucketing and we
  /// want a reliable resolution when the keys diverge in the future.
  final String itemId;

  /// Display title (movie or episode title).
  final String title;

  /// Optional poster for thumbnails.
  final String? posterUrl;

  /// HTTPS URL we're downloading from.
  final String sourceUrl;

  /// File extension we'll write to disk (without the dot). Defaults to
  /// `mp4`; Xtream routinely serves `mp4` / `mkv` / `m4v`.
  final String containerExt;

  /// Lifecycle.
  final DownloadStatus status;

  /// Total bytes — known once the first response lands and we've read
  /// `Content-Length`. 0 means "unknown".
  final int totalBytes;

  /// Bytes written so far.
  final int bytesReceived;

  /// Absolute path on disk. Set as soon as the destination is decided so
  /// the player can resolve a partial-file path during paused states.
  final String? localPath;

  /// Timestamps.
  final DateTime createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  /// Last error message.
  final String? error;

  /// HTTP `User-Agent` header to set on the request.
  final String? userAgent;

  /// HTTP `Referer` header — required by some panels.
  final String? referer;

  /// Convenience: progress in [0,1]. Returns 0 when [totalBytes] is
  /// unknown.
  double get progress {
    if (totalBytes <= 0) return 0;
    if (bytesReceived <= 0) return 0;
    final p = bytesReceived / totalBytes;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }

  DownloadTask copyWith({
    DownloadStatus? status,
    int? totalBytes,
    int? bytesReceived,
    String? localPath,
    DateTime? startedAt,
    DateTime? finishedAt,
    String? error,
  }) {
    return DownloadTask(
      id: id,
      itemId: itemId,
      title: title,
      posterUrl: posterUrl,
      sourceUrl: sourceUrl,
      containerExt: containerExt,
      status: status ?? this.status,
      totalBytes: totalBytes ?? this.totalBytes,
      bytesReceived: bytesReceived ?? this.bytesReceived,
      localPath: localPath ?? this.localPath,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
      error: error ?? this.error,
      userAgent: userAgent,
      referer: referer,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'itemId': itemId,
        'title': title,
        'posterUrl': posterUrl,
        'sourceUrl': sourceUrl,
        'containerExt': containerExt,
        'status': status.name,
        'totalBytes': totalBytes,
        'bytesReceived': bytesReceived,
        'localPath': localPath,
        'createdAt': createdAt.toIso8601String(),
        'startedAt': startedAt?.toIso8601String(),
        'finishedAt': finishedAt?.toIso8601String(),
        'error': error,
        'userAgent': userAgent,
        'referer': referer,
      };
}
