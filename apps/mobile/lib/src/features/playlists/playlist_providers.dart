import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../shared/service_providers.dart';

part 'playlist_providers.g.dart';

/// All playlist sources the user has added.
///
/// Re-fetched every time `playlistService.add/remove/refresh` invalidates
/// this provider via `ref.invalidate(playlistsProvider)`.
@Riverpod(keepAlive: true)
Future<List<PlaylistSource>> playlists(Ref ref) async {
  final svc = ref.watch(playlistServiceProvider);
  return svc.list();
}

/// Live channel stream for a single source.
///
/// Wraps `PlaylistService.watchChannels` in a Riverpod stream so widgets
/// can `ref.watch(playlistChannelsProvider(sourceId))` and rebuild as the
/// underlying Hive box changes.
@Riverpod(keepAlive: true)
Stream<List<Channel>> playlistChannels(Ref ref, String sourceId) {
  final svc = ref.watch(playlistServiceProvider);
  return svc.watchChannels(sourceId);
}

/// Currently selected source id — null until the user picks one or until
/// the first source becomes available.
@Riverpod(keepAlive: true)
class SelectedSourceId extends _$SelectedSourceId {
  @override
  String? build() => null;

  void select(String? id) => state = id;
}

/// All channels across all currently-known sources, merged & deduped by id.
///
/// This is the surface the Channels grid consumes when "All sources" is
/// selected. Single-source filter is handled inside the screen itself.
@Riverpod(keepAlive: true)
Future<List<Channel>> allChannels(Ref ref) async {
  final sources = await ref.watch(playlistsProvider.future);
  final svc = ref.watch(playlistServiceProvider);
  final merged = <String, Channel>{};
  for (final s in sources) {
    final stream = svc.watchChannels(s.id);
    final list = await stream.first;
    for (final c in list) {
      merged[c.id] = c;
    }
  }
  return merged.values.toList(growable: false);
}
