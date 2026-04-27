import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Global search across live channels, movies, series.
///
/// Pure-client filtering — fast on the few thousand items a typical IPTV
/// catalog ships. If catalogs grow we can move this into Hive's full-text
/// extension later.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final channels = ref.watch(liveChannelsProvider);
    final vod = ref.watch(allVodProvider);
    final series = ref.watch(allSeriesProvider);

    final ql = _q.trim().toLowerCase();
    final filteredChannels = ql.isEmpty
        ? <Channel>[]
        : (channels.value ?? const <Channel>[])
            .where((c) => c.name.toLowerCase().contains(ql))
            .take(50)
            .toList();
    final filteredVod = ql.isEmpty
        ? <VodItem>[]
        : (vod.value ?? const <VodItem>[])
            .where((v) => v.title.toLowerCase().contains(ql))
            .take(50)
            .toList();
    final filteredSeries = ql.isEmpty
        ? <SeriesItem>[]
        : (series.value ?? const <SeriesItem>[])
            .where((s) => s.title.toLowerCase().contains(ql))
            .take(50)
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: 'Kanal, film veya dizi ara...',
            border: InputBorder.none,
            filled: false,
          ),
          onChanged: (String v) => setState(() => _q = v),
        ),
        actions: [
          if (_q.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () {
                _ctrl.clear();
                setState(() => _q = '');
              },
            ),
        ],
      ),
      body: ql.isEmpty
          ? const EmptyState(
              icon: Icons.search,
              title: 'Aramaya basla',
              message: 'Adi yaz, sonuclar an?nda gorunsun.',
            )
          : ListView(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              children: [
                if (filteredChannels.isNotEmpty)
                  _Section<Channel>(
                    title: 'Canli kanallar',
                    items: filteredChannels,
                    builder: (Channel c) => ListTile(
                      leading: const Icon(Icons.live_tv_outlined),
                      title: Text(c.name),
                      subtitle: c.groups.isEmpty
                          ? null
                          : Text(c.groups.join(' / ')),
                      onTap: () {
                        context.push(
                          '/play',
                          extra: PlayerLaunchArgs(
                            source: MediaSource(
                              url: proxify(c.streamUrl),
                              title: c.name,
                            ),
                            title: c.name,
                            itemId: c.id,
                            kind: HistoryKind.live,
                            isLive: true,
                          ),
                        );
                      },
                    ),
                  ),
                if (filteredVod.isNotEmpty)
                  _Section<VodItem>(
                    title: 'Filmler',
                    items: filteredVod,
                    builder: (VodItem v) => ListTile(
                      leading: const Icon(Icons.movie_outlined),
                      title: Text(v.title),
                      subtitle: v.year == null ? null : Text('${v.year}'),
                      onTap: () => context.push('/movie/${v.id}'),
                    ),
                  ),
                if (filteredSeries.isNotEmpty)
                  _Section<SeriesItem>(
                    title: 'Diziler',
                    items: filteredSeries,
                    builder: (SeriesItem s) => ListTile(
                      leading: const Icon(Icons.video_library_outlined),
                      title: Text(s.title),
                      subtitle: s.year == null ? null : Text('${s.year}'),
                      onTap: () => context.push('/series/${s.id}'),
                    ),
                  ),
                if (filteredChannels.isEmpty &&
                    filteredVod.isEmpty &&
                    filteredSeries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: EmptyState(
                      icon: Icons.search_off,
                      title: 'Sonuc yok',
                    ),
                  ),
              ],
            ),
    );
  }
}

class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.items,
    required this.builder,
  });

  final String title;
  final List<T> items;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceS),
          child: Text(
            '$title (${items.length})',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        for (final item in items) builder(item),
        const SizedBox(height: DesignTokens.spaceM),
      ],
    );
  }
}
