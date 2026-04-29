// ignore_for_file: avoid_slow_async_io — async exists/length on dynamic file paths is correct here; no sync alternative buys anything for I/O dominant operations.
import 'dart:async';
import 'dart:io';

import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/models/recording_task.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';

/// Records live channels to disk.
///
/// Two recording strategies, picked at start time:
///   1. **ffmpeg** — when a `ffmpeg` binary is on `PATH`. We spawn
///      `ffmpeg -i <stream> -c copy -t <duration> <out.mp4>` so we
///      remux without re-encoding. Best fidelity, lowest CPU.
///   2. **Dio stream-copy** — pure-Dart fallback. Streams the URL into
///      a `.ts` file. Works for HLS/TS panels (Xtream live is TS) but
///      can't repackage `.m3u8` HLS into mp4, and produces a slightly
///      bigger file. No external deps.
///
/// On unsupported platforms (web, restricted desktop sandbox) the
/// service refuses cleanly with [RecordingBackend.unsupported] so the
/// UI can surface an empty-state hint.
class RecordingService {
  RecordingService({
    required AwatvStorage storage,
    required Dio dio,
    required Future<Directory> Function() recordingsDir,
  })  : _storage = storage,
        _dio = dio,
        _recordingsDir = recordingsDir;

  final AwatvStorage _storage;
  final Dio _dio;
  final Future<Directory> Function() _recordingsDir;

  static final AwatvLogger _log = AwatvLogger(tag: 'RecordingService');

  /// Per-task running state. Keyed by [RecordingTask.id].
  final Map<String, _ActiveRecording> _active = <String, _ActiveRecording>{};

  /// Periodic timer that watches the persisted task list for
  /// scheduled recordings whose start time has arrived.
  Timer? _scheduleTimer;

  /// Reactive view onto persisted recordings.
  Stream<List<RecordingTask>> watch() => _storage.watchRecordings();

  /// Snapshot of persisted recordings.
  Future<List<RecordingTask>> list() => _storage.listRecordings();

  /// Active recordings — includes both [RecordingStatus.running] and
  /// [RecordingStatus.scheduled] entries.
  Future<List<RecordingTask>> active() async {
    final all = await list();
    return all
        .where((RecordingTask t) =>
            t.status == RecordingStatus.running ||
            t.status == RecordingStatus.scheduled)
        .toList();
  }

  /// Bootstraps the schedule poller. Idempotent — safe to call from
  /// app boot and repeated provider creations.
  void boot() {
    _scheduleTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _poll(),
    );
    // Run once immediately so a freshly-launched app picks up tasks
    // whose `scheduledAt` is already in the past.
    unawaited(_poll());
  }

  Future<void> dispose() async {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    final ids = _active.keys.toList();
    for (final id in ids) {
      await stop(id);
    }
  }

  /// Schedule a future recording.
  Future<RecordingTask> schedule({
    required Channel channel,
    required DateTime startAt,
    required Duration duration,
  }) async {
    final task = RecordingTask(
      id: const Uuid().v4(),
      channelId: channel.id,
      channelName: channel.name,
      streamUrl: channel.streamUrl,
      posterUrl: channel.logoUrl,
      status: RecordingStatus.scheduled,
      createdAt: DateTime.now().toUtc(),
      scheduledAt: startAt.toUtc(),
      duration: duration,
      userAgent: channel.extras['http-user-agent'] ??
          channel.extras['user-agent'],
      referer: channel.extras['http-referrer'] ??
          channel.extras['referer'] ??
          channel.extras['Referer'],
    );
    await _storage.putRecording(task);
    return task;
  }

  /// Start a recording immediately. Returns the persisted [RecordingTask]
  /// once the bytes have started flowing (or once the failure has been
  /// captured to disk for the UI to display).
  Future<RecordingTask> start(
    Channel channel, {
    Duration? duration,
  }) async {
    final task = RecordingTask(
      id: const Uuid().v4(),
      channelId: channel.id,
      channelName: channel.name,
      streamUrl: channel.streamUrl,
      posterUrl: channel.logoUrl,
      status: RecordingStatus.scheduled,
      createdAt: DateTime.now().toUtc(),
      duration: duration,
      userAgent: channel.extras['http-user-agent'] ??
          channel.extras['user-agent'],
      referer: channel.extras['http-referrer'] ??
          channel.extras['referer'] ??
          channel.extras['Referer'],
    );
    await _storage.putRecording(task);
    await _launch(task);
    return (await _findById(task.id)) ?? task;
  }

  /// Stop an active recording. No-op when the task is not running.
  Future<void> stop(String taskId) async {
    final active = _active.remove(taskId);
    if (active != null) {
      await active.cancel();
    }
    final t = await _findById(taskId);
    if (t == null) return;
    if (t.status == RecordingStatus.running) {
      await _storage.putRecording(
        t.copyWith(
          status: RecordingStatus.completed,
          finishedAt: DateTime.now().toUtc(),
        ),
      );
    } else if (t.status == RecordingStatus.scheduled) {
      await _storage.putRecording(
        t.copyWith(
          status: RecordingStatus.cancelled,
          finishedAt: DateTime.now().toUtc(),
        ),
      );
    }
  }

  /// Delete a recording — also unlinks the file when the task is
  /// completed.
  Future<void> delete(String taskId) async {
    final t = await _findById(taskId);
    if (t != null && t.outputPath != null) {
      try {
        final f = File(t.outputPath!);
        if (await f.exists()) await f.delete();
      } on Object catch (e) {
        _log.warn('could not delete recording file: $e');
      }
    }
    final active = _active.remove(taskId);
    if (active != null) {
      await active.cancel();
    }
    await _storage.deleteRecording(taskId);
  }

  // ----------------------------------------------------------------------

  Future<RecordingTask?> _findById(String id) async {
    final all = await _storage.listRecordings();
    for (final t in all) {
      if (t.id == id) return t;
    }
    return null;
  }

  Future<void> _poll() async {
    final all = await _storage.listRecordings();
    final now = DateTime.now().toUtc();
    for (final t in all) {
      if (t.status != RecordingStatus.scheduled) continue;
      final at = t.scheduledAt;
      if (at == null) continue;
      if (now.isBefore(at)) continue;
      if (_active.containsKey(t.id)) continue;
      await _launch(t);
    }
  }

  Future<void> _launch(RecordingTask task) async {
    if (_active.containsKey(task.id)) return;

    // Web / unsupported platforms — write the failure straight to the
    // task so the UI can surface "Sadece masaustu/mobil uygulamada".
    if (!_isPlatformSupported()) {
      await _storage.putRecording(
        task.copyWith(
          status: RecordingStatus.failed,
          backend: RecordingBackend.unsupported,
          finishedAt: DateTime.now().toUtc(),
          error: 'Bu platformda kayit desteklenmiyor.',
        ),
      );
      return;
    }

    final dir = await _recordingsDir();
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    final ffmpeg = await _ffmpegPath();
    final backend = ffmpeg != null
        ? RecordingBackend.ffmpeg
        : RecordingBackend.dioCopy;
    final ext = backend == RecordingBackend.ffmpeg ? 'mp4' : 'ts';
    final safeName = _safeFilename(task.channelName);
    final stamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    final outPath = '${dir.path}${Platform.pathSeparator}$safeName-$stamp.$ext';

    final running = task.copyWith(
      status: RecordingStatus.running,
      backend: backend,
      startedAt: DateTime.now().toUtc(),
      outputPath: outPath,
    );
    await _storage.putRecording(running);

    final active = _ActiveRecording(taskId: task.id);
    _active[task.id] = active;

    if (backend == RecordingBackend.ffmpeg) {
      unawaited(_runFfmpeg(running, ffmpeg!, active));
    } else {
      unawaited(_runDioCopy(running, active));
    }
  }

  Future<void> _runFfmpeg(
    RecordingTask task,
    String ffmpegBin,
    _ActiveRecording active,
  ) async {
    final outPath = task.outputPath!;
    final args = <String>[
      '-hide_banner',
      '-loglevel',
      'warning',
      '-y',
      if (task.userAgent != null) ...<String>['-user_agent', task.userAgent!],
      if (task.referer != null) ...<String>[
        '-headers',
        'Referer: ${task.referer}\r\n',
      ],
      '-i',
      task.streamUrl,
      if (task.duration != null) ...<String>[
        '-t',
        '${task.duration!.inSeconds}',
      ],
      '-c',
      'copy',
      '-bsf:a',
      'aac_adtstoasc',
      outPath,
    ];

    try {
      final proc = await Process.start(ffmpegBin, args);
      active.bind(proc);

      // Drain stdout/stderr so the process doesn't block on its
      // pipe buffer.
      proc.stdout.listen((_) {}, onError: (Object _) {});
      proc.stderr.listen((_) {}, onError: (Object _) {});

      // Periodic size sampler so the UI sees live progress.
      final ticker = Timer.periodic(const Duration(seconds: 5), (_) async {
        try {
          final f = File(outPath);
          if (await f.exists()) {
            final size = await f.length();
            final fresh = await _findById(task.id);
            if (fresh != null && fresh.status == RecordingStatus.running) {
              await _storage.putRecording(fresh.copyWith(bytesWritten: size));
            }
          }
        } on Object {
          // Ignore — sampler is best-effort.
        }
      });

      final exitCode = await proc.exitCode;
      ticker.cancel();
      _active.remove(task.id);

      if (active.cancelled) {
        // User asked us to stop — finalise as completed if any bytes
        // were written, else cancelled.
        final size = await _safeFileSize(outPath);
        await _storage.putRecording(
          task.copyWith(
            status: size > 0
                ? RecordingStatus.completed
                : RecordingStatus.cancelled,
            bytesWritten: size,
            finishedAt: DateTime.now().toUtc(),
          ),
        );
        return;
      }

      if (exitCode == 0) {
        final size = await _safeFileSize(outPath);
        await _storage.putRecording(
          task.copyWith(
            status: RecordingStatus.completed,
            bytesWritten: size,
            finishedAt: DateTime.now().toUtc(),
          ),
        );
      } else {
        await _storage.putRecording(
          task.copyWith(
            status: RecordingStatus.failed,
            finishedAt: DateTime.now().toUtc(),
            error: 'ffmpeg cikis kodu $exitCode',
          ),
        );
      }
    } on Object catch (e, st) {
      _log.warn('ffmpeg recording failed: $e\n$st');
      _active.remove(task.id);
      await _storage.putRecording(
        task.copyWith(
          status: RecordingStatus.failed,
          finishedAt: DateTime.now().toUtc(),
          error: e.toString(),
        ),
      );
    }
  }

  Future<void> _runDioCopy(
    RecordingTask task,
    _ActiveRecording active,
  ) async {
    final outPath = task.outputPath!;
    final cancelToken = CancelToken();
    active.bindCancelToken(cancelToken);

    Timer? deadline;
    if (task.duration != null) {
      deadline = Timer(task.duration!, () {
        if (!cancelToken.isCancelled) {
          cancelToken.cancel('duration reached');
          active.cancelled = true;
        }
      });
    }

    try {
      final headers = <String, String>{
        if (task.userAgent != null) 'User-Agent': task.userAgent!,
        if (task.referer != null) 'Referer': task.referer!,
      };
      await _dio.download(
        task.streamUrl,
        outPath,
        cancelToken: cancelToken,
        options: Options(
          headers: headers,
          responseType: ResponseType.stream,
          // No receiveTimeout — live streams are intentionally infinite.
          receiveTimeout: Duration.zero,
        ),
        onReceiveProgress: (int received, int _) async {
          final fresh = await _findById(task.id);
          if (fresh != null && fresh.status == RecordingStatus.running) {
            await _storage.putRecording(fresh.copyWith(bytesWritten: received));
          }
        },
      );
      deadline?.cancel();
      _active.remove(task.id);
      final size = await _safeFileSize(outPath);
      await _storage.putRecording(
        task.copyWith(
          status: RecordingStatus.completed,
          bytesWritten: size,
          finishedAt: DateTime.now().toUtc(),
        ),
      );
    } on DioException catch (e) {
      deadline?.cancel();
      _active.remove(task.id);
      final size = await _safeFileSize(outPath);
      // Cancellation due to duration reached or user-stop is expected.
      if (active.cancelled || e.type == DioExceptionType.cancel) {
        await _storage.putRecording(
          task.copyWith(
            status: size > 0
                ? RecordingStatus.completed
                : RecordingStatus.cancelled,
            bytesWritten: size,
            finishedAt: DateTime.now().toUtc(),
          ),
        );
        return;
      }
      _log.warn('dio recording failed: ${e.message}');
      await _storage.putRecording(
        task.copyWith(
          status: RecordingStatus.failed,
          bytesWritten: size,
          finishedAt: DateTime.now().toUtc(),
          error: e.message ?? 'Indirme hatasi',
        ),
      );
    } on Object catch (e, st) {
      deadline?.cancel();
      _active.remove(task.id);
      _log.warn('dio recording crashed: $e\n$st');
      await _storage.putRecording(
        task.copyWith(
          status: RecordingStatus.failed,
          finishedAt: DateTime.now().toUtc(),
          error: e.toString(),
        ),
      );
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
    // dart:io is unavailable in browsers — _recordingsDir() throws there
    // before we reach here, but be defensive in case the platform check
    // is ever moved up.
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

  Future<String?> _ffmpegPath() async {
    try {
      // Quick lookup: `which ffmpeg` on POSIX, `where ffmpeg` on Windows.
      final cmd = Platform.isWindows ? 'where' : 'which';
      final result = await Process.run(cmd, <String>['ffmpeg']);
      if (result.exitCode != 0) return null;
      final out = (result.stdout as String? ?? '').trim();
      if (out.isEmpty) return null;
      // `where` can return multiple paths separated by newlines.
      return out.split(RegExp(r'\r?\n')).first.trim();
    } on Object {
      return null;
    }
  }

  String _safeFilename(String name) {
    final s = name.replaceAll(RegExp('[^a-zA-Z0-9_-]+'), '_');
    if (s.isEmpty) return 'recording';
    return s.length > 60 ? s.substring(0, 60) : s;
  }
}

/// Internal: runtime handle for a recording in flight. Owns the
/// `Process` (ffmpeg) and/or the `CancelToken` (dio) so we can stop
/// either backend uniformly.
class _ActiveRecording {
  _ActiveRecording({required this.taskId});
  final String taskId;
  Process? _process;
  CancelToken? _cancelToken;
  bool cancelled = false;

  void bind(Process p) => _process = p;
  void bindCancelToken(CancelToken t) => _cancelToken = t;

  Future<void> cancel() async {
    cancelled = true;
    final p = _process;
    if (p != null) {
      try {
        p.kill(ProcessSignal.sigint);
      } on Object {
        try {
          p.kill();
        } on Object {
          // Already dead.
        }
      }
    }
    final t = _cancelToken;
    if (t != null && !t.isCancelled) {
      t.cancel('user stopped');
    }
  }
}
