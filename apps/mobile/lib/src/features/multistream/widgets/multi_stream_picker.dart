import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_session.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-sheet channel picker for the "+" empty tile.
///
/// Reuses [liveChannelsProvider] for the source list — the same data
/// surface that powers `/live` — and wires the search field to a
/// simple substring filter on channel name + group. Tapping a channel
/// pushes it into the multi-stream session and dismisses the sheet.
class MultiStreamPicker extends ConsumerStatefulWidget {
  const MultiStreamPicker({super.key});

  /// Convenience opener — call from the empty-slot tile.
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const FractionallySizedBox(
        heightFactor: 0.85,
        child: MultiStreamPicker(),
      ),
    );
  }

  @override
  ConsumerState<MultiStreamPicker> createState() => _MultiStreamPickerState();
}

class _MultiStreamPickerState extends ConsumerState<MultiStreamPicker> {
  String _query = '';
  late final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channelsAsync = ref.watch(liveChannelsProvider);
    final theme = Theme.of(context);
    final session = ref.watch(multiStreamSessionProvider);
    final existingIds = <String>{
      for (final s in session.slots) s.channel.id,
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceL,
        0,
        DesignTokens.spaceL,
        DesignTokens.spaceM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: DesignTokens.spaceXs,
            ),
            child: Text(
              'Coklu izleme — kanal sec',
              style: theme.textTheme.titleLarge,
            ),
          ),
          TextField(
            controller: _ctrl,
            onChanged: (String v) =>
                setState(() => _query = v.trim().toLowerCase()),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search_rounded),
              hintText: 'Kanal ara...',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceM),
          Expanded(
            child: channelsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator.adaptive(),
              ),
              error: (Object e, StackTrace _) => Center(
                child: Text('Kanallar yuklenemedi: $e'),
              ),
              data: (List<Channel> all) {
                final filtered = _filter(all, _query);
                if (filtered.isEmpty) {
                  return const EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Eslesen kanal yok',
                    message: 'Farkli bir kelime deneyin.',
                  );
                }
                return ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 0),
                  itemBuilder: (BuildContext ctx, int i) {
                    final ch = filtered[i];
                    final already = existingIds.contains(ch.id);
                    return ListTile(
                      leading: _ChannelLogo(channel: ch),
                      title: Text(
                        ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: ch.groups.isEmpty
                          ? null
                          : Text(
                              ch.groups.first,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                      enabled: !already,
                      trailing: already
                          ? const Chip(label: Text('Eklendi'))
                          : const Icon(Icons.add_circle_outline_rounded),
                      onTap: already
                          ? null
                          : () {
                              ref
                                  .read(multiStreamSessionProvider.notifier)
                                  .addChannel(ch);
                              Navigator.of(ctx).pop();
                            },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Substring filter on channel name + first group, case-insensitive.
  List<Channel> _filter(List<Channel> all, String q) {
    if (q.isEmpty) return all;
    return <Channel>[
      for (final ch in all)
        if (ch.name.toLowerCase().contains(q) ||
            (ch.groups.isNotEmpty &&
                ch.groups.first.toLowerCase().contains(q)))
          ch,
    ];
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel});
  final Channel channel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = channel.logoUrl;
    if (url == null || url.isEmpty) {
      return CircleAvatar(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        child: Text(
          channel.name.isEmpty ? '?' : channel.name.characters.first,
        ),
      );
    }
    return SizedBox(
      width: 40,
      height: 40,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.cover,
          errorWidget: (_, __, ___) => CircleAvatar(
            backgroundColor: scheme.primary,
            foregroundColor: scheme.onPrimary,
            child: Text(
              channel.name.isEmpty ? '?' : channel.name.characters.first,
            ),
          ),
        ),
      ),
    );
  }
}
