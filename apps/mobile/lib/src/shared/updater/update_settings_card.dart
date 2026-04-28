import 'dart:io' show Platform;

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/shared/updater/update_state.dart';
import 'package:awatv_mobile/src/shared/updater/updater_service.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Settings tile group that owns everything user-facing for the updater:
///
///   * Live version line ("AWAtv 0.3.0")
///   * "Güncellemeleri kontrol et" button
///   * Coloured card when an update is on offer (notes + download button)
///   * Progress bar during download
///   * "Yeniden başlat ve yükle" CTA when ready
///   * Inline error state with retry
///
/// Renders on every platform so the version line is always visible.
/// The check / download / install actions are gated behind macOS and
/// Windows — other platforms see "Bu cihazda otomatik güncelleme yok"
/// instead, since iOS / Android / Web are updated through their own
/// stores or as fresh deploys.
class UpdateSettingsCard extends ConsumerStatefulWidget {
  const UpdateSettingsCard({super.key});

  @override
  ConsumerState<UpdateSettingsCard> createState() =>
      _UpdateSettingsCardState();
}

class _UpdateSettingsCardState extends ConsumerState<UpdateSettingsCard> {
  String? _version;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = info.version);
    } on Object {
      // Leave _version null — the row falls back to "—" so the layout
      // doesn't shift as soon as the future resolves.
    }
  }

  bool get _supportsAutoUpdate {
    if (kIsWeb) return false;
    if (!isDesktopRuntime()) return false;
    return Platform.isMacOS || Platform.isWindows;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(updaterServiceProvider);
    final theme = Theme.of(context);
    final version = _version ?? '—';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: const Text('Hakkında'),
          subtitle: Text('AWAtv $version'),
          onTap: () {
            showAboutDialog(
              context: context,
              applicationName: 'AWAtv',
              applicationVersion: version,
              applicationIcon: const Icon(Icons.live_tv_rounded, size: 32),
              children: const <Widget>[
                Text(
                  'Cross-platform IPTV oynatıcı. M3U / Xtream destekli, '
                  'TMDB metadata zenginleştirmeli, premium abonelikli.',
                ),
              ],
            );
          },
        ),
        if (!_supportsAutoUpdate)
          const ListTile(
            leading: Icon(Icons.system_update_alt_outlined),
            title: Text('Otomatik güncelleme'),
            subtitle: Text(
              'Bu platformda güncellemeler mağaza üzerinden gelir.',
            ),
            enabled: false,
          )
        else
          _buildUpdateRow(context, state, theme),
      ],
    );
  }

  Widget _buildUpdateRow(
    BuildContext context,
    UpdateState state,
    ThemeData theme,
  ) {
    return switch (state) {
      UpdateIdle() => _checkTile(
          subtitle: 'Yeni sürümleri elle kontrol edebilirsin.',
        ),
      UpdateChecking() => const ListTile(
          leading: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Güncelleme aranıyor…'),
          subtitle: Text('GitHub Releases üzerinden kontrol ediliyor.'),
        ),
      final UpdateUpToDate s => _checkTile(
          subtitle: 'Sürümün güncel — son kontrol ${_formatTime(s.checkedAt)}.',
        ),
      final UpdateAvailable s => _availableCard(context, s, theme),
      final UpdateDownloading s => _downloadingTile(s, theme),
      final UpdateReadyToInstall s => _readyTile(context, s, theme),
      final UpdateInstalling s => ListTile(
          leading: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text('Sürüm ${s.remoteVersion} kuruluyor…'),
          subtitle: const Text(
            'AWAtv otomatik olarak yeniden başlatılacak.',
          ),
        ),
      final UpdateError s => _errorTile(context, s),
    };
  }

  Widget _checkTile({required String subtitle}) {
    return ListTile(
      leading: const Icon(Icons.system_update_alt_outlined),
      title: const Text('Güncellemeleri kontrol et'),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.refresh_rounded),
      onTap: () => ref
          .read(updaterServiceProvider.notifier)
          .checkForUpdates(silent: false),
    );
  }

  Widget _availableCard(
    BuildContext context,
    UpdateAvailable s,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    final notes = s.notes.trim().isEmpty
        ? 'Yeni sürümde iyileştirmeler ve hata düzeltmeleri yer alıyor.'
        : s.notes.trim();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.primaryContainer.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
        ),
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.upgrade_rounded, color: scheme.primary, size: 28),
                const SizedBox(width: DesignTokens.spaceS),
                Expanded(
                  child: Text(
                    'Yeni sürüm: ${s.remoteVersion}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (s.forceUpdate)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.error.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'ZORUNLU',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.error,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceS),
            Text(notes, style: theme.textTheme.bodyMedium),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              'Boyut: ${_formatBytes(s.size)}'
              '${s.releasedAt != null ? '  •  Yayın: ${_formatDate(s.releasedAt!)}' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Row(
              children: <Widget>[
                if (!s.forceUpdate)
                  TextButton(
                    onPressed: () =>
                        ref.read(updaterServiceProvider.notifier).reset(),
                    child: const Text('Sonra'),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () =>
                      ref.read(updaterServiceProvider.notifier).downloadUpdate(),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('İndir ve kur'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _downloadingTile(UpdateDownloading s, ThemeData theme) {
    final pct = (s.progress * 100).clamp(0, 100).toStringAsFixed(0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceS,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Sürüm ${s.remoteVersion} indiriliyor… $pct%',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: DesignTokens.spaceXs),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: s.progress,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_formatBytes(s.bytesReceived)} / ${_formatBytes(s.totalBytes)}',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _readyTile(
    BuildContext context,
    UpdateReadyToInstall s,
    ThemeData theme,
  ) {
    return ListTile(
      leading: Icon(
        Icons.task_alt_rounded,
        color: theme.colorScheme.primary,
      ),
      title: Text('Sürüm ${s.remoteVersion} hazır'),
      subtitle: const Text(
        'Yeniden başlat ve yeni sürüme geç.',
      ),
      trailing: FilledButton.icon(
        onPressed: () =>
            ref.read(updaterServiceProvider.notifier).installUpdate(),
        icon: const Icon(Icons.restart_alt_rounded),
        label: const Text('Yeniden başlat'),
      ),
    );
  }

  Widget _errorTile(BuildContext context, UpdateError s) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(Icons.error_outline, color: theme.colorScheme.error),
      title: const Text('Güncelleme alınamadı'),
      subtitle: Text(s.message),
      trailing: TextButton(
        onPressed: () {
          ref.read(updaterServiceProvider.notifier).reset();
          ref
              .read(updaterServiceProvider.notifier)
              .checkForUpdates(silent: false);
        },
        child: const Text('Tekrar dene'),
      ),
    );
  }

  // ----------------------- formatting helpers -------------------------

  String _formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = <String>['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit++;
    }
    return '${size.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
  }

  String _formatTime(DateTime when) {
    final now = DateTime.now();
    final diff = now.difference(when);
    if (diff.inSeconds < 60) return 'az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    return _formatDate(when);
  }

  String _formatDate(DateTime when) {
    final local = when.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
