import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/series/series_providers.dart';
import 'package:awatv_mobile/src/features/vod/vod_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 10-foot global search.
///
/// Big search field at the top, three result columns underneath
/// (channels / movies / series). Same data sources as the mobile
/// `SearchScreen` — only the layout is rebuilt for distance.
class TvSearchScreen extends ConsumerStatefulWidget {
  const TvSearchScreen({super.key});

  @override
  ConsumerState<TvSearchScreen> createState() => _TvSearchScreenState();
}

class _TvSearchScreenState extends ConsumerState<TvSearchScreen> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _fieldFocus = FocusNode();
  String _q = '';

  @override
  void initState() {
    super.initState();
    // Land focus on the field so a TV remote's keyboard / on-screen IME
    // is summoned without an extra D-pad press.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fieldFocus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _fieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final channels = ref.watch(liveChannelsProvider);
    final vod = ref.watch(allVodProvider);
    final series = ref.watch(allSeriesProvider);

    final ql = _q.trim().toLowerCase();
    final fc = ql.isEmpty
        ? <Channel>[]
        : (channels.value ?? const <Channel>[])
            .where((Channel c) => c.name.toLowerCase().contains(ql))
            .take(40)
            .toList();
    final fv = ql.isEmpty
        ? <VodItem>[]
        : (vod.value ?? const <VodItem>[])
            .where((VodItem v) => v.title.toLowerCase().contains(ql))
            .take(40)
            .toList();
    final fs = ql.isEmpty
        ? <SeriesItem>[]
        : (series.value ?? const <SeriesItem>[])
            .where((SeriesItem s) => s.title.toLowerCase().contains(ql))
            .take(40)
            .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
        DesignTokens.spaceXl,
        DesignTokens.spaceL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Ara',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceL,
              vertical: DesignTokens.spaceM,
            ),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(DesignTokens.radiusL),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.5),
                width: 2,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.search, size: 32, color: scheme.primary),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _fieldFocus,
                    style: const TextStyle(fontSize: 22),
                    decoration: const InputDecoration(
                      hintText: 'Kanal, film veya dizi adi yaz...',
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    textInputAction: TextInputAction.search,
                    onChanged: (String v) => setState(() => _q = v),
                  ),
                ),
                if (_q.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 28),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _q = '');
                    },
                  ),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Expanded(
            child: ql.isEmpty
                ? const Center(
                    child: EmptyState(
                      icon: Icons.search,
                      title: 'Aramaya basla',
                      message: 'Klavyenden veya uzaktan kumandadan yaz.',
                    ),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _ResultColumn<Channel>(
                        title: 'Canli kanallar',
                        items: fc,
                        builder: (Channel c) => _ResultRow(
                          icon: Icons.live_tv_outlined,
                          title: c.name,
                          subtitle: c.groups.isEmpty
                              ? null
                              : c.groups.first,
                          onTap: () {
                            final urls = streamUrlVariants(c.streamUrl)
                                .map(proxify)
                                .toList();
                            final variants = MediaSource.variants(
                              urls,
                              title: c.name,
                            );
                            context.push(
                              '/play',
                              extra: PlayerLaunchArgs(
                                source: variants.isEmpty
                                    ? MediaSource(
                                        url: proxify(c.streamUrl),
                                        title: c.name,
                                      )
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
                          },
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceL),
                      _ResultColumn<VodItem>(
                        title: 'Filmler',
                        items: fv,
                        builder: (VodItem v) => _ResultRow(
                          icon: Icons.movie_outlined,
                          title: v.title,
                          subtitle: v.year?.toString(),
                          onTap: () => context.push('/movie/${v.id}'),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceL),
                      _ResultColumn<SeriesItem>(
                        title: 'Diziler',
                        items: fs,
                        builder: (SeriesItem s) => _ResultRow(
                          icon: Icons.video_library_outlined,
                          title: s.title,
                          subtitle: s.year?.toString(),
                          onTap: () => context.push('/series/${s.id}'),
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultColumn<T> extends StatelessWidget {
  const _ResultColumn({
    required this.title,
    required this.items,
    required this.builder,
  });

  final String title;
  final List<T> items;
  final Widget Function(T) builder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.spaceM),
            child: Text(
              '$title (${items.length})',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(top: DesignTokens.spaceL),
                    child: Text(
                      'Sonuc yok',
                      style: TextStyle(
                        fontSize: 16,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.55),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: DesignTokens.spaceS),
                    itemBuilder: (BuildContext _, int i) =>
                        builder(items[i]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({
    required this.icon,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusableTile(
      onTap: onTap,
      semanticLabel: title,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceM,
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 28, color: theme.colorScheme.primary),
            const SizedBox(width: DesignTokens.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
