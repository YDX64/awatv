import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/favorites/favorites_providers.dart';
import 'package:awatv_mobile/src/features/favorites/folder_picker_sheet.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_mobile/src/shared/stream_url.dart';
import 'package:awatv_mobile/src/shared/web_proxy.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Folders + favourites screen — replaces the legacy "Favoriler" sidebar
/// placeholder. Top: chip row with each folder and a "+" affordance.
/// Body: grid/list of channels in the active folder.
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foldersAsync = ref.watch(favoriteFoldersStreamProvider);
    final selectedId = ref.watch(selectedFavoriteFolderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Favoriler'),
      ),
      body: foldersAsync.when(
        loading: () => const LoadingView(label: 'Klasorler yukleniyor'),
        error: (Object err, StackTrace _) =>
            ErrorView(message: err.toString()),
        data: (List<FavoriteFolder> folders) {
          if (folders.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'Klasor yok',
                subtitle:
                    'Favoriye ekledigin kanallar burada gozukur. Bir kanali kalp ikonu ile favorilere ekle.',
              ),
            );
          }
          // Default folder picks itself if the previously-selected one
          // got deleted.
          final activeId = folders.any(
            (FavoriteFolder f) => f.id == selectedId,
          )
              ? selectedId
              : FavoritesService.kDefaultFolderId;

          return Column(
            children: <Widget>[
              _FolderChipRow(
                folders: folders,
                selectedId: activeId,
                onSelect: (String id) =>
                    ref.read(selectedFavoriteFolderProvider.notifier).state = id,
              ),
              const Divider(height: 1),
              Expanded(
                child: _FolderChannelsBody(folderId: activeId),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FolderChipRow extends ConsumerWidget {
  const _FolderChipRow({
    required this.folders,
    required this.selectedId,
    required this.onSelect,
  });

  final List<FavoriteFolder> folders;
  final String selectedId;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 60,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceS,
        ),
        child: Row(
          children: <Widget>[
            for (final f in folders) ...<Widget>[
              _FolderChip(
                folder: f,
                selected: f.id == selectedId,
                onTap: () => onSelect(f.id),
                onLongPress: f.isDefault
                    ? null
                    : () => _showFolderActions(context, ref, f),
              ),
              const SizedBox(width: DesignTokens.spaceS),
            ],
            _AddFolderChip(
              onTap: () => _onCreateFolder(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onCreateFolder(BuildContext context, WidgetRef ref) async {
    final allowed = ref.read(canUseFeatureProvider(PremiumFeature.cloudSync));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.cloudSync);
      return;
    }
    final name = await _promptFolderName(context, initial: '');
    if (name == null || name.trim().isEmpty) return;
    final svc = ref.read(favoritesServiceProvider);
    await svc.createFolder(name: name);
  }

  Future<void> _showFolderActions(
    BuildContext context,
    WidgetRef ref,
    FavoriteFolder folder,
  ) async {
    final svc = ref.read(favoritesServiceProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: const Text('Yeniden adlandir'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final name = await _promptFolderName(
                    context,
                    initial: folder.name,
                  );
                  if (name != null && name.trim().isNotEmpty) {
                    await svc.renameFolder(folder.id, name);
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.delete_outline_rounded,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  'Klasoru sil',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
                subtitle: const Text(
                  'Kanallar favorilerden cikmaz, sadece klasor silinir.',
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await svc.deleteFolder(folder.id);
                  if (ref.read(selectedFavoriteFolderProvider) == folder.id) {
                    ref.read(selectedFavoriteFolderProvider.notifier).state =
                        FavoritesService.kDefaultFolderId;
                  }
                },
              ),
              const SizedBox(height: DesignTokens.spaceM),
            ],
          ),
        );
      },
    );
  }

  Future<String?> _promptFolderName(
    BuildContext context, {
    required String initial,
  }) async {
    final controller = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text(
            initial.isEmpty ? 'Yeni klasor' : 'Klasoru yeniden adlandir',
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              hintText: 'Klasor adi',
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onSubmitted: (String value) => Navigator.of(ctx).pop(value),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Iptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(controller.text),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );
  }
}

class _FolderChip extends StatelessWidget {
  const _FolderChip({
    required this.folder,
    required this.selected,
    required this.onTap,
    this.onLongPress,
  });

  final FavoriteFolder folder;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tint = folder.color != null
        ? Color(folder.color!)
        : (selected ? scheme.primary : scheme.surfaceContainerHighest);
    return GestureDetector(
      onLongPress: onLongPress,
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.18)
            : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceS,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tint,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceS),
                Text(
                  folder.name,
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: selected ? scheme.primary : scheme.onSurface,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${folder.channelIds.length}',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
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

class _AddFolderChip extends StatelessWidget {
  const _AddFolderChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.add_rounded,
                color: scheme.primary,
                size: 18,
              ),
              const SizedBox(width: 4),
              Text(
                'Yeni klasor',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FolderChannelsBody extends ConsumerWidget {
  const _FolderChannelsBody({required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final channelsAsync = ref.watch(folderChannelsProvider(folderId));
    return channelsAsync.when(
      loading: () => const LoadingView(label: 'Kanallar yukleniyor'),
      error: (Object err, StackTrace _) =>
          ErrorView(message: err.toString()),
      data: (List<Channel> channels) {
        if (channels.isEmpty) {
          return Center(
            child: EmptyState(
              icon: Icons.favorite_border_rounded,
              title: folderId == FavoritesService.kDefaultFolderId
                  ? 'Henuz favori yok'
                  : 'Bu klasor bos',
              subtitle: folderId == FavoritesService.kDefaultFolderId
                  ? 'Bir kanali favorilere ekledigin anda burada gorunur.'
                  : 'Kanali uzun bas, "Klasor degistir" ile buraya tasi.',
            ),
          );
        }
        return LayoutBuilder(
          builder: (BuildContext _, BoxConstraints c) {
            final width = c.maxWidth;
            final cols = width > 900
                ? 4
                : width > 600
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
              itemCount: channels.length,
              itemBuilder: (BuildContext ctx, int i) {
                final ch = channels[i];
                return ChannelTile(
                  name: ch.name,
                  logoUrl: ch.logoUrl,
                  group: ch.groups.isEmpty ? null : ch.groups.first,
                  onTap: () => _play(context, ch),
                  onLongPress: () =>
                      _onChannelLongPress(context, ref, ch, folderId),
                );
              },
            );
          },
        );
      },
    );
  }

  void _play(BuildContext context, Channel channel) {
    final headers = <String, String>{};
    final referer = channel.extras['http-referrer'] ??
        channel.extras['referer'] ??
        channel.extras['Referer'];
    if (referer != null && referer.isNotEmpty) headers['Referer'] = referer;
    final urls = streamUrlVariants(channel.streamUrl).map(proxify).toList();
    final variants = MediaSource.variants(
      urls,
      title: channel.name,
      userAgent: channel.extras['http-user-agent'] ?? channel.extras['user-agent'],
      headers: headers.isEmpty ? null : headers,
    );
    final args = PlayerLaunchArgs(
      source: variants.isEmpty
          ? MediaSource(url: proxify(channel.streamUrl), title: channel.name)
          : variants.first,
      fallbacks: variants.length <= 1
          ? const <MediaSource>[]
          : variants.sublist(1),
      title: channel.name,
      subtitle: channel.groups.isEmpty ? null : channel.groups.first,
      itemId: channel.id,
      kind: HistoryKind.live,
      isLive: true,
    );
    context.push('/play', extra: args);
  }

  Future<void> _onChannelLongPress(
    BuildContext context,
    WidgetRef ref,
    Channel channel,
    String currentFolderId,
  ) async {
    final svc = ref.read(favoritesServiceProvider);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.drive_file_move_outlined),
                title: const Text('Klasor degistir'),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  final next = await FolderPickerSheet.show(
                    context,
                    channelId: channel.id,
                  );
                  if (next != null && next != currentFolderId) {
                    await svc.moveChannelBetweenFolders(
                      channelId: channel.id,
                      fromFolderId: currentFolderId,
                      toFolderId: next,
                    );
                  }
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.heart_broken_outlined,
                  color: Theme.of(ctx).colorScheme.error,
                ),
                title: Text(
                  'Favorilerden cikar',
                  style: TextStyle(
                    color: Theme.of(ctx).colorScheme.error,
                  ),
                ),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await svc.toggle(channel.id);
                },
              ),
              const SizedBox(height: DesignTokens.spaceM),
            ],
          ),
        );
      },
    );
  }
}

