import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_engine.dart';
import 'package:awatv_mobile/src/shared/sync/cloud_sync_providers.dart';
import 'package:awatv_mobile/src/shared/sync/sync_envelope.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// Active devices for the signed-in user.
///
/// Renders one row per `device_sessions` row with a "sign out" affordance
/// that revokes the row remotely. The current device is highlighted but
/// not revokable from this screen — the user signs the current device
/// out via Settings → Account.
class ManageDevicesScreen extends ConsumerWidget {
  const ManageDevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(deviceSessionsProvider);
    final engine = ref.watch(cloudSyncEnginePulseProvider);
    final currentRowId = engine.deviceRowId;

    return Scaffold(
      appBar: AppBar(title: const Text('Cihazlar')),
      body: devicesAsync.when(
        loading: () => const LoadingView(label: 'Cihazlar yükleniyor'),
        error: (Object err, StackTrace st) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(deviceSessionsProvider),
        ),
        data: (List<DeviceSessionRow> rows) {
          if (rows.isEmpty) {
            return const EmptyState(
              icon: Icons.devices_other_outlined,
              title: 'Henüz cihaz kayıtlı değil',
              message: 'Hesabınla oturum açtığın her cihaz burada listelenir.',
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(deviceSessionsProvider);
              await ref.read(deviceSessionsProvider.future);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              itemCount: rows.length,
              separatorBuilder: (_, __) =>
                  const SizedBox(height: DesignTokens.spaceS),
              itemBuilder: (BuildContext ctx, int i) {
                final row = rows[i];
                final isCurrent = row.id == currentRowId;
                return _DeviceTile(
                  row: row,
                  isCurrent: isCurrent,
                  onRevoke: isCurrent
                      ? null
                      : () => _confirmRevoke(context, ref, row),
                );
              },
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmRevoke(
    BuildContext context,
    WidgetRef ref,
    DeviceSessionRow row,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) {
        return AlertDialog(
          title: const Text('Cihazı oturumdan çıkar'),
          content: Text(
            '"${_kindLabelTr(row.kind)} - ${row.platform}" oturumu '
            'sonlandırılsın mı?\n\n'
            'Cihaz tekrar açıldığında yeniden oturum açılması gerekecek.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Çıkar'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(cloudSyncEnginePulseProvider).revokeDevice(row.id);
      ref.invalidate(deviceSessionsProvider);
      if (!context.mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Cihaz çıkarıldı')),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({
    required this.row,
    required this.isCurrent,
    required this.onRevoke,
  });

  final DeviceSessionRow row;
  final bool isCurrent;
  final VoidCallback? onRevoke;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = DateFormat.yMMMd().add_Hm();
    return Material(
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        side: BorderSide(
          color: isCurrent
              ? theme.colorScheme.primary.withValues(alpha: 0.5)
              : theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCurrent
              ? theme.colorScheme.primary
              : theme.colorScheme.surfaceContainerHighest,
          foregroundColor: isCurrent
              ? theme.colorScheme.onPrimary
              : theme.colorScheme.onSurface,
          child: Icon(_iconFor(row.kind)),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                _kindLabelTr(row.kind),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (isCurrent)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Bu cihaz',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(row.platform, style: theme.textTheme.bodySmall),
              Text(
                'Son aktif: ${fmt.format(row.lastSeenAt.toLocal())}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
        trailing: onRevoke == null
            ? null
            : IconButton(
                tooltip: 'Cihazı çıkar',
                icon: const Icon(Icons.logout_rounded),
                onPressed: onRevoke,
              ),
      ),
    );
  }

  IconData _iconFor(DeviceKind kind) => switch (kind) {
        DeviceKind.phone => Icons.phone_iphone_rounded,
        DeviceKind.tablet => Icons.tablet_mac_rounded,
        DeviceKind.tv => Icons.tv_rounded,
        DeviceKind.desktop => Icons.desktop_mac_rounded,
        DeviceKind.web => Icons.web_rounded,
      };
}

String _kindLabelTr(DeviceKind kind) => switch (kind) {
      DeviceKind.phone => 'Telefon',
      DeviceKind.tablet => 'Tablet',
      DeviceKind.tv => 'TV',
      DeviceKind.desktop => 'Masaüstü',
      DeviceKind.web => 'Tarayıcı',
    };
