// ignore_for_file: avoid_slow_async_io — async exists/length on dynamic file paths is correct here; no sync alternative buys anything for I/O dominant operations.
import 'dart:async';
import 'dart:io';

import 'package:awatv_core/src/models/download_task.dart';
import 'package:awatv_core/src/models/vod_item.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Manages VOD downloads for offline playback.
///
/// Internally we use a Dio `download` with a per-task [CancelToken],
/// reading the partial-file size on resume so a paused download picks
/// up where it left off via a `Range:` header. This intentionally does
/// **not** depend on `background_downloader` at the service layer —
/// the package is registered in the mobile app's `pubspec.yaml` (as
/// asked) and will eventually drive iOS/Android background fetch from
/// the app side; the core service stays platform-portable so the same
/// service can be unit-tested under `dart:io` (desktop / mobile).
///
/// Web platforms degrade gracefully — `enqueue()` writes a failed task
/// straight to storage so the UI can render the empty-state hint.
class DownloadsService {
  DownloadsService({
    required AwatvStorage storage,
    required Dio dio,
    required Future<Directory> Function() downloadsDir,
    int parallelism = 3,
  })  : _storage = storage,
        _dio = dio,
        _downloadsDir = downloadsDir,
        _parallelism = parallelism;

  final AwatvStorage _storage;
  final Dio _dio;
  final Future<Directory> Function() _downloadsDir;
  final int _parallelism;

  static final AwatvLogger _log = AwatvLogger(tag: 'DownloadsService');

  /// Active token per task — keyed by [DownloadTask.id].
  final Map<String, CancelToken> _tokens = <String, CancelToken>{};

  /// Reactive view onto persisted downloads.
  Stream<List<DownloadTask>> watch() => _storage.watchDownloads();

  /// Snapshot of persisted downloads.
  Future<List<DownloadTask>> list() => _storage.listDownloads();

  /// True when a completed download exists for [id]. Returned path can
  /// be fed straight to the player (`MediaSource(url: 'file://...')`).
  Future<String?> localPathFor(String id) async {
    final t = await _storage.getDownload(id);
    if (t == null) return null;
    if (t.status != DownloadStatus.completed) return null;
    final path = t.localPath;
    if (path == null) return null;
    if (!await File(path).exists()) return null;
    return path;
  }

  /// Convenience: same as [localPathFor] but takes a [VodItem].
  Future<String?> localPathForVod(VodItem v) => localPathFor(v.id);

  /// Enqueue a download for [item]. If a task already exists for the
  /// same id we simply resume it; the UI's "indir" button is therefore
  /// safe to spam.
  Future<DownloadTask> enqueue(VodItem item) async {
    final existing = await _storage.getDownload(item.id);
    if (existing != null) {
      switch (existing.status) {
        case DownloadStatus.completed:
        case DownloadStatus.running:
          return existing;
        case DownloadStatus.paused:
        case DownloadStatus.failed:
        case DownloadStatus.cancelled:
        case DownloadStatus.pending:
          // Fall through and re-launch.
          break;
      }
    }

    final task = existing ??
        DownloadTask(
          id: item.id,
          itemId: item.id,
          title: item.title,
          posterUrl: item.posterUrl,
          sourceUrl: item.streamUrl,
          containerExt: item.containerExt ?? 'mp4',
          status: DownloadStatus.pending,
          createdAt: DateTime.now().toUtc(),
        );
    await _storage.putDownload(task);

    if (!_isPlatformSupported()) {
      final fail = task.copyWith(
        status: DownloadStatus.failed,
        finishedAt: DateTime.now().toUtc(),
        error: 'Bu platformda indirme desteklenmiyor.',
      );
      await _storage.putDownload(fail);
      return fail;
    }

    await _maybeStart();
    return (await _storage.getDownload(task.id)) ?? task;
  }

  /// Pause an in-flight download. No-op when the task isn't running.
  Future<void> pause(String id) async {
    final tok = _tokens.remove(id);
    if (tok != null && !tok.isCancelled) {
      tok.cancel('paused');
    }
    final t = await _storage.getDownload(id);
    if (t == null) return;
    if (t.status == DownloadStatus.running ||
        t.status == DownloadStatus.pending) {
      await _storage.putDownload(t.copyWith(status: DownloadStatus.paused));
    }
    unawaited(_maybeStart());
  }

  /// Resume a previously paused / failed download.
  Future<void> resume(String id) async {
    final t = await _storage.getDownload(id);
    if (t == null) return;
    await _storage.putDownload(t.copyWith(status: DownloadStatus.pending));
    await _maybeStart();
  }

  /// Cancel — also unlinks the partial file.
  Future<void> cancel(String id) async {
    final tok = _tokens.remove(id);
    if (tok != null && !tok.isCancelled) {
      tok.cancel('cancelled');
    }
    final t = await _storage.getDownload(id);
    if (t == null) return;
    if (t.localPath != null) {
      try {
        final f = File(t.localPath!);
        if (await f.exists()) await f.delete();
      } on Object catch (e) {
        _log.warn('could not delete partial: $e');
      }
    }
    await _storage.putDownload(
      t.copyWith(
        status: DownloadStatus.cancelled,
        finishedAt: DateTime.now().toUtc(),
        bytesReceived: 0,
      ),
    );
  }

  /// Remove a finished/cancelled task (and its file).
  Future<void> delete(String id) async {
    final tok = _tokens.remove(id);
    if (tok != null && !tok.isCancelled) {
      tok.cancel('deleted');
    }
    final t = await _storage.getDownload(id);
    if (t != null && t.localPath != null) {
      try {
        final f = File(t.localPath!);
        if (await f.exists()) await f.delete();
      } on Object catch (e) {
        _log.warn('could not delete file: $e');
      }
    }
    await _storage.deleteDownload(id);
  }

  /// Total bytes occupied by completed downloads. Used by the UI
  /// "storage used" label.
  Future<int> totalBytesUsed() async {
    final all = await list();
    var total = 0;
    for (final t in all) {
      if (t.status == DownloadStatus.completed) {
        total += t.bytesReceived > 0 ? t.bytesReceived : t.totalBytes;
      }
    }
    return total;
  }

  /// Delete every completed/cancelled task. Running tasks are left
  /// untouched.
  Future<void> deleteAllFinished() async {
    final all = await list();
    for (final t in all) {
      if (t.status == DownloadStatus.completed ||
          t.status == DownloadStatus.cancelled ||
          t.status == DownloadStatus.failed) {
        await delete(t.id);
      }
    }
  }

  // ----------------------------------------------------------------------

  Future<void> _maybeStart() async {
    if (!_isPlatformSupported()) return;
    final all = await list();
    final running = all
        .where((DownloadTask t) => t.status == DownloadStatus.running)
        .length;
    if (running >= _parallelism) return;
    final pending = all
        .where((DownloadTask t) => t.status == DownloadStatus.pending)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final slots = _parallelism - running;
    for (var i = 0; i < slots && i < pending.length; i++) {
      unawaited(_runOne(pending[i]));
    }
  }

  Future<void> _runOne(DownloadTask task) async {
    if (_tokens.containsKey(task.id)) return;

    final dir = await _downloadsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final safeName = _safeFilename(task.title);
    final path = task.localPath ??
        '${dir.path}${Platform.pathSeparator}$safeName-${task.id}.${task.containerExt}';

    final existingBytes = await _safeFileSize(path);

    final headers = <String, String>{
      if (task.userAgent != null) 'User-Agent': task.userAgent!,
      if (task.referer != null) 'Referer': task.referer!,
      if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
    };

    final cancelToken = CancelToken();
    _tokens[task.id] = cancelToken;

    final running = task.copyWith(
      status: DownloadStatus.running,
      startedAt: task.startedAt ?? DateTime.now().toUtc(),
      localPath: path,
      bytesReceived: existingBytes,
    );
    await _storage.putDownload(running);

    try {
      var lastPersist = DateTime.now();
      await _dio.download(
        task.sourceUrl,
        path,
        cancelToken: cancelToken,
        deleteOnError: false,
        options: Options(
          headers: headers,
          // Some panels stall if we keep the receive timeout small —
          // disable it for long downloads.
          receiveTimeout: Duration.zero,
          // Allow 200 (initial) + 206 (range) responses.
          validateStatus: (int? status) =>
              status != null && (status == 200 || status == 206),
          followRedirects: true,
        ),
        onReceiveProgress: (int received, int total) async {
          final globalReceived = existingBytes + received;
          final globalTotal = total <= 0 ? 0 : existingBytes + total;
          final now = DateTime.now();
          // Coalesce progress writes — Hive is fast but not free.
          if (now.difference(lastPersist).inMilliseconds < 750) return;
          lastPersist = now;
          final fresh = await _storage.getDownload(task.id);
          if (fresh == null || fresh.status != DownloadStatus.running) return;
          await _storage.putDownload(
            fresh.copyWith(
              totalBytes: globalTotal > 0 ? globalTotal : fresh.totalBytes,
              bytesReceived: globalReceived,
            ),
          );
        },
      );
      _tokens.remove(task.id);
      final finalSize = await _safeFileSize(path);
      await _storage.putDownload(
        running.copyWith(
          status: DownloadStatus.completed,
          bytesReceived: finalSize,
          totalBytes: finalSize,
          finishedAt: DateTime.now().toUtc(),
        ),
      );
      unawaited(_maybeStart());
    } on DioException catch (e) {
      _tokens.remove(task.id);
      final partialSize = await _safeFileSize(path);
      if (e.type == DioExceptionType.cancel) {
        // Pause / cancel handlers already updated the status.
        unawaited(_maybeStart());
        return;
      }
      _log.warn('download failed: ${e.message}');
      await _storage.putDownload(
        running.copyWith(
          status: DownloadStatus.failed,
          bytesReceived: partialSize,
          finishedAt: DateTime.now().toUtc(),
          error: e.message ?? 'Indirme hatasi',
        ),
      );
      unawaited(_maybeStart());
    } on Object catch (e, st) {
      _tokens.remove(task.id);
      _log.warn('download crashed: $e\n$st');
      final partialSize = await _safeFileSize(path);
      await _storage.putDownload(
        running.copyWith(
          status: DownloadStatus.failed,
          bytesReceived: partialSize,
          finishedAt: DateTime.now().toUtc(),
          error: e.toString(),
        ),
      );
      unawaited(_maybeStart());
    }
  }

  Future<int> _safeFileSize(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) return f.length();
    } on Object {
      // Ignore.
    }
    return 0;
  }

  bool _isPlatformSupported() {
    try {
      return Platform.isMacOS ||
          Platform.isWindows ||
          Platform.isLinux ||
          Platform.isAndroid ||
          Platform.isIOS;
    } on Object {
      return false;
    }
  }

  String _safeFilename(String name) {
    final s = name.replaceAll(RegExp('[^a-zA-Z0-9_-]+'), '_');
    if (s.isEmpty) return 'download';
    return s.length > 60 ? s.substring(0, 60) : s;
  }
}
