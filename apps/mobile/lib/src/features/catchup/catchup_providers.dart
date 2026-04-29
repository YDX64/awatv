import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'catchup_providers.g.dart';

/// Channels (across every Xtream source) eligible for catchup playback.
///
/// We can't know per-channel whether the panel actually has archive
/// without hitting `get_simple_data_table`, so this list is the
/// optimistic universe — the per-programme `has_archive` flag from
/// [catchupProgrammes] is what actually gates the CTA.
@Riverpod(keepAlive: true)
Future<List<Channel>> catchupChannels(Ref ref) async {
  final svc = ref.watch(catchupServiceProvider);
  final list = await svc.channelsWithCatchup();
  list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return list;
}

/// Catchup programme list for one channel id. Empty until the channel
/// is selected from the screen's left rail.
@Riverpod()
Future<List<CatchupProgramme>> catchupProgrammes(
  Ref ref,
  String channelId,
) async {
  final channels = await ref.watch(catchupChannelsProvider.future);
  Channel? match;
  for (final c in channels) {
    if (c.id == channelId) {
      match = c;
      break;
    }
  }
  if (match == null) return const <CatchupProgramme>[];
  final svc = ref.watch(catchupServiceProvider);
  return svc.programmesFor(match);
}

/// Currently selected channel id on the catchup screen. `null` until
/// the user picks one (or the first eligible channel is auto-selected
/// at first paint).
@Riverpod(keepAlive: true)
class SelectedCatchupChannelId extends _$SelectedCatchupChannelId {
  @override
  String? build() => null;

  // ignore: use_setters_to_change_properties, document_ignores
  // We expose `select(id)` rather than a setter so consumers read like
  // `notifier.select(c.id)` — matches the rest of the project's
  // notifiers (e.g. ChannelGroupFilter.select).
  void select(String? id) => state = id;
}
