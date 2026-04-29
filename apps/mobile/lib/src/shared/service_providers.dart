import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'service_providers.g.dart';

/// The singleton `AwatvStorage` instance — already opened in `main.dart`
/// before `runApp`, so the provider just hands the live instance back.
@Riverpod(keepAlive: true)
AwatvStorage awatvStorage(Ref ref) => AwatvStorage.instance;

/// Shared `Dio` HTTP client. Tuned for IPTV traffic: long receive window,
/// follows redirects, accepts JSON or text bodies.
@Riverpod(keepAlive: true)
Dio dio(Ref ref) {
  // Browsers refuse to let JS set the User-Agent header (it's a forbidden
  // header name). Sending it from the Dart side anyway just produces a
  // noisy `Refused to set unsafe header "User-Agent"` console warning.
  // The Worker proxy substitutes its own VLC-style UA when forwarding to
  // upstream IPTV panels, so we don't need to set one here on web.
  final headers = <String, String>{'Accept': '*/*'};
  if (!kIsWeb) {
    headers['User-Agent'] = 'AWAtv/0.1 (Mobile; Flutter)';
  }

  final d = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      followRedirects: true,
      validateStatus: (int? status) => status != null && status < 500,
      headers: headers,
    ),
  );
  // On web, route every http(s) request through the AWAtv proxy Worker so
  // mixed-content and missing-CORS-headers stop bricking IPTV API calls.
  d.interceptors.add(const WebProxyInterceptor());
  ref.onDispose(d.close);
  return d;
}

/// TMDB client. Returns `null` when the user has not configured an API key —
/// downstream code should treat that as "no enrichment available".
@Riverpod(keepAlive: true)
TmdbClient? tmdbClient(Ref ref) {
  if (!Env.hasTmdb) return null;
  return TmdbClient(apiKey: Env.tmdbApiKey, dio: ref.watch(dioProvider));
}

/// Metadata service — wraps TMDB lookups with on-disk caching. When the
/// TMDB key is missing this returns a no-op service that always answers
/// `null` so callers don't need to special-case the empty-env path.
@Riverpod(keepAlive: true)
MetadataService metadataService(Ref ref) {
  final storage = ref.watch(awatvStorageProvider);
  final tmdb = ref.watch(tmdbClientProvider);
  return MetadataService(storage: storage, tmdb: tmdb);
}

/// Playlist service — orchestrates source CRUD, parses M3U / Xtream, and
/// streams resulting channels through Hive.
@Riverpod(keepAlive: true)
PlaylistService playlistService(Ref ref) {
  return PlaylistService(
    storage: ref.watch(awatvStorageProvider),
    dio: ref.watch(dioProvider),
    metadata: ref.watch(metadataServiceProvider),
  );
}

/// EPG service — XMLTV download + indexed lookup. The underlying client is
/// constructed with the shared `Dio` so it inherits our redirect / timeout
/// configuration and proxy if any.
@Riverpod(keepAlive: true)
EpgService epgService(Ref ref) {
  return EpgService(
    client: EpgClient(dio: ref.watch(dioProvider)),
    storage: ref.watch(awatvStorageProvider),
  );
}

/// Favorites — toggle + watch.
@Riverpod(keepAlive: true)
FavoritesService favoritesService(Ref ref) {
  return FavoritesService(storage: ref.watch(awatvStorageProvider));
}

/// History — resume points and continue-watching.
@Riverpod(keepAlive: true)
HistoryService historyService(Ref ref) {
  return HistoryService(storage: ref.watch(awatvStorageProvider));
}

/// Catchup / replay TV — resolves Xtream `archive=1` programmes and
/// timeshift URLs so the EPG grid + Catchup screen can play past
/// programmes. Returns a service even on web; the underlying calls
/// degrade naturally because the playback URLs are HTTP-based.
@Riverpod(keepAlive: true)
CatchupService catchupService(Ref ref) {
  return CatchupService(
    storage: ref.watch(awatvStorageProvider),
    dio: ref.watch(dioProvider),
  );
}

/// On-disk path used for [recordingService] output. Each platform
/// gets its own canonical sandbox:
///   * macOS / Linux desktop → `Application Support/AWAtv/recordings`
///   * Windows desktop       → `%APPDATA%\AWAtv\recordings`
///   * iOS / Android mobile  → app documents `recordings` subfolder
/// On web this provider throws, which the service treats as
/// "unsupported platform" and surfaces the empty-state hint.
@Riverpod(keepAlive: true)
Future<Directory> Function() recordingsDirResolver(Ref ref) {
  return () async {
    if (kIsWeb) {
      throw const FileSystemException(
        'Recording is not available on the web build',
      );
    }
    final base = (Platform.isMacOS || Platform.isLinux || Platform.isWindows)
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    return Directory('${base.path}${Platform.pathSeparator}recordings');
  };
}

/// On-disk path used for [downloadsService] output. Same per-platform
/// rules as [recordingsDirResolver] but in a `downloads/` subfolder.
@Riverpod(keepAlive: true)
Future<Directory> Function() downloadsDirResolver(Ref ref) {
  return () async {
    if (kIsWeb) {
      throw const FileSystemException(
        'Downloads are not available on the web build',
      );
    }
    final base = (Platform.isMacOS || Platform.isLinux || Platform.isWindows)
        ? await getApplicationSupportDirectory()
        : await getApplicationDocumentsDirectory();
    return Directory('${base.path}${Platform.pathSeparator}downloads');
  };
}

/// Recording service singleton. Boots the schedule poller so future
/// scheduled recordings auto-start while the app is open.
@Riverpod(keepAlive: true)
RecordingService recordingService(Ref ref) {
  final svc = RecordingService(
    storage: ref.watch(awatvStorageProvider),
    dio: ref.watch(dioProvider),
    recordingsDir: ref.watch(recordingsDirResolverProvider),
  );
  if (!kIsWeb) svc.boot();
  ref.onDispose(svc.dispose);
  return svc;
}

/// Downloads service singleton. Default cap: 3 parallel downloads.
@Riverpod(keepAlive: true)
DownloadsService downloadsService(Ref ref) {
  return DownloadsService(
    storage: ref.watch(awatvStorageProvider),
    dio: ref.watch(dioProvider),
    downloadsDir: ref.watch(downloadsDirResolverProvider),
  );
}
