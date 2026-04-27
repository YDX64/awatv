import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/app/env.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
  final d = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      sendTimeout: const Duration(seconds: 15),
      followRedirects: true,
      validateStatus: (int? status) => status != null && status < 500,
      headers: <String, String>{
        'Accept': '*/*',
        'User-Agent': 'AWAtv/0.1 (Mobile; Flutter)',
      },
    ),
  );
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
