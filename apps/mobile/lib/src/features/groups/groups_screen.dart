import 'package:awatv_mobile/src/features/groups/group_customisation_provider.dart';
import 'package:awatv_mobile/src/features/groups/group_customisation_service.dart';
import 'package:awatv_mobile/src/features/home/category_tree_provider.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `/settings/groups` — drag-to-reorder, hide and rename group
/// customisation surface (mirrors the equivalent IPTV-Expert flow).
///
/// Three tabs (Live / Movies / Series) — one [_KindTab] each. The
/// underlying data is the raw [categoryTreeProvider] + the persisted
/// [GroupCustomisations]; we present the leaves as a reorderable list
/// and surface visibility / rename actions per row.
class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kanal gruplari'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Sifirla',
            icon: const Icon(Icons.restore_rounded),
            onPressed: _confirmReset,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Tab>[
            Tab(text: 'Canli'),
            Tab(text: 'Filmler'),
            Tab(text: 'Diziler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const <Widget>[
          _KindTab(kind: CategoryKind.live),
          _KindTab(kind: CategoryKind.movies),
          _KindTab(kind: CategoryKind.series),
        ],
      ),
    );
  }

  Future<void> _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Sifirla'),
        content: const Text(
          'Tum gruplarda sira, gizleme ve isim degisikliklerini sifirla?',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sifirla'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(groupCustomisationServiceProvider).resetAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        duration: Duration(seconds: 2),
        content: Text('Tum gruplar varsayilana donduruldu.'),
      ),
    );
  }
}

class _KindTab extends ConsumerWidget {
  const _KindTab({required this.kind});

  final CategoryKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final treeAsync = ref.watch(categoryTreeProvider);
    final customs = ref.watch(groupCustomisationsProvider).valueOrNull ??
        GroupCustomisations.empty;
    return treeAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object e, StackTrace _) => ErrorView(message: e.toString()),
      data: (CategoryTree tree) {
        final bucket = _bucketFor(tree);
        // Skip the root "Tum X" header; we only customise leaves.
        final leaves = bucket.length > 1 ? bucket.sublist(1) : <CategoryNode>[];
        if (leaves.isEmpty) {
          return const EmptyState(
            icon: Icons.category_outlined,
            title: 'Grup yok',
            message: 'Bu icerik turunde henuz grup yok.',
          );
        }
        // Render the leaves in the user's persisted order. Unknown
        // groups (just synced) drop to the tail alphabetically.
        final order = customs.order[kind] ?? const <String>[];
        final orderIdx = <String, int>{
          for (var i = 0; i < order.length; i++) order[i]: i,
        };
        final ordered = List<CategoryNode>.of(leaves)
          ..sort((CategoryNode a, CategoryNode b) {
            final ai = orderIdx[a.name ?? ''];
            final bi = orderIdx[b.name ?? ''];
            if (ai != null && bi != null) return ai.compareTo(bi);
            if (ai != null) return -1;
            if (bi != null) return 1;
            return (a.name ?? '')
                .toLowerCase()
                .compareTo((b.name ?? '').toLowerCase());
          });
        return _ReorderableList(kind: kind, items: ordered, customs: customs);
      },
    );
  }

  List<CategoryNode> _bucketFor(CategoryTree tree) {
    switch (kind) {
      case CategoryKind.live:
        return tree.live;
      case CategoryKind.movies:
        return tree.movies;
      case CategoryKind.series:
        return tree.series;
    }
  }
}

class _ReorderableList extends ConsumerStatefulWidget {
  const _ReorderableList({
    required this.kind,
    required this.items,
    required this.customs,
  });

  final CategoryKind kind;
  final List<CategoryNode> items;
  final GroupCustomisations customs;

  @override
  ConsumerState<_ReorderableList> createState() => _ReorderableListState();
}

class _ReorderableListState extends ConsumerState<_ReorderableList> {
  late List<CategoryNode> _local;

  @override
  void initState() {
    super.initState();
    _local = List<CategoryNode>.of(widget.items);
  }

  @override
  void didUpdateWidget(covariant _ReorderableList oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Keep the local list in sync with provider data unless the user
    // is actively dragging.
    if (oldWidget.items.length != widget.items.length ||
        !_sameOrder(oldWidget.items, widget.items)) {
      _local = List<CategoryNode>.of(widget.items);
    }
  }

  bool _sameOrder(List<CategoryNode> a, List<CategoryNode> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].name != b[i].name) return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceM,
      ),
      itemCount: _local.length,
      onReorder: _onReorder,
      proxyDecorator: (Widget child, int _, Animation<double> __) {
        return Material(
          elevation: 4,
          color: scheme.surface,
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: child,
        );
      },
      itemBuilder: (BuildContext _, int i) {
        final node = _local[i];
        final groupName = node.name ?? '';
        final hidden = widget.customs.isHidden(widget.kind, groupName);
        final alias = (widget.customs.aliases[widget.kind] ??
            const <String, String>{})[groupName];
        return _GroupRow(
          key: ValueKey<String>('grp:${widget.kind.name}:$groupName'),
          node: node,
          hidden: hidden,
          alias: alias,
          onToggleHidden: () async {
            await ref
                .read(groupCustomisationServiceProvider)
                .setHidden(widget.kind, groupName, value: !hidden);
          },
          onRename: () => _onRename(groupName, alias),
        );
      },
    );
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    setState(() {
      var to = newIndex;
      if (oldIndex < to) to -= 1;
      final moved = _local.removeAt(oldIndex);
      _local.insert(to, moved);
    });
    final ordered = <String>[
      for (final n in _local)
        if (n.name != null) n.name!,
    ];
    await ref
        .read(groupCustomisationServiceProvider)
        .setOrder(widget.kind, ordered);
  }

  Future<void> _onRename(String groupName, String? currentAlias) async {
    final controller =
        TextEditingController(text: currentAlias ?? groupName);
    final next = await showDialog<String?>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Grup adini degistir'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Yeni isim',
            hintText: groupName,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgec'),
          ),
          if (currentAlias != null)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: const Text('Sifirla'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (next == null) return;
    await ref
        .read(groupCustomisationServiceProvider)
        .setAlias(widget.kind, groupName, next);
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({
    required this.node,
    required this.hidden,
    required this.alias,
    required this.onToggleHidden,
    required this.onRename,
    super.key,
  });

  final CategoryNode node;
  final bool hidden;
  final String? alias;
  final VoidCallback onToggleHidden;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final original = node.name ?? '';
    final shown = (alias != null && alias!.isNotEmpty) ? alias! : original;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Material(
        color: hidden
            ? scheme.surface.withValues(alpha: 0.4)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: ListTile(
          dense: true,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          ),
          leading: Icon(
            Icons.drag_indicator_rounded,
            color: scheme.onSurface.withValues(alpha: 0.5),
          ),
          title: Text(
            shown,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              decoration:
                  hidden ? TextDecoration.lineThrough : TextDecoration.none,
              color: hidden
                  ? scheme.onSurface.withValues(alpha: 0.5)
                  : scheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Row(
            children: <Widget>[
              if (alias != null && alias!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    'Asil: $original',
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              Text(
                '${node.count} icerik',
                style: TextStyle(
                  fontSize: 11,
                  color: scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Adini degistir',
                icon: const Icon(Icons.edit_rounded, size: 18),
                onPressed: onRename,
              ),
              IconButton(
                tooltip: hidden ? 'Goster' : 'Gizle',
                icon: Icon(
                  hidden
                      ? Icons.visibility_off_rounded
                      : Icons.visibility_rounded,
                  size: 18,
                ),
                onPressed: onToggleHidden,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
