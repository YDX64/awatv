import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/service_providers.dart';
import '../playlists/playlist_providers.dart';

part 'vod_providers.g.dart';

/// Every VOD item the user has, merged across all sources.
@Riverpod(keepAlive: true)
Future<List<VodItem>> allVod(Ref ref) async {
  final sources = await ref.watch(playlistsProvider.future);
  final svc = ref.watch(playlistServiceProvider);
  final out = <VodItem>[];
  for (final s in sources) {
    final list = await svc.vodItems(s.id);
    out.addAll(list);
  }
  return out;
}

/// Single VOD lookup.
@Riverpod(keepAlive: false)
Future<VodItem?> vodById(Ref ref, String id) async {
  final all = await ref.watch(allVodProvider.future);
  for (final v in all) {
    if (v.id == id) return v;
  }
  return null;
}
