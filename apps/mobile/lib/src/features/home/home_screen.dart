import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/epg_providers.dart';
import 'package:awatv_mobile/src/features/groups/group_customisation_provider.dart';
import 'package:awatv_mobile/src/features/home/category_tree_provider.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/network/network_chip.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// IPTV-Expert-class home screen.
///
/// Layout adapts to the available width:
///   * **>= 1280dp** — 3 panes: category tree (260dp) | grid (flex) |
///     EPG strip (320dp, only when a live channel is highlighted)
///   * **>= 720dp**  — 2 panes: category tree (240dp) | grid (flex)
///   * **< 720dp**   — 1 pane: chip row of categories on top, grid below
///
/// The hallmark IPTV-app browsing pattern: pick a category from the tree,
/// see its content. No "Trending" / "New" Netflix rows — the source of
/// truth is the user's own playlist taxonomy.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(customisedCategoryTreeProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: treeAsync.when(
          loading: () => const _HomeLoading(),
          error: (Object e, StackTrace _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(customisedCategoryTreeProvider),
          ),
          data: (CategoryTree tree) {
            final hasAny = tree.live.isNotEmpty ||
                tree.movies.isNotEmpty ||
                tree.series.isNotEmpty;
            if (!hasAny ||
                (tree.countFor(CategoryKind.live) == 0 &&
                    tree.countFor(CategoryKind.movies) == 0 &&
                    tree.countFor(CategoryKind.series) == 0)) {
              return const _HomeEmpty();
            }
            return _HomeBody(tree: tree);
          },
        ),
      ),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  const _HomeBody({required this.tree});

  final CategoryTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints c) {
        final width = c.maxWidth;
        final showTreePane = width >= 720;
        final showEpgStrip = width >= DesignTokens.tripleColumnBreakpoint;

        return Column(
          children: <Widget>[
            const SsidConsentBanner(),
            _HomeAppBar(
              showCategoryChips: !showTreePane,
              tree: tree,
            ),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (showTreePane)
                    SizedBox(
                      width: DesignTokens.categoryTreePaneWidth,
                      child: CategoryTreePane(tree: tree),
                    ),
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: () async {
                        ref.invalidate(categoryTreeProvider);
                        await ref.read(categoryTreeProvider.future);
                      },
                      child: const _GridPane(),
                    ),
                  ),
                  if (showEpgStrip)
                    SizedBox(
                      width: DesignTokens.epgStripPaneWidth,
                      child: const _EpgStripPane(),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// App bar
// ---------------------------------------------------------------------------

class _HomeAppBar extends StatelessWidget {
  const _HomeAppBar({
    required this.showCategoryChips,
    required this.tree,
  });

  final bool showCategoryChips;
  final CategoryTree tree;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.85),
        border: Border(
          bottom: BorderSide(
            color: scheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceS,
            ),
            child: Row(
              children: <Widget>[
                ShaderMask(
                  shaderCallback: (Rect r) =>
                      BrandColors.brandGradient.createShader(r),
                  blendMode: BlendMode.srcIn,
                  child: const Text(
                    'AWAtv',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      fontSize: 22,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceM),
                _CategoryCounter(tree: tree),
                const Spacer(),
                const NetworkChip(),
                const SizedBox(width: DesignTokens.spaceXs),
                IconButton(
                  tooltip: 'Ara',
                  icon: const Icon(Icons.search),
                  onPressed: () => context.push('/search'),
                ),
                IconButton(
                  tooltip: 'Listeler',
                  icon: const Icon(Icons.playlist_play_outlined),
                  onPressed: () => context.push('/playlists'),
                ),
              ],
            ),
          ),
          if (showCategoryChips)
            SizedBox(
              height: 48,
              child: _CategoryChipsRow(tree: tree),
            ),
        ],
      ),
    );
  }
}

class _CategoryCounter extends StatelessWidget {
  const _CategoryCounter({required this.tree});

  final CategoryTree tree;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = tree.countFor(CategoryKind.live);
    final movies = tree.countFor(CategoryKind.movies);
    final series = tree.countFor(CategoryKind.series);
    return Wrap(
      spacing: DesignTokens.spaceM,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        _Counter(label: 'Canli', count: live, color: scheme.secondary),
        _Counter(label: 'Film', count: movies, color: scheme.primary),
        _Counter(label: 'Dizi', count: series, color: scheme.tertiary),
      ],
    );
  }
}

class _Counter extends StatelessWidget {
  const _Counter({
    required this.label,
    required this.count,
    required this.color,
  });

  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$count $label',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.78),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Category-chip row (mobile / narrow)
// ---------------------------------------------------------------------------

class _CategoryChipsRow extends ConsumerWidget {
  const _CategoryChipsRow({required this.tree});

  final CategoryTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(categorySelectionProvider);
    // Flatten roots first, then groups grouped by kind.
    final entries = <CategoryNode>[];
    if (tree.live.isNotEmpty && tree.live.first.count > 0) {
      entries.addAll(tree.live);
    }
    if (tree.movies.isNotEmpty && tree.movies.first.count > 0) {
      entries.addAll(tree.movies);
    }
    if (tree.series.isNotEmpty && tree.series.first.count > 0) {
      entries.addAll(tree.series);
    }
    if (entries.isEmpty) {
      return const SizedBox.shrink();
    }
    return ListView.separated(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceS,
      ),
      itemCount: entries.length,
      separatorBuilder: (_, __) =>
          const SizedBox(width: DesignTokens.spaceS),
      itemBuilder: (BuildContext _, int i) {
        final node = entries[i];
        final selected = selection == node;
        final label = node.isRoot
            ? 'Tum ${node.kind.label}'
            : node.name!;
        return ChoiceChip(
          label: Text(label),
          selected: selected,
          onSelected: (_) => ref
              .read(categorySelectionProvider.notifier)
              .select(node),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Category-tree pane (wide)
// ---------------------------------------------------------------------------

class CategoryTreePane extends ConsumerWidget {
  const CategoryTreePane({required this.tree, super.key});

  final CategoryTree tree;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final selection = ref.watch(categorySelectionProvider);

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.6),
        border: Border(
          right: BorderSide(
            color: scheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spaceS,
        ),
        children: <Widget>[
          _TreeBucket(
            kind: CategoryKind.live,
            nodes: tree.live,
            selection: selection,
          ),
          _TreeBucket(
            kind: CategoryKind.movies,
            nodes: tree.movies,
            selection: selection,
          ),
          _TreeBucket(
            kind: CategoryKind.series,
            nodes: tree.series,
            selection: selection,
          ),
        ],
      ),
    );
  }
}

class _TreeBucket extends ConsumerStatefulWidget {
  const _TreeBucket({
    required this.kind,
    required this.nodes,
    required this.selection,
  });

  final CategoryKind kind;
  final List<CategoryNode> nodes;
  final CategoryNode? selection;

  @override
  ConsumerState<_TreeBucket> createState() => _TreeBucketState();
}

class _TreeBucketState extends ConsumerState<_TreeBucket> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    if (widget.nodes.isEmpty) return const SizedBox.shrink();
    final root = widget.nodes.first;
    final children =
        widget.nodes.length > 1 ? widget.nodes.sublist(1) : <CategoryNode>[];
    if (root.count == 0) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;

    final IconData icon;
    final Color tint;
    switch (widget.kind) {
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

    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.spaceXs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Heading: toggles the bucket open/close + selects the root.
          _TreeRow(
            icon: icon,
            iconTint: tint,
            label: widget.kind.label,
            count: root.count,
            selected: widget.selection == root,
            indent: 0,
            heading: true,
            expanded: _expanded,
            hasChildren: children.isNotEmpty,
            onTap: () {
              ref
                  .read(categorySelectionProvider.notifier)
                  .select(root);
            },
            onToggle: children.isEmpty
                ? null
                : () => setState(() => _expanded = !_expanded),
          ),
          AnimatedSize(
            duration: DesignTokens.motionPanelSlide,
            curve: DesignTokens.motionStandard,
            child: !_expanded
                ? const SizedBox(width: double.infinity)
                : Column(
                    children: <Widget>[
                      for (final c in children)
                        _TreeRow(
                          icon: Icons.subdirectory_arrow_right_rounded,
                          iconTint: tint.withValues(alpha: 0.6),
                          label: c.name!,
                          count: c.count,
                          selected: widget.selection == c,
                          indent: 18,
                          heading: false,
                          expanded: false,
                          hasChildren: false,
                          onTap: () => ref
                              .read(categorySelectionProvider.notifier)
                              .select(c),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TreeRow extends StatefulWidget {
  const _TreeRow({
    required this.icon,
    required this.iconTint,
    required this.label,
    required this.count,
    required this.selected,
    required this.indent,
    required this.heading,
    required this.expanded,
    required this.hasChildren,
    required this.onTap,
    this.onToggle,
  });

  final IconData icon;
  final Color iconTint;
  final String label;
  final int count;
  final bool selected;
  final double indent;
  final bool heading;
  final bool expanded;
  final bool hasChildren;
  final VoidCallback onTap;
  final VoidCallback? onToggle;

  @override
  State<_TreeRow> createState() => _TreeRowState();
}

class _TreeRowState extends State<_TreeRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    final fg = selected
        ? scheme.onSurface
        : _hover
            ? scheme.onSurface.withValues(alpha: 0.95)
            : scheme.onSurface.withValues(alpha: 0.78);
    final bg = selected
        ? widget.iconTint.withValues(alpha: 0.14)
        : (_hover ? scheme.onSurface.withValues(alpha: 0.06) : null);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DesignTokens.motionFast,
          height: DesignTokens.categoryTreeRowHeight,
          margin: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceXs,
            vertical: 1,
          ),
          padding: EdgeInsets.only(left: widget.indent),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          ),
          child: Row(
            children: <Widget>[
              if (widget.hasChildren && widget.heading)
                IconButton(
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  iconSize: 16,
                  splashRadius: 14,
                  onPressed: widget.onToggle,
                  icon: AnimatedRotation(
                    duration: DesignTokens.motionMicroBounce,
                    turns: widget.expanded ? 0.25 : 0,
                    child: Icon(
                      Icons.chevron_right_rounded,
                      color:
                          scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                )
              else
                const SizedBox(width: 24),
              Icon(widget.icon, size: 16, color: widget.iconTint),
              const SizedBox(width: DesignTokens.spaceS),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: widget.heading
                        ? FontWeight.w800
                        : (selected
                            ? FontWeight.w700
                            : FontWeight.w500),
                    letterSpacing: widget.heading ? 0.6 : 0,
                    color: fg,
                  ),
                ),
              ),
              if (widget.count > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  margin: const EdgeInsets.only(
                    right: DesignTokens.spaceXs,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest
                        .withValues(alpha: 0.7),
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusS),
                  ),
                  child: Text(
                    _fmtCount(widget.count),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface
                          .withValues(alpha: 0.65),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtCount(int n) {
  if (n < 1000) return '$n';
  if (n < 10000) {
    return '${(n / 1000).toStringAsFixed(1)}k';
  }
  return '${(n / 1000).toStringAsFixed(0)}k';
}

// ---------------------------------------------------------------------------
// Centre grid pane
// ---------------------------------------------------------------------------

class _GridPane extends ConsumerWidget {
  const _GridPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(categorySelectionProvider);
    if (selection == null) {
      return const _SelectACategory();
    }
    switch (selection.kind) {
      case CategoryKind.live:
        return const _LiveGrid();
      case CategoryKind.movies:
        return const _MovieGrid();
      case CategoryKind.series:
        return const _SeriesGrid();
    }
  }
}

class _SelectACategory extends StatelessWidget {
  const _SelectACategory();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: EmptyState(
        icon: Icons.account_tree_outlined,
        title: 'Bir kategori sec',
        subtitle:
            'Sol panelden bir grup veya tur sec, icerik burada listelensin.',
      ),
    );
  }
}

class _LiveGrid extends ConsumerWidget {
  const _LiveGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channels = ref.watch(selectedLiveChannelsProvider);
    return channels.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) =>
          ErrorView(message: e.toString()),
      data: (List<Channel> values) {
        if (values.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.live_tv_outlined,
              title: 'Bu grupta kanal yok',
            ),
          );
        }
        return LayoutBuilder(
          builder: (BuildContext _, BoxConstraints c) {
            final cols = c.maxWidth > 1100
                ? 4
                : c.maxWidth > 760
                    ? 3
                    : 2;
            return GridView.builder(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: DesignTokens.spaceM,
                mainAxisSpacing: DesignTokens.spaceM,
                childAspectRatio: DesignTokens.channelTileAspect,
              ),
              itemCount: values.length,
              itemBuilder: (BuildContext _, int i) {
                final ch = values[i];
                return ChannelTile(
                  name: ch.name,
                  logoUrl: ch.logoUrl,
                  group: ch.groups.isEmpty ? null : ch.groups.first,
                  onTap: () => _playChannel(context, ch),
                );
              },
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

class _MovieGrid extends ConsumerWidget {
  const _MovieGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final vod = ref.watch(selectedVodProvider);
    return vod.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) =>
          ErrorView(message: e.toString()),
      data: (List<VodItem> values) {
        if (values.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.movie_outlined,
              title: 'Bu turde film yok',
            ),
          );
        }
        return LayoutBuilder(
          builder: (BuildContext _, BoxConstraints c) {
            final cols = c.maxWidth > 1100
                ? 6
                : c.maxWidth > 760
                    ? 4
                    : 3;
            return GridView.builder(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: DesignTokens.spaceM,
                mainAxisSpacing: DesignTokens.spaceM,
                childAspectRatio: DesignTokens.posterAspect,
              ),
              itemCount: values.length,
              itemBuilder: (BuildContext _, int i) {
                final v = values[i];
                return _PosterTile(
                  title: v.title,
                  imageUrl: v.posterUrl,
                  year: v.year,
                  rating: v.rating,
                  onTap: () => context.push('/movie/${v.id}'),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _SeriesGrid extends ConsumerWidget {
  const _SeriesGrid();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final series = ref.watch(selectedSeriesProvider);
    return series.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) =>
          ErrorView(message: e.toString()),
      data: (List<SeriesItem> values) {
        if (values.isEmpty) {
          return const Center(
            child: EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Bu turde dizi yok',
            ),
          );
        }
        return LayoutBuilder(
          builder: (BuildContext _, BoxConstraints c) {
            final cols = c.maxWidth > 1100
                ? 6
                : c.maxWidth > 760
                    ? 4
                    : 3;
            return GridView.builder(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: DesignTokens.spaceM,
                mainAxisSpacing: DesignTokens.spaceM,
                childAspectRatio: DesignTokens.posterAspect,
              ),
              itemCount: values.length,
              itemBuilder: (BuildContext _, int i) {
                final s = values[i];
                return _PosterTile(
                  title: s.title,
                  imageUrl: s.posterUrl,
                  year: s.year,
                  rating: s.rating,
                  onTap: () => context.push('/series/${s.id}'),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _PosterTile extends StatefulWidget {
  const _PosterTile({
    required this.title,
    required this.imageUrl,
    required this.onTap,
    this.year,
    this.rating,
  });

  final String title;
  final String? imageUrl;
  final int? year;
  final double? rating;
  final VoidCallback onTap;

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          duration: DesignTokens.motionFast,
          curve: Curves.easeOut,
          scale: _hover ? 1.03 : 1.0,
          child: AnimatedContainer(
            duration: DesignTokens.motionFast,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusL),
              boxShadow: _hover
                  ? <BoxShadow>[
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.40),
                        blurRadius: 24,
                        spreadRadius: 1,
                      ),
                    ]
                  : <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusL),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (widget.imageUrl != null && widget.imageUrl!.isNotEmpty)
                    CachedNetworkImage(
                      imageUrl: widget.imageUrl!,
                      fit: BoxFit.cover,
                      fadeInDuration: DesignTokens.motionFast,
                      errorWidget: (BuildContext _, String __, Object ___) =>
                          _PosterFallback(title: widget.title),
                    )
                  else
                    _PosterFallback(title: widget.title),
                  // Bottom scrim + title.
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
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (widget.year != null ||
                              widget.rating != null)
                            Row(
                              children: <Widget>[
                                if (widget.rating != null) ...<Widget>[
                                  const Icon(
                                    Icons.star_rounded,
                                    color: Color(0xFFFFC83D),
                                    size: 11,
                                  ),
                                  const SizedBox(width: 2),
                                  Text(
                                    widget.rating!.toStringAsFixed(1),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                if (widget.year != null)
                                  Text(
                                    '${widget.year}',
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 10,
                                    ),
                                  ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosterFallback extends StatelessWidget {
  const _PosterFallback({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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

// ---------------------------------------------------------------------------
// EPG strip pane (triple column only)
// ---------------------------------------------------------------------------

class _EpgStripPane extends ConsumerWidget {
  const _EpgStripPane();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selection = ref.watch(categorySelectionProvider);
    final scheme = Theme.of(context).colorScheme;

    if (selection == null || selection.kind != CategoryKind.live) {
      return Container(
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.45),
          border: Border(
            left: BorderSide(
              color: scheme.outline.withValues(alpha: 0.18),
            ),
          ),
        ),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Text(
          'Canli kanal sec, EPG burada gosterilecek',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurface.withValues(alpha: 0.55),
          ),
        ),
      );
    }

    final liveChannelsAsync = ref.watch(selectedLiveChannelsProvider);
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.45),
        border: Border(
          left: BorderSide(
            color: scheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: liveChannelsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object _, StackTrace __) => const SizedBox.shrink(),
        data: (List<Channel> channels) {
          final preview = channels.take(8).toList();
          if (preview.isEmpty) {
            return const SizedBox.shrink();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.spaceM,
                  DesignTokens.spaceM,
                  DesignTokens.spaceM,
                  DesignTokens.spaceS,
                ),
                child: Row(
                  children: <Widget>[
                    Icon(
                      Icons.schedule_rounded,
                      size: 14,
                      color: scheme.secondary,
                    ),
                    const SizedBox(width: DesignTokens.spaceXs),
                    Text(
                      'Simdi yayinda',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: scheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceS,
                  ),
                  itemCount: preview.length,
                  itemBuilder: (BuildContext _, int i) =>
                      _NowAiringRow(channel: preview[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NowAiringRow extends ConsumerWidget {
  const _NowAiringRow({required this.channel});

  final Channel channel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          onTap: () => context.push('/channel/${channel.id}'),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceS),
            child: Row(
              children: <Widget>[
                ClipRRect(
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusS),
                  child: SizedBox(
                    width: 32,
                    height: 32,
                    child: channel.logoUrl == null
                        ? Container(
                            color: scheme.surface,
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.live_tv_rounded,
                              size: 16,
                              color: scheme.onSurface
                                  .withValues(alpha: 0.6),
                            ),
                          )
                        : CachedNetworkImage(
                            imageUrl: channel.logoUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (
                              BuildContext _,
                              String __,
                              Object ___,
                            ) =>
                                Container(
                              color: scheme.surface,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceS),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      _ProgrammeLine(
                        tvgId: channel.tvgId,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgrammeLine extends ConsumerWidget {
  const _ProgrammeLine({required this.tvgId});

  final String? tvgId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    if (tvgId == null || tvgId!.isEmpty) {
      return Text(
        'EPG yok',
        style: TextStyle(
          fontSize: 10,
          color: scheme.onSurface.withValues(alpha: 0.45),
        ),
      );
    }

    // Tick once a minute so "now airing" stays fresh without a dedicated
    // provider family cache.
    ref.watch(epgClockProvider);
    return FutureBuilder<EpgProgramme?>(
      future: _resolveNow(ref, tvgId!),
      builder: (
        BuildContext _,
        AsyncSnapshot<EpgProgramme?> snap,
      ) {
        if (!snap.hasData || snap.data == null) {
          return Text(
            '...',
            style: TextStyle(
              fontSize: 10,
              color: scheme.onSurface.withValues(alpha: 0.45),
            ),
          );
        }
        final p = snap.data!;
        return Text(
          p.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: scheme.onSurface.withValues(alpha: 0.65),
          ),
        );
      },
    );
  }
}

Future<EpgProgramme?> _resolveNow(WidgetRef ref, String tvgId) async {
  final svc = ref.read(epgServiceProvider);
  final now = DateTime.now();
  try {
    final list = await svc.programmesFor(tvgId, around: now);
    for (final p in list) {
      if (p.start.isBefore(now) && p.stop.isAfter(now)) return p;
    }
  } on Exception {
    // EPG miss is fine — just no subtitle.
  }
  return null;
}

// ---------------------------------------------------------------------------
// Empty + loading
// ---------------------------------------------------------------------------

class _HomeLoading extends StatelessWidget {
  const _HomeLoading();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _HomeEmpty extends StatelessWidget {
  const _HomeEmpty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EmptyState(
        icon: Icons.playlist_add_rounded,
        title: 'Hosgeldin!',
        subtitle:
            'Bir liste ekleyince filmler, diziler ve canli kanallar burada belirir.',
        action: FilledButton.icon(
          onPressed: () => context.push('/playlists/add'),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Once bir liste ekle'),
        ),
      ),
    );
  }
}

