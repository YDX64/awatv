import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/features/recordings/recordings_providers.dart';
import 'package:awatv_mobile/src/routing/app_router.dart';
import 'package:awatv_mobile/src/shared/loading_view.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Live channel recordings hub.
///
/// Three tabs: aktif (running) / tamamlanan (completed) / planli
/// (scheduled). The "Yeni kayit" FAB launches a channel picker +
/// duration sheet.
class RecordingsScreen extends ConsumerStatefulWidget {
  const RecordingsScreen({super.key});

  @override
  ConsumerState<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends ConsumerState<RecordingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Scaffold(
        appBar: AppBar(title: const Text('Kayitlar')),
        body: const _UnsupportedPlatform(),
      );
    }
    final recordingsAsync = ref.watch(recordingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kayitlar'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const <Widget>[
            Tab(text: 'Aktif'),
            Tab(text: 'Tamamlanan'),
            Tab(text: 'Planli'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onNewRecording,
        icon: const Icon(Icons.fiber_manual_record_rounded),
        label: const Text('Yeni kayit'),
      ),
      body: recordingsAsync.when(
        loading: () => const LoadingView(label: 'Kayitlar yukleniyor'),
        error: (Object err, StackTrace _) => ErrorView(
          message: err.toString(),
          onRetry: () => ref.invalidate(recordingsProvider),
        ),
        data: (List<RecordingTask> all) {
          final running = all
              .where((RecordingTask t) => t.status == RecordingStatus.running)
              .toList();
          final scheduled = all
              .where((RecordingTask t) =>
                  t.status == RecordingStatus.scheduled)
              .toList();
          final completed = all
              .where((RecordingTask t) =>
                  t.status == RecordingStatus.completed ||
                  t.status == RecordingStatus.failed ||
                  t.status == RecordingStatus.cancelled)
              .toList();
          return TabBarView(
            controller: _tabs,
            children: <Widget>[
              _RecordingList(
                items: running,
                empty: const _EmptyTab(
                  icon: Icons.fiber_manual_record_outlined,
                  title: 'Aktif kayit yok',
                  hint:
                      'Yeni kayit ile bir kanali secip kayda al; ilerleme '
                      'burada gozukur.',
                ),
              ),
              _RecordingList(
                items: completed,
                empty: const _EmptyTab(
                  icon: Icons.movie_filter_outlined,
                  title: 'Henuz kayit yok',
                  hint: 'Kayit tamamlandiginda burada listelenir.',
                ),
              ),
              _RecordingList(
                items: scheduled,
                empty: const _EmptyTab(
                  icon: Icons.schedule_rounded,
                  title: 'Plan yok',
                  hint:
                      'Bir programi ileri tarihe planla; otomatik olarak '
                      'baslatilir.',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onNewRecording() async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.recording));
    if (!allowed) {
      await PremiumLockSheet.show(context, PremiumFeature.recording);
      return;
    }
    final result = await showModalBottomSheet<_NewRecordingResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext _) => const _NewRecordingSheet(),
    );
    if (result == null) return;
    final svc = ref.read(recordingServiceProvider);
    if (result.scheduleAt != null) {
      await svc.schedule(
        channel: result.channel,
        startAt: result.scheduleAt!,
        duration: result.duration,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.channel.name} planlandi')),
      );
    } else {
      await svc.start(result.channel, duration: result.duration);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${result.channel.name} kaydi basladi')),
      );
    }
  }
}

class _RecordingList extends ConsumerWidget {
  const _RecordingList({required this.items, required this.empty});

  final List<RecordingTask> items;
  final Widget empty;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) return empty;
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        96,
      ),
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const SizedBox(height: DesignTokens.spaceS),
      itemBuilder: (BuildContext _, int i) =>
          _RecordingTile(task: items[i]),
    );
  }
}

class _RecordingTile extends ConsumerWidget {
  const _RecordingTile({required this.task});

  final RecordingTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final running = task.status == RecordingStatus.running;
    final completed = task.status == RecordingStatus.completed;
    final failed = task.status == RecordingStatus.failed;
    final scheduled = task.status == RecordingStatus.scheduled;

    final subtitleParts = <String>[
      _statusLabel(task.status),
      if (task.duration != null) _formatDuration(task.duration!),
      if (task.bytesWritten > 0) _formatBytes(task.bytesWritten),
      if (task.backend == RecordingBackend.unsupported) 'desteklenmeyen platform',
    ];

    return Material(
      color: scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.18)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        onTap: completed && task.outputPath != null
            ? () => _playLocalFile(context)
            : null,
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceM),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _Logo(url: task.posterUrl, running: running),
              const SizedBox(width: DesignTokens.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      task.channelName,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' • '),
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurface.withValues(alpha: 0.65),
                      ),
                    ),
                    if (running)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: DesignTokens.spaceXs,
                        ),
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          value: task.duration != null &&
                                  task.startedAt != null
                              ? _runProgress(task)
                              : null,
                        ),
                      ),
                    if (failed && task.error != null)
                      Padding(
                        padding: const EdgeInsets.only(
                          top: DesignTokens.spaceXs,
                        ),
                        child: Text(
                          task.error!,
                          maxLines: 2,
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
              if (running)
                IconButton(
                  tooltip: 'Durdur',
                  icon: const Icon(Icons.stop_rounded),
                  onPressed: () =>
                      ref.read(recordingServiceProvider).stop(task.id),
                )
              else if (scheduled)
                IconButton(
                  tooltip: 'Plani iptal et',
                  icon: const Icon(Icons.event_busy_rounded),
                  onPressed: () =>
                      ref.read(recordingServiceProvider).delete(task.id),
                )
              else
                IconButton(
                  tooltip: 'Sil',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () =>
                      ref.read(recordingServiceProvider).delete(task.id),
                ),
            ],
          ),
        ),
      ),
    );
  }

  double? _runProgress(RecordingTask t) {
    if (t.duration == null || t.startedAt == null) return null;
    final elapsed = DateTime.now().toUtc().difference(t.startedAt!);
    final total = t.duration!.inMilliseconds;
    if (total <= 0) return null;
    final p = elapsed.inMilliseconds / total;
    if (p < 0) return 0;
    if (p > 1) return 1;
    return p;
  }

  Future<void> _playLocalFile(BuildContext context) async {
    final path = task.outputPath!;
    final src = MediaSource(
      url: 'file://$path',
      title: task.channelName,
    );
    final args = PlayerLaunchArgs(
      source: src,
      title: task.channelName,
      subtitle: 'Kayit',
      itemId: 'recording::${task.id}',
      kind: HistoryKind.vod,
    );
    context.push('/play', extra: args);
  }
}

class _Logo extends StatelessWidget {
  const _Logo({required this.url, required this.running});

  final String? url;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      ),
      alignment: Alignment.center,
      child: url == null || url!.isEmpty
          ? Icon(
              Icons.live_tv_outlined,
              color: scheme.onSurface.withValues(alpha: 0.5),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusS),
              child: CachedNetworkImage(
                imageUrl: url!,
                fit: BoxFit.cover,
                width: 56,
                height: 56,
                errorWidget: (_, __, ___) => Icon(
                  Icons.live_tv_outlined,
                  color: scheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ),
    );
    if (!running) return base;
    return Stack(
      alignment: Alignment.bottomRight,
      children: <Widget>[
        base,
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: scheme.error,
            borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          ),
          child: const Text(
            'REC',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
        ),
      ],
    );
  }
}

class _NewRecordingSheet extends ConsumerStatefulWidget {
  const _NewRecordingSheet();

  @override
  ConsumerState<_NewRecordingSheet> createState() => _NewRecordingSheetState();
}

class _NewRecordingSheetState extends ConsumerState<_NewRecordingSheet> {
  Channel? _channel;
  Duration _duration = const Duration(minutes: 30);
  DateTime? _scheduleAt;

  static const List<int> _durationChoices = <int>[5, 15, 30, 60, 90, 120, 180];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final channelsAsync = ref.watch(liveChannelsProvider);
    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(DesignTokens.radiusXL),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.spaceL,
          DesignTokens.spaceM,
          DesignTokens.spaceL,
          DesignTokens.spaceL,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurface.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.spaceM),
              Text(
                'Yeni kayit',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: DesignTokens.spaceM),
              const Text(
                'Kanal',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: DesignTokens.spaceS),
              channelsAsync.when(
                loading: () => const LinearProgressIndicator(),
                error: (Object e, _) => Text('Kanallar yuklenemedi: $e'),
                data: (List<Channel> all) {
                  return DropdownButtonFormField<Channel>(
                    initialValue: _channel,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Bir kanal sec',
                    ),
                    isExpanded: true,
                    items: <DropdownMenuItem<Channel>>[
                      for (final c in all)
                        DropdownMenuItem<Channel>(
                          value: c,
                          child: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (Channel? c) => setState(() => _channel = c),
                  );
                },
              ),
              const SizedBox(height: DesignTokens.spaceL),
              const Text(
                'Sure (dakika)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: DesignTokens.spaceS),
              Wrap(
                spacing: DesignTokens.spaceS,
                runSpacing: DesignTokens.spaceS,
                children: <Widget>[
                  for (final m in _durationChoices)
                    ChoiceChip(
                      label: Text('$m dk'),
                      selected: _duration.inMinutes == m,
                      onSelected: (_) => setState(
                        () => _duration = Duration(minutes: m),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: DesignTokens.spaceL),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Plan kaydi'),
                subtitle: Text(
                  _scheduleAt == null
                      ? 'Hemen baslar'
                      : _scheduleAt!
                          .toLocal()
                          .toIso8601String()
                          .replaceFirst('T', ' ')
                          .substring(0, 16),
                ),
                value: _scheduleAt != null,
                onChanged: (bool on) async {
                  if (!on) {
                    setState(() => _scheduleAt = null);
                    return;
                  }
                  final picked = await _pickDateTime();
                  if (picked != null) setState(() => _scheduleAt = picked);
                },
              ),
              const SizedBox(height: DesignTokens.spaceL),
              FilledButton.icon(
                onPressed: _channel == null
                    ? null
                    : () => Navigator.of(context).pop(
                          _NewRecordingResult(
                            channel: _channel!,
                            duration: _duration,
                            scheduleAt: _scheduleAt,
                          ),
                        ),
                icon: const Icon(Icons.fiber_manual_record_rounded),
                label: Text(
                  _scheduleAt == null ? 'Kaydi baslat' : 'Plani kaydet',
                ),
              ),
              const SizedBox(height: DesignTokens.spaceXs),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Vazgec'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<DateTime?> _pickDateTime() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 14)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now),
    );
    if (time == null) return null;
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
  }
}

class _NewRecordingResult {
  const _NewRecordingResult({
    required this.channel,
    required this.duration,
    this.scheduleAt,
  });

  final Channel channel;
  final Duration duration;
  final DateTime? scheduleAt;
}

class _UnsupportedPlatform extends StatelessWidget {
  const _UnsupportedPlatform();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.desktop_mac_outlined,
      title: 'Sadece masaustu/mobil uygulamada',
      message:
          'Canli kayit, isletim sistemi dosya sistemine eristigimiz '
          'masaustu (macOS / Windows / Linux) ve mobil (iOS / Android) '
          'uygulamalarinda calisir.',
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

String _statusLabel(RecordingStatus s) => switch (s) {
      RecordingStatus.scheduled => 'planli',
      RecordingStatus.running => 'kayitta',
      RecordingStatus.completed => 'tamamlandi',
      RecordingStatus.failed => 'hata',
      RecordingStatus.cancelled => 'iptal',
    };

String _formatDuration(Duration d) {
  final m = d.inMinutes;
  if (m < 60) return '$m dk';
  final h = m ~/ 60;
  final r = m % 60;
  if (r == 0) return '${h}sa';
  return '${h}sa ${r}dk';
}

String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
