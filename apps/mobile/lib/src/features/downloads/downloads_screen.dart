import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/downloads/downloads_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Offline downloads hub.
///
/// Tabs: Indirilenler (completed) / Indiriliyor (active + pending +
/// paused). Surfaces total disk usage at the bottom and a "Tumunu sil"
/// action to wipe finished items.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Indirilenler')),
        body: const _UnsupportedPlatform(),
      );
    }
    final downloadsAsync = ref.watch(downloadsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Indirilenler'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Tumunu sil',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmDeleteAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'Indirilenler'),
            Tab(text: 'Indiriliyor'),
          ],
        ),
      ),
      body: downloadsAsync.when(
        loading: () => const LoadingView(label: 'Indirmeler yukleniyor'),
        error: (Object err, StackTrace _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(downloadsProvider),
        ),
        data: (List<DownloadTask> all) {
          final completed = all
              .where((DownloadTask t) =>
                  t.status == DownloadStatus.completed)
              .toList();
          final active = all
              .where((DownloadTask t) =>
                  t.status == DownloadStatus.running ||
                  t.status == DownloadStatus.pending ||
                  t.status == DownloadStatus.paused ||
                  t.status == DownloadStatus.failed)
              .toList();

          final totalBytes = completed.fold<int>(
            0,
            (int sum, DownloadTask t) =>
                sum + (t.bytesReceived > 0 ? t.bytesReceived : t.totalBytes),
          );

          return Column(
            children: <Widget>[
              Expanded(
                child: TabBarView(
                  controller: _tabs,
                  children: <Widget>[
                    _DownloadList(
                      items: completed,
                      empty: const _EmptyTab(
                        icon: Icons.download_done_outlined,
                        title: 'Henuz indirme yok',
                        hint:
                            'Bir filme veya boluma git, "Indir" tusuna bas — '
                            'tamamlandiginda burada listelenir.',
                      ),
                    ),
                    _DownloadList(
                      items: active,
                      empty: const _EmptyTab(
                        icon: Icons.cloud_download_outlined,
                        title: 'Aktif indirme yok',
                        hint:
                            'Indirme baslattiginda durumu burada gosterilir.',
                      ),
                    ),
                  ],
                ),
              ),
              _StorageFooter(totalBytes: totalBytes, count: completed.length),
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmDeleteAll() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Tumunu sil'),
        content: const Text(
          'Tamamlanan ve iptal edilen indirmeler silinecek. Aktif '
          'indirmeler etkilenmez.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(downloadsServiceProvider).deleteAllFinished();
  }
}

class _DownloadList extends ConsumerWidget {
  const _DownloadList({required this.items, required this.empty});

  final List<DownloadTask> items;
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return empty;
    return ListView.separated(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: DesignTokens.spaceS),
      itemBuilder: (BuildContext _, int i) =>
          _DownloadTile(task: items[i]),
    );
  }
}

class _DownloadTile extends ConsumerStatefulWidget {
  const _DownloadTile({required this.task});

  final DownloadTask task;

  @override
  ConsumerState<_DownloadTile> createState() => _DownloadTileState();
}

class _DownloadTileState extends ConsumerState<_DownloadTile> {
  DateTime _lastSampleAt = DateTime.now();
  int _lastSampleBytes = 0;
  double _speedBytesPerSec = 0;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final scheme = Theme.of(context).colorScheme;
    final completed = t.status == DownloadStatus.completed;
    final running = t.status == DownloadStatus.running;
    final paused = t.status == DownloadStatus.paused;
    final failed = t.status == DownloadStatus.failed;

    if (running) _sampleSpeed(t);

    final subtitleParts = <String>[
      _statusLabel(t.status),
      if (t.totalBytes > 0)
        '${_formatBytes(t.bytesReceived)} / ${_formatBytes(t.totalBytes)}'
      else if (t.bytesReceived > 0)
        _formatBytes(t.bytesReceived),
      if (running && _speedBytesPerSec > 0)
        '${_formatBytes(_speedBytesPerSec.round())}/s',
      if (running && t.totalBytes > 0 && _speedBytesPerSec > 0)
        _formatEta(t),
    ];

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        onTap: completed ? () => _playLocal(context) : null,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceM),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _Poster(url: t.posterUrl),
                  const SizedBox(width: DesignTokens.spaceM),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          t.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitleParts.join(' • '),
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                        if (failed && t.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(
                              t.error!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: scheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: DesignTokens.spaceS),
                  _ActionButtons(task: t),
                ],
              ),
              if (running || paused || t.status == DownloadStatus.pending)
                Padding(
                  padding: const EdgeInsets.only(top: DesignTokens.spaceS),
                  child: LinearProgressIndicator(
                    minHeight: 4,
                    value: t.totalBytes > 0
                        ? t.progress
                        : (running ? null : 0),
                  ),
                ),
              if (completed)
                Padding(
                  padding: const EdgeInsets.only(top: DesignTokens.spaceS),
                  child: Row(
                    children: <Widget>[
                      const Icon(
                        Icons.offline_pin_outlined,
                        size: 14,
                        color: Colors.green,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Cevrimdisi izle',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: scheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _sampleSpeed(DownloadTask t) {
    final now = DateTime.now();
    final dt = now.difference(_lastSampleAt).inMilliseconds;
    if (dt < 500) return;
    final db = t.bytesReceived - _lastSampleBytes;
    if (_lastSampleBytes == 0) {
      _lastSampleBytes = t.bytesReceived;
      _lastSampleAt = now;
      return;
    }
    if (dt > 0) {
      _speedBytesPerSec = db * 1000 / dt;
    }
    _lastSampleBytes = t.bytesReceived;
    _lastSampleAt = now;
  }

  String _formatEta(DownloadTask t) {
    final remaining = t.totalBytes - t.bytesReceived;
    if (remaining <= 0 || _speedBytesPerSec <= 0) return '';
    final seconds = (remaining / _speedBytesPerSec).round();
    if (seconds < 60) return '${seconds}sn';
    if (seconds < 3600) {
      return '${(seconds / 60).round()}dk';
    }
    return '${(seconds / 3600).toStringAsFixed(1)}sa';
  }

  Future<void> _playLocal(BuildContext context) async {
    final t = widget.task;
    if (t.localPath == null) return;
    final src = MediaSource(
      url: 'file://${t.localPath}',
      title: t.title,
    );
    final args = PlayerLaunchArgs(
      source: src,
      title: t.title,
      subtitle: 'Indirildi',
      itemId: t.itemId,
      kind: HistoryKind.vod,
    );
    context.push('/play', extra: args);
  }
}

class _ActionButtons extends ConsumerWidget {
  const _ActionButtons({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(downloadsServiceProvider);
    switch (task.status) {
      case DownloadStatus.running:
      case DownloadStatus.pending:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Duraklat',
              icon: const Icon(Icons.pause_rounded),
              onPressed: () => svc.pause(task.id),
            ),
            IconButton(
              tooltip: 'Iptal',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => svc.cancel(task.id),
            ),
          ],
        );
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Devam et',
              icon: const Icon(Icons.play_arrow_rounded),
              onPressed: () => svc.resume(task.id),
            ),
            IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => svc.delete(task.id),
            ),
          ],
        );
      case DownloadStatus.completed:
      case DownloadStatus.cancelled:
        return IconButton(
          tooltip: 'Sil',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: () => svc.delete(task.id),
        );
    }
  }
}

class _Poster extends StatelessWidget {
  const _Poster({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ph = Container(
      width: 56,
      height: 80,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      ),
      child: Icon(
        Icons.movie_outlined,
        color: scheme.onSurface.withValues(alpha: 0.5),
      ),
    );
    if (url == null || url!.isEmpty) return ph;
    return ClipRRect(
      borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      child: CachedNetworkImage(
        imageUrl: url!,
        width: 56,
        height: 80,
        fit: BoxFit.cover,
        placeholder: (_, __) => ph,
        errorWidget: (_, __, ___) => ph,
      ),
    );
  }
}

class _StorageFooter extends StatelessWidget {
  const _StorageFooter({required this.totalBytes, required this.count});

  final int totalBytes;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceL,
        vertical: DesignTokens.spaceM,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: scheme.outline.withValues(alpha: 0.18)),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: <Widget>[
            Icon(
              Icons.sd_storage_outlined,
              size: 18,
              color: scheme.onSurface.withValues(alpha: 0.65),
            ),
            const SizedBox(width: DesignTokens.spaceS),
            Text(
              '$count dosya • ${_formatBytes(totalBytes)}',
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UnsupportedPlatform extends StatelessWidget {
  const _UnsupportedPlatform();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.desktop_mac_outlined,
      title: 'Sadece masaustu/mobil uygulamada',
      message:
          'Cevrimdisi indirme, isletim sistemi dosya sistemine eristigimiz '
          'masaustu (macOS / Windows / Linux) ve mobil (iOS / Android) '
          'uygulamalarinda calisir. Web istemcisinde bu sayfa yer tutar '
          'olarak gosterilir.',
    );
  }
}

class _EmptyTab extends StatelessWidget {
  const _EmptyTab({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return EmptyState(icon: icon, title: title, message: hint);
  }
}

String _statusLabel(DownloadStatus s) => switch (s) {
      DownloadStatus.pending => 'beklemede',
      DownloadStatus.running => 'indiriliyor',
      DownloadStatus.paused => 'duraklatildi',
      DownloadStatus.completed => 'tamamlandi',
      DownloadStatus.failed => 'hata',
      DownloadStatus.cancelled => 'iptal',
    };

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
