import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/features/voice_search/voice_search_button.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/breakpoints/breakpoints.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Global search across live channels, movies, series.
///
/// Pure-client filtering — fast on the few thousand items a typical IPTV
/// catalog ships. If catalogs grow we can move this into Hive's full-text
/// extension later.
///
/// Adaptive layout:
///   * **phone** (<600 dp) — single scrollable column with stacked
///     "Live / Filmler / Diziler" sections (existing behaviour).
///   * **tablet** (>=600 dp) — search bar above; 3-column results grid
///     so the user sees Live, Movies and Series side-by-side without
///     scrolling. On the larger tablet breakpoint, columns get more
///     breathing room; below that they share the available width.
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
    final deviceClass = deviceClassFor(context);

    final ql = _q.trim().toLowerCase();
    final filteredChannels = ql.isEmpty
        ? <Channel>[]
        : (channels.value ?? const <Channel>[])
            .where((Channel c) => c.name.toLowerCase().contains(ql))
            .take(50)
            .toList();
    final filteredVod = ql.isEmpty
        ? <VodItem>[]
        : (vod.value ?? const <VodItem>[])
            .where((VodItem v) => v.title.toLowerCase().contains(ql))
            .take(50)
            .toList();
    final filteredSeries = ql.isEmpty
        ? <SeriesItem>[]
        : (series.value ?? const <SeriesItem>[])
            .where((SeriesItem s) => s.title.toLowerCase().contains(ql))
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
        actions: <Widget>[
          // Voice search — additive trailing button. Hides itself
          // automatically on platforms without a speech recogniser
          // (Windows / Linux desktop, Safari web). Tap to start /
          // stop a session; final transcripts replace the query and
          // immediately trigger the live filter via _setQuery.
          VoiceSearchButton(onResult: _setQuery),
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
      body: Column(
        children: <Widget>[
          // Real-time partial-transcript hint pinned just below the
          // app bar so the user can see what the mic is hearing while
          // a session is still in progress. Empty / hidden otherwise.
          const VoiceSearchPartialHint(),
          Expanded(child: _buildResults(ql, deviceClass, filteredChannels, filteredVod, filteredSeries)),
        ],
      ),
    );
  }

  /// Replace the search field's text + filter state from a programmatic
  /// source (currently only the voice-search controller). Keeps the
  /// caret at the end so a follow-up edit appends naturally.
  void _setQuery(String text) {
    final clean = text.trim();
    if (clean.isEmpty) return;
    _ctrl
      ..text = clean
      ..selection = TextSelection.fromPosition(
        TextPosition(offset: clean.length),
      );
    setState(() => _q = clean);
  }

  Widget _buildResults(
    String ql,
    DeviceClass deviceClass,
    List<Channel> filteredChannels,
    List<VodItem> filteredVod,
    List<SeriesItem> filteredSeries,
  ) {
    if (ql.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'Aramaya basla',
        message: 'Adi yaz, sonuclar an?nda gorunsun.',
      );
    }
    if (filteredChannels.isEmpty &&
        filteredVod.isEmpty &&
        filteredSeries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: EmptyState(
          icon: Icons.search_off,
          title: 'Sonuc yok',
        ),
      );
    }
    if (deviceClass.isTablet) {
      return _SearchTabletColumns(
        channels: filteredChannels,
        vods: filteredVod,
        series: filteredSeries,
        onPlayChannel: _playChannel,
      );
    }
    return _SearchPhoneList(
      channels: filteredChannels,
      vods: filteredVod,
      series: filteredSeries,
      onPlayChannel: _playChannel,
    );
  }

  /// Shared "open the player with this live channel" handler — used by
  /// both the phone list and the tablet column tiles. Keeping it in one
  /// place means the proxy + variants logic can't drift between layouts.
  void _playChannel(BuildContext context, Channel c) {
    final urls = streamUrlVariants(c.streamUrl).map(proxify).toList();
    final variants = MediaSource.variants(urls, title: c.name);
    context.push(
      '/play',
      extra: PlayerLaunchArgs(
        source: variants.isEmpty
            ? MediaSource(url: proxify(c.streamUrl), title: c.name)
            : variants.first,
        fallbacks: variants.length <= 1
            ? const <MediaSource>[]
            : variants.sublist(1),
        title: c.name,
        itemId: c.id,
        kind: HistoryKind.live,
        isLive: true,
      ),
    );
  }
}

/// Phone single-column list — preserves the previous stacked sections
/// so the existing UX stays exactly the same on small screens.
class _SearchPhoneList extends StatelessWidget {
  const _SearchPhoneList({
    required this.channels,
    required this.vods,
    required this.series,
    required this.onPlayChannel,
  });

  final List<Channel> channels;
  final List<VodItem> vods;
  final List<SeriesItem> series;
  final void Function(BuildContext, Channel) onPlayChannel;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      children: <Widget>[
        if (channels.isNotEmpty)
          _Section<Channel>(
            title: 'Canli kanallar',
            items: channels,
            builder: (Channel c) => ListTile(
              leading: const Icon(Icons.live_tv_outlined),
              title: Text(c.name),
              subtitle:
                  c.groups.isEmpty ? null : Text(c.groups.join(' / ')),
              onTap: () => onPlayChannel(context, c),
            ),
          ),
        if (vods.isNotEmpty)
          _Section<VodItem>(
            title: 'Filmler',
            items: vods,
            builder: (VodItem v) => ListTile(
              leading: const Icon(Icons.movie_outlined),
              title: Text(v.title),
              subtitle: v.year == null ? null : Text('${v.year}'),
              onTap: () => context.push('/movie/${v.id}'),
            ),
          ),
        if (series.isNotEmpty)
          _Section<SeriesItem>(
            title: 'Diziler',
            items: series,
            builder: (SeriesItem s) => ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(s.title),
              subtitle: s.year == null ? null : Text('${s.year}'),
              onTap: () => context.push('/series/${s.id}'),
            ),
          ),
      ],
    );
  }
}

/// Tablet 3-column results layout.
///
/// One column per content kind (Live / Filmler / Diziler). Each column
/// owns its own scroll view so a long Live result list doesn't push
/// the Filmler column off-screen. Empty columns render a centered
/// "Bu turde sonuc yok" placeholder so the user can tell they at least
/// got a hit *somewhere*.
class _SearchTabletColumns extends StatelessWidget {
  const _SearchTabletColumns({
    required this.channels,
    required this.vods,
    required this.series,
    required this.onPlayChannel,
  });

  final List<Channel> channels;
  final List<VodItem> vods;
  final List<SeriesItem> series;
  final void Function(BuildContext, Channel) onPlayChannel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: _Column(
              title: 'Canli',
              icon: Icons.live_tv_rounded,
              count: channels.length,
              empty: 'Bu sorguya uyan kanal yok.',
              child: channels.isEmpty
                  ? null
                  : ListView.separated(
                      itemCount: channels.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext _, int i) {
                        final c = channels[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.live_tv_outlined),
                          title: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: c.groups.isEmpty
                              ? null
                              : Text(
                                  c.groups.join(' / '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                          onTap: () => onPlayChannel(context, c),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: _Column(
              title: 'Filmler',
              icon: Icons.movie_rounded,
              count: vods.length,
              empty: 'Bu sorguya uyan film yok.',
              child: vods.isEmpty
                  ? null
                  : ListView.separated(
                      itemCount: vods.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext _, int i) {
                        final v = vods[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.movie_outlined),
                          title: Text(
                            v.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle:
                              v.year == null ? null : Text('${v.year}'),
                          onTap: () => context.push('/movie/${v.id}'),
                        );
                      },
                    ),
            ),
          ),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: _Column(
              title: 'Diziler',
              icon: Icons.video_library_rounded,
              count: series.length,
              empty: 'Bu sorguya uyan dizi yok.',
              child: series.isEmpty
                  ? null
                  : ListView.separated(
                      itemCount: series.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1),
                      itemBuilder: (BuildContext _, int i) {
                        final s = series[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.video_library_outlined),
                          title: Text(
                            s.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle:
                              s.year == null ? null : Text('${s.year}'),
                          onTap: () => context.push('/series/${s.id}'),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Single column wrapper for the tablet 3-up layout. Renders a header
/// with icon + count + an inner card holding either the result list or
/// an empty-state placeholder.
class _Column extends StatelessWidget {
  const _Column({
    required this.title,
    required this.icon,
    required this.count,
    required this.empty,
    required this.child,
  });

  final String title;
  final IconData icon;
  final int count;
  final String empty;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceS),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceS,
                DesignTokens.spaceS,
                DesignTokens.spaceS,
                DesignTokens.spaceXs,
              ),
              child: Row(
                children: <Widget>[
                  Icon(icon, size: 18, color: theme.colorScheme.primary),
                  const SizedBox(width: DesignTokens.spaceS),
                  Text(title, style: theme.textTheme.titleSmall),
                  const Spacer(),
                  Text(
                    '$count',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: child ??
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(DesignTokens.spaceM),
                      child: Text(
                        empty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                  ),
            ),
          ],
        ),
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
      children: <Widget>[
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
