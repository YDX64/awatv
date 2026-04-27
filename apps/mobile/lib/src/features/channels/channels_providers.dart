import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'channels_providers.g.dart';

/// Live-only subset of [allChannelsProvider].
@Riverpod(keepAlive: true)
Future<List<Channel>> liveChannels(Ref ref) async {
  final all = await ref.watch(allChannelsProvider.future);
  return all.where((Channel c) => c.kind == ChannelKind.live).toList();
}

/// Currently-active group filter. `null` means "all groups".
@Riverpod(keepAlive: true)
class ChannelGroupFilter extends _$ChannelGroupFilter {
  @override
  String? build() => null;

  void select(String? group) => state = group;
}

/// Distinct group titles across all live channels, alphabetically sorted.
@Riverpod(keepAlive: true)
Future<List<String>> liveChannelGroups(Ref ref) async {
  final channels = await ref.watch(liveChannelsProvider.future);
  final set = <String>{};
  for (final c in channels) {
    set.addAll(c.groups);
  }
  final list = set.toList()..sort();
  return list;
}

/// Live channels filtered by the active group.
@Riverpod(keepAlive: true)
Future<List<Channel>> filteredLiveChannels(Ref ref) async {
  final channels = await ref.watch(liveChannelsProvider.future);
  final group = ref.watch(channelGroupFilterProvider);
  if (group == null || group.isEmpty) return channels;
  return channels.where((Channel c) => c.groups.contains(group)).toList();
}

/// Channel by id — small convenience for `/channel/:id` and `/play`.
@Riverpod()
Future<Channel?> channelById(Ref ref, String id) async {
  final all = await ref.watch(allChannelsProvider.future);
  for (final c in all) {
    if (c.id == id) return c;
  }
  return null;
}
