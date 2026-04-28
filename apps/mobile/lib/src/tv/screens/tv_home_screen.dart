import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/home/category_tree_provider.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_mobile/src/tv/d_pad.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// 10-foot home screen — IPTV-Expert-class.
///
/// Layout (left to right):
/// ┌──────────────┬────────────────────────────────────────┐
/// │ Category     │  Hero focus area                       │
/// │ tree         │  (current selection preview)           │
/// │              ├────────────────────────────────────────┤
/// │ • Live       │  Grid of channels / movies / series    │
/// │   - Spor     │  (FocusableTile per item)              │
/// │   - Haber    │                                        │
/// │ • Filmler    │                                        │
/// │ • Diziler    │                                        │
/// └──────────────┴────────────────────────────────────────┘
///
/// D-pad: Up/Down to traverse the category tree (or grid rows). Right
/// pushes focus into the grid; Left brings it back to the tree. OK on
/// a category navigates into its grid; OK on a grid item opens the
/// player.
class TvHomeScreen extends ConsumerWidget {
  const TvHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tree = ref.watch(categoryTreeProvider);
    return tree.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) => ErrorView(
        message: e.toString(),
        onRetry: () => ref.invalidate(categoryTreeProvider),
      ),
      data: (CategoryTree t) {
        final hasAny = t.live.any((CategoryNode n) => n.count > 0) ||
            t.movies.any((CategoryNode n) => n.count > 0) ||
            t.series.any((CategoryNode n) => n.count > 0);
        if (!hasAny) return const _TvHomeEmpty();
        return _TvHomeBody(tree: t);
      },
    );
  }
}

class _TvHomeBody extends ConsumerWidget {
  const _TvHomeBody({required this.tree});

  final CategoryTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(categorySelectionProvider);

    return Padding(
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 320,
            child: _TvCategoryTree(tree: tree),
          ),
          const SizedBox(width: DesignTokens.spaceL),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _TvHeroFocus(selection: selection, tree: tree),
                const SizedBox(height: DesignTokens.spaceL),
                Expanded(child: _TvGrid(selection: selection)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tree pane
// ---------------------------------------------------------------------------

class _TvCategoryTree extends ConsumerWidget {
  const _TvCategoryTree({required this.tree});

  final CategoryTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(categorySelectionProvider);
    final scheme = Theme.of(context).colorScheme;
    return FocusTraversalGroup(
      policy: OrderedTraversalPolicy(),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          border: Border.all(
            color: scheme.outline.withValues(alpha: 0.18),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spaceM,
          horizontal: DesignTokens.spaceS,
        ),
        child: ListView(
          children: <Widget>[
            _TvBucket(
              kind: CategoryKind.live,
              nodes: tree.live,
              selection: selection,
              autofocus: true,
            ),
            _TvBucket(
              kind: CategoryKind.movies,
              nodes: tree.movies,
              selection: selection,
            ),
            _TvBucket(
              kind: CategoryKind.series,
              nodes: tree.series,
              selection: selection,
            ),
          ],
        ),
      ),
    );
  }
}

class _TvBucket extends ConsumerWidget {
  const _TvBucket({
    required this.kind,
    required this.nodes,
    required this.selection,
    this.autofocus = false,
  });

  final CategoryKind kind;
  final List<CategoryNode> nodes;
  final CategoryNode? selection;
  final bool autofocus;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (nodes.isEmpty || nodes.first.count == 0) {
      return const SizedBox.shrink();
    }
    final IconData icon;
    final Color tint;
    final scheme = Theme.of(context).colorScheme;
    switch (kind) {
      case CategoryKind.live:
        icon = Icons.live_tv_rounded;
        tint = scheme.secondary;
      case CategoryKind.movies:
        icon = Icons.movie_outlined;
        tint = scheme.primary;
      case CategoryKind.series:
        icon = Icons.video_library_outlined;
        tint = scheme.tertiary;
    }
    final root = nodes.first;
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spaceS),
      child: Column(
        children: <Widget>[
          _TvTreeItem(
            icon: icon,
            iconTint: tint,
            label: kind.label,
            count: root.count,
            selected: selection == root,
            heading: true,
            autofocus: autofocus,
            onTap: () => ref
                .read(categorySelectionProvider.notifier)
                .select(root),
          ),
          for (final c in nodes.sublist(1))
            _TvTreeItem(
              icon: Icons.subdirectory_arrow_right_rounded,
              iconTint: tint.withValues(alpha: 0.5),
              label: c.name!,
              count: c.count,
              selected: selection == c,
              heading: false,
              onTap: () => ref
                  .read(categorySelectionProvider.notifier)
                  .select(c),
            ),
        ],
      ),
    );
  }
}

class _TvTreeItem extends StatefulWidget {
  const _TvTreeItem({
    required this.icon,
    required this.iconTint,
    required this.label,
    required this.count,
    required this.selected,
    required this.heading,
    required this.onTap,
    this.autofocus = false,
  });

  final IconData icon;
  final Color iconTint;
  final String label;
  final int count;
  final bool selected;
  final bool heading;
  final VoidCallback onTap;
  final bool autofocus;

  @override
  State<_TvTreeItem> createState() => _TvTreeItemState();
}

class _TvTreeItemState extends State<_TvTreeItem> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final showActive = selected || _focused;
    final fg = showActive
        ? scheme.onSurface
        : scheme.onSurface.withValues(alpha: 0.78);

    final tile = AnimatedContainer(
      duration: DesignTokens.motionFast,
      margin: const EdgeInsets.symmetric(
        vertical: 2,
        horizontal: 4,
      ),
      padding: EdgeInsets.symmetric(
        vertical: widget.heading ? 12 : 10,
        horizontal: 12,
      ),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        gradient: selected
            ? LinearGradient(
                colors: <Color>[
                  widget.iconTint.withValues(alpha: 0.30),
                  widget.iconTint.withValues(alpha: 0.10),
                ],
              )
            : null,
        color: !selected && _focused
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.7)
            : null,
        border: Border.all(
          color: showActive
              ? widget.iconTint.withValues(alpha: _focused ? 0.9 : 0.4)
              : Colors.transparent,
          width: _focused ? 2 : 1,
        ),
        boxShadow: _focused
            ? <BoxShadow>[
                BoxShadow(
                  color: widget.iconTint.withValues(alpha: 0.45),
                  blurRadius: 18,
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: Row(
        children: <Widget>[
          Icon(widget.icon, color: widget.iconTint, size: 22),
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: Text(
              widget.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: widget.heading ? 16 : 14,
                fontWeight: widget.heading
                    ? FontWeight.w800
                    : (selected ? FontWeight.w700 : FontWeight.w500),
                color: fg,
              ),
            ),
          ),
          if (widget.count > 0)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.7),
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusS),
              ),
              child: Text(
                '${widget.count}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
            ),
        ],
      ),
    );

    return FocusableActionDetector(
      autofocus: widget.autofocus,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (bool v) => setState(() => _focused = v),
      onShowHoverHighlight: (bool v) {
        if (v != _focused) setState(() => _focused = v);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: tile,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero / preview area
// ---------------------------------------------------------------------------

class _TvHeroFocus extends StatelessWidget {
  const _TvHeroFocus({required this.selection, required this.tree});

  final CategoryNode? selection;
  final CategoryTree tree;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final node = selection ?? _firstNonEmpty(tree);
    final IconData icon;
    final Color tint;
    final String headline;
    final String tagline;

    if (node == null) {
      icon = Icons.playlist_add_rounded;
      tint = scheme.primary;
      headline = 'AWAtv';
      tagline = 'Bir liste ekleyince icerik burada yer alir.';
    } else {
      switch (node.kind) {
        case CategoryKind.live:
          icon = Icons.live_tv_rounded;
          tint = scheme.secondary;
        case CategoryKind.movies:
          icon = Icons.movie_outlined;
          tint = scheme.primary;
        case CategoryKind.series:
          icon = Icons.video_library_outlined;
          tint = scheme.tertiary;
      }
      headline = node.isRoot
          ? 'Tum ${node.kind.label}'
          : node.name!;
      tagline = node.isRoot
          ? '${node.count} icerik mevcut'
          : '${node.kind.label} > ${node.count} icerik';
    }

    return Container(
      height: 180,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            tint.withValues(alpha: 0.35),
            scheme.surface.withValues(alpha: 0.6),
          ],
        ),
        border: Border.all(
          color: tint.withValues(alpha: 0.5),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tint.withValues(alpha: 0.25),
            blurRadius: 32,
          ),
        ],
      ),
      padding: const EdgeInsets.all(DesignTokens.spaceL),
      child: Row(
        children: <Widget>[
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tint.withValues(alpha: 0.18),
              border: Border.all(
                color: tint.withValues(alpha: 0.6),
                width: 2,
              ),
            ),
            child: Icon(icon, size: 44, color: tint),
          ),
          const SizedBox(width: DesignTokens.spaceL),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  headline,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Text(
                  tagline,
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurface.withValues(alpha: 0.78),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  CategoryNode? _firstNonEmpty(CategoryTree t) {
    for (final list in <List<CategoryNode>>[t.live, t.movies, t.series]) {
      if (list.isNotEmpty && list.first.count > 0) return list.first;
    }
    return null;
  }
}

// ---------------------------------------------------------------------------
// Grid pane
// ---------------------------------------------------------------------------

class _TvGrid extends ConsumerWidget {
  const _TvGrid({required this.selection});

  final CategoryNode? selection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (selection == null) {
      return const Center(
        child: EmptyState(
          icon: Icons.account_tree_outlined,
          title: 'Bir kategori sec',
        ),
      );
    }
    switch (selection!.kind) {
      case CategoryKind.live:
        return const _TvLiveGrid();
      case CategoryKind.movies:
        return const _TvVodGrid();
      case CategoryKind.series:
        return const _TvSeriesGrid();
    }
  }
}

class _TvLiveGrid extends ConsumerWidget {
  const _TvLiveGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(selectedLiveChannelsProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) =>
          ErrorView(message: e.toString()),
      data: (List<Channel> values) {
        if (values.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.live_tv_outlined,
              title: 'Kanal yok',
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(DesignTokens.spaceS),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            childAspectRatio: 16 / 9,
            mainAxisSpacing: DesignTokens.spaceM,
            crossAxisSpacing: DesignTokens.spaceM,
          ),
          itemCount: values.length,
          itemBuilder: (BuildContext _, int i) {
            final ch = values[i];
            return FocusableTile(
              autofocus: i == 0,
              onTap: () => _playChannel(context, ch),
              semanticLabel: ch.name,
              child: ChannelTile(
                name: ch.name,
                logoUrl: ch.logoUrl,
                group: ch.groups.isEmpty ? null : ch.groups.first,
                onTap: () => _playChannel(context, ch),
              ),
            );
          },
        );
      },
    );
  }

  void _playChannel(BuildContext context, Channel ch) {
    final urls = streamUrlVariants(ch.streamUrl).map(proxify).toList();
    final variants = MediaSource.variants(
      urls,
      title: ch.name,
      userAgent: ch.extras['http-user-agent'],
    );
    final args = PlayerLaunchArgs(
      source: variants.isEmpty
          ? MediaSource(
              url: proxify(ch.streamUrl),
              title: ch.name,
              userAgent: ch.extras['http-user-agent'],
            )
          : variants.first,
      fallbacks: variants.length <= 1
          ? const <MediaSource>[]
          : variants.sublist(1),
      title: ch.name,
      subtitle: ch.groups.isEmpty ? null : ch.groups.first,
      itemId: ch.id,
      kind: HistoryKind.live,
      isLive: true,
    );
    context.push('/play', extra: args);
  }
}

class _TvVodGrid extends ConsumerWidget {
  const _TvVodGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(selectedVodProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) =>
          ErrorView(message: e.toString()),
      data: (List<VodItem> values) {
        if (values.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.movie_outlined,
              title: 'Film yok',
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(DesignTokens.spaceS),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            childAspectRatio: 2 / 3,
            mainAxisSpacing: DesignTokens.spaceM,
            crossAxisSpacing: DesignTokens.spaceM,
          ),
          itemCount: values.length,
          itemBuilder: (BuildContext _, int i) {
            final v = values[i];
            return FocusableTile(
              autofocus: i == 0,
              semanticLabel: v.title,
              onTap: () => context.push('/movie/${v.id}'),
              child: _TvPosterTile(
                title: v.title,
                imageUrl: v.posterUrl,
              ),
            );
          },
        );
      },
    );
  }
}

class _TvSeriesGrid extends ConsumerWidget {
  const _TvSeriesGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(selectedSeriesProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) =>
          ErrorView(message: e.toString()),
      data: (List<SeriesItem> values) {
        if (values.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Dizi yok',
            ),
          );
        }
        return GridView.builder(
          padding: const EdgeInsets.all(DesignTokens.spaceS),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 200,
            childAspectRatio: 2 / 3,
            mainAxisSpacing: DesignTokens.spaceM,
            crossAxisSpacing: DesignTokens.spaceM,
          ),
          itemCount: values.length,
          itemBuilder: (BuildContext _, int i) {
            final s = values[i];
            return FocusableTile(
              autofocus: i == 0,
              semanticLabel: s.title,
              onTap: () => context.push('/series/${s.id}'),
              child: _TvPosterTile(
                title: s.title,
                imageUrl: s.posterUrl,
              ),
            );
          },
        );
      },
    );
  }
}

class _TvPosterTile extends StatelessWidget {
  const _TvPosterTile({required this.title, this.imageUrl});

  final String title;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (imageUrl != null && imageUrl!.isNotEmpty)
          CachedNetworkImage(
            imageUrl: imageUrl!,
            fit: BoxFit.cover,
            errorWidget: (BuildContext _, String __, Object ___) =>
                _fallback(scheme),
          )
        else
          _fallback(scheme),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  Colors.transparent,
                  Color(0xCC000000),
                ],
              ),
            ),
            padding: const EdgeInsets.all(DesignTokens.spaceS),
            child: Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback(ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.6),
            scheme.tertiary.withValues(alpha: 0.4),
          ],
        ),
      ),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      child: Text(
        title,
        textAlign: TextAlign.center,
        maxLines: 3,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _TvHomeEmpty extends StatelessWidget {
  const _TvHomeEmpty();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'Liste ekle',
        subtitle: 'Telefonundan AWAtv mobil uygulamasi ile bir M3U veya '
            'Xtream listesi ekledikten sonra burada zenginlesir.',
      ),
    );
  }
}
