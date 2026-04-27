import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/premium/premium_quotas.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

/// Lists every `PlaylistSource` the user has registered. Each row supports
/// pull-to-refresh, tap-to-resync, and swipe-to-delete via the trailing
/// menu.
class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    final quota = ref.watch(playlistQuotaProvider);

    // Resolve the current count synchronously when the source list is
    // already loaded; otherwise treat as unknown and let the gate
    // re-check at tap time.
    final currentCount = playlists.value?.length ?? 0;
    final atQuota = currentCount >= quota;

    void onAddTap() {
      // Re-read at the moment of tap so a refresh-in-flight cannot
      // race past the gate.
      final live = ref.read(playlistsProvider).value?.length ?? 0;
      final liveQuota = ref.read(playlistQuotaProvider);
      if (live >= liveQuota) {
        PremiumLockSheet.show(
          context,
          PremiumFeature.unlimitedPlaylists,
        );
        return;
      }
      context.push('/playlists/add');
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Listelerim'),
        actions: [
          IconButton(
            tooltip: 'Yeni liste ekle',
            icon: const Icon(Icons.add),
            onPressed: onAddTap,
          ),
        ],
      ),
      body: playlists.when(
        loading: () => const LoadingView(label: 'Listeler yukleniyor'),
        error: (Object err, StackTrace st) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(playlistsProvider),
        ),
        data: (List<PlaylistSource> sources) {
          if (sources.isEmpty) {
            return EmptyState(
              icon: Icons.queue_music_outlined,
              title: 'Henuz liste yok',
              message: 'Bir M3U veya Xtream Codes hesabi ekleyerek basla.',
              actionLabel: 'Ekle',
              onAction: onAddTap,
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(playlistsProvider);
              await ref.read(playlistsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              itemCount: sources.length + (atQuota ? 1 : 0),
              separatorBuilder: (_, __) =>
                  const SizedBox(height: DesignTokens.spaceS),
              itemBuilder: (BuildContext context, int i) {
                if (i == sources.length) {
                  // Trailing quota notice — visible only when the user
                  // is at the free-tier ceiling.
                  return _QuotaNotice(
                    used: sources.length,
                    quota: quota,
                  );
                }
                final source = sources[i];
                return _PlaylistTile(source: source);
              },
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: onAddTap,
        icon: Icon(atQuota ? Icons.lock_rounded : Icons.add),
        label: const Text('Liste ekle'),
      ),
    );
  }
}

/// Trailing card surfaced when the free tier ceiling has been reached.
/// Tapping it routes to the paywall via the lock sheet.
class _QuotaNotice extends StatelessWidget {
  const _QuotaNotice({required this.used, required this.quota});
  final int used;
  final int quota;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      onTap: () => PremiumLockSheet.show(
        context,
        PremiumFeature.unlimitedPlaylists,
      ),
      child: Ink(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.workspace_premium_rounded,
              color: BrandColors.primary,
            ),
            const SizedBox(width: DesignTokens.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ucretsiz tier limiti: $used / $quota',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Premium ile sinirsiz liste ekleyebilirsin.',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _PlaylistTile extends ConsumerStatefulWidget {
  const _PlaylistTile({required this.source});

  final PlaylistSource source;

  @override
  ConsumerState<_PlaylistTile> createState() => _PlaylistTileState();
}

class _PlaylistTileState extends ConsumerState<_PlaylistTile> {
  bool _refreshing = false;

  Future<void> _refresh() async {
    setState(() => _refreshing = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(playlistServiceProvider).refresh(widget.source.id);
      ref.invalidate(playlistsProvider);
      ref.invalidate(playlistChannelsProvider(widget.source.id));
      ref.invalidate(allChannelsProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('"${widget.source.name}" guncellendi')),
      );
    } on Object catch (err) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Yenilenemedi: $err')),
      );
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  Future<void> _confirmDelete() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: Text('"${widget.source.name}" silinsin mi?'),
          content: const Text(
            'Bu liste ve onun kanallari/film/dizi katalogu silinecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgec'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Sil'),
            ),
          ],
        );
      },
    );
    if (result != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(playlistServiceProvider).remove(widget.source.id);
      ref.invalidate(playlistsProvider);
      ref.invalidate(allChannelsProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('"${widget.source.name}" silindi')),
      );
    } on Object catch (err) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Silinemedi: $err')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final fmt = DateFormat.yMMMd();
    final lastSync = s.lastSyncAt;
    final subtitle = StringBuffer()
      ..write(s.kind == PlaylistKind.xtream ? 'Xtream Codes' : 'M3U')
      ..write('  -  ');
    if (lastSync != null) {
      subtitle.write('Son senkron: ${fmt.format(lastSync)}');
    } else {
      subtitle.write('Henuz senkronlanmadi');
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Icon(
            s.kind == PlaylistKind.xtream
                ? Icons.satellite_alt_outlined
                : Icons.list_alt_rounded,
          ),
        ),
        title: Text(
          s.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(subtitle.toString()),
        trailing: PopupMenuButton<String>(
          onSelected: (String value) {
            switch (value) {
              case 'refresh':
                _refresh();
              case 'delete':
                _confirmDelete();
            }
          },
          itemBuilder: (BuildContext ctx) => const <PopupMenuEntry<String>>[
            PopupMenuItem(
              value: 'refresh',
              child: ListTile(
                leading: Icon(Icons.refresh),
                title: Text('Yenile'),
              ),
            ),
            PopupMenuItem(
              value: 'delete',
              child: ListTile(
                leading: Icon(Icons.delete_outline),
                title: Text('Sil'),
              ),
            ),
          ],
          child: _refreshing
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.more_vert),
        ),
      ),
    );
  }
}
