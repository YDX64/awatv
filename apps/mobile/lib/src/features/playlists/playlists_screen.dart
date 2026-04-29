import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/playlists/playlist_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/discovery/share_helper.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/premium/premium_quotas.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
        unawaited(
          PremiumLockSheet.show(
            context,
            PremiumFeature.unlimitedPlaylists,
          ),
        );
        return;
      }
      unawaited(context.push('/playlists/add'));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('playlists.list_title'.tr()),
        actions: [
          IconButton(
            tooltip: 'playlists.list_add_tooltip'.tr(),
            icon: const Icon(Icons.add),
            onPressed: onAddTap,
          ),
        ],
      ),
      body: playlists.when(
        loading: () => LoadingView(label: 'playlists.list_loading'.tr()),
        error: (Object err, StackTrace st) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(playlistsProvider),
        ),
        data: (List<PlaylistSource> sources) {
          if (sources.isEmpty) {
            return EmptyState(
              icon: Icons.queue_music_outlined,
              title: 'playlists.empty_title'.tr(),
              message: 'playlists.list_empty_msg'.tr(),
              actionLabel: 'common.add'.tr(),
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
        label: Text('playlists.add'.tr()),
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
      onTap: () => unawaited(
        PremiumLockSheet.show(
          context,
          PremiumFeature.unlimitedPlaylists,
        ),
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
                    'playlists.list_quota_label'.tr(
                      namedArgs: <String, String>{
                        'used': used.toString(),
                        'quota': quota.toString(),
                      },
                    ),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'playlists.list_quota_msg'.tr(),
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
        SnackBar(
          content: Text(
            'playlists.snack_refreshed'.tr(
              namedArgs: <String, String>{'name': widget.source.name},
            ),
          ),
        ),
      );
    } on Object catch (err) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'playlists.snack_refresh_failed'
                .tr(namedArgs: <String, String>{'message': err.toString()}),
          ),
        ),
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
          title: Text(
            'playlists.list_delete_confirm_title'
                .tr(namedArgs: <String, String>{'name': widget.source.name}),
          ),
          content: Text(
            'playlists.list_delete_confirm_message'.tr(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text('playlists.list_delete_cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('common.delete'.tr()),
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
        SnackBar(
          content: Text(
            'playlists.snack_deleted'.tr(
              namedArgs: <String, String>{'name': widget.source.name},
            ),
          ),
        ),
      );
    } on Object catch (err) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'playlists.snack_delete_failed'
                .tr(namedArgs: <String, String>{'message': err.toString()}),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.source;
    final fmt = DateFormat.yMMMd();
    final lastSync = s.lastSyncAt;
    final subtitle = StringBuffer()
      ..write(
        s.kind == PlaylistKind.xtream
            ? 'playlists.list_kind_xtream'.tr()
            : 'playlists.list_kind_m3u'.tr(),
      )
      ..write('  -  ');
    if (lastSync != null) {
      subtitle.write(
        'playlists.list_synced'
            .tr(namedArgs: <String, String>{'date': fmt.format(lastSync)}),
      );
    } else {
      subtitle.write('playlists.list_never_synced'.tr());
    }

    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      ),
      child: Dismissible(
        key: ValueKey<String>('playlist_${s.id}'),
        // Right-to-left swipe: share. We never auto-confirm — Dismissible
        // returns false from confirmDismiss so the row springs back. The
        // swipe is purely an alternative entry point to the share action.
        direction: DismissDirection.endToStart,
        background: const SizedBox.shrink(),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceL,
          ),
          decoration: BoxDecoration(
            color: BrandColors.primary.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              const Icon(Icons.share_rounded, color: BrandColors.primary),
              const SizedBox(width: DesignTokens.spaceS),
              Text(
                'playlists.list_swipe_share'.tr(),
                style: const TextStyle(
                  color: BrandColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        confirmDismiss: (DismissDirection _) async {
          await ShareHelper.sharePlaylist(context, s);
          return false;
        },
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
                  unawaited(_refresh());
                case 'share':
                  unawaited(ShareHelper.sharePlaylist(context, s));
                case 'delete':
                  unawaited(_confirmDelete());
              }
            },
            itemBuilder: (BuildContext ctx) => <PopupMenuEntry<String>>[
              PopupMenuItem(
                value: 'refresh',
                child: ListTile(
                  leading: const Icon(Icons.refresh),
                  title: Text('playlists.list_action_refresh'.tr()),
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: const Icon(Icons.share_outlined),
                  title: Text('playlists.list_action_share'.tr()),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: Text('playlists.list_action_delete'.tr()),
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
      ),
    );
  }
}
