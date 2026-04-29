import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/features/stats/watch_stats_models.dart';
import 'package:awatv_mobile/src/features/stats/watch_stats_providers.dart';
import 'package:awatv_mobile/src/features/stats/widgets/stats_bar_chart.dart';
import 'package:awatv_mobile/src/features/stats/widgets/stats_pie_chart.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

/// "Izleme istatistiklerim" screen — Spotify-Wrapped-style summary
/// card stack.
///
/// Layout (top → bottom):
///   1. Hero card with animated total-hours counter + period switcher.
///   2. Pie chart for Live / Filmler / Diziler distribution.
///   3. 7-day bar chart with weekday labels.
///   4. Top 5 channels / movies / series (premium → 5 each, free → 3).
///   5. "Bu hafta ne izledim" weekly digest with a streak / sessions
///      summary line.
///   6. "Paylas" sheet — exports a textual summary the user can post
///      to Twitter / WhatsApp via `share_plus`.
///
/// Premium gating:
///   * Free tier sees the last-7-days totals only and Top 3 in each
///     category. The pie chart still renders so the upsell card has
///     visual context, but the all-time / 30-day rows show the
///     paywall lock instead of a number.
class StatsScreen extends ConsumerStatefulWidget {
  const StatsScreen({super.key});

  @override
  ConsumerState<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends ConsumerState<StatsScreen> {
  /// Currently-selected timeframe for the hero card. The pie / bar
  /// always reflect their inherent windows (all kinds / 7 days), but
  /// the headline number flips between 7d / 30d / all-time.
  _StatsRange _range = _StatsRange.last7;

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(watchStatsSummaryProvider);
    final isPremium =
        ref.watch(canUseFeatureProvider(PremiumFeature.customThemes));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Izleme istatistiklerim'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Yenile',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () =>
                ref.invalidate(watchStatsSummaryProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(watchStatsSummaryProvider);
          await ref.read(watchStatsSummaryProvider.future);
        },
        child: summaryAsync.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (Object err, StackTrace _) => ListView(
            children: <Widget>[
              const SizedBox(height: 80),
              ErrorView(message: '$err'),
            ],
          ),
          data: (WatchStatsSummary s) =>
              _buildBody(context, s, isPremium: isPremium),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    WatchStatsSummary s, {
    required bool isPremium,
  }) {
    final isEmpty = s.totalAllTime.inSeconds == 0;
    if (isEmpty) {
      return ListView(
        children: const <Widget>[
          SizedBox(height: 80),
          EmptyState(
            icon: Icons.timer_outlined,
            title: 'Henuz izleme verisi yok',
            message:
                'Bir kanal ya da film izlemeye basla — istatistik burada birikecek.',
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceM),
      children: <Widget>[
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
          child: _HeroCard(
            summary: s,
            range: _range,
            onRangeChanged: (_StatsRange r) {
              if (r == _StatsRange.allTime && !isPremium) {
                PremiumLockSheet.show(context, PremiumFeature.customThemes);
                return;
              }
              if (r == _StatsRange.last30 && !isPremium) {
                PremiumLockSheet.show(context, PremiumFeature.customThemes);
                return;
              }
              setState(() => _range = r);
            },
            premium: isPremium,
          ),
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _SectionHeader(label: 'Tur dagilimi'),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
          child: Card(
            child: StatsPieChart(byKind: s.byKind),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _SectionHeader(label: 'Son 7 gun aktivitesi'),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
          child: Card(
            child: StatsBarChart(daySeconds: s.last7DaysBuckets),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _SectionHeader(label: 'Bu hafta ne izledim'),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
          child: _WeeklyDigestCard(summary: s),
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _SectionHeader(label: 'En cok izlenen kanallar'),
        _TopList(
          entries: s.topChannels,
          icon: Icons.live_tv_rounded,
          maxEntries: isPremium ? 5 : 3,
          isPremium: isPremium,
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _SectionHeader(label: 'En cok izlenen filmler'),
        _TopList(
          entries: s.topVod,
          icon: Icons.movie_rounded,
          maxEntries: isPremium ? 5 : 3,
          isPremium: isPremium,
        ),
        const SizedBox(height: DesignTokens.spaceL),
        _SectionHeader(label: 'En cok izlenen diziler'),
        _TopList(
          entries: s.topSeries,
          icon: Icons.video_library_rounded,
          maxEntries: isPremium ? 5 : 3,
          isPremium: isPremium,
        ),
        const SizedBox(height: DesignTokens.spaceL),
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
          child: FilledButton.icon(
            onPressed: () => _share(context, s),
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Paylas'),
          ),
        ),
        const SizedBox(height: DesignTokens.spaceXl),
      ],
    );
  }

  /// Compose a Turkish summary line per category and let the OS share
  /// sheet take it from here. share_plus throws on web when the user
  /// dismisses the picker; we catch it so the screen never crashes
  /// after a cancel.
  Future<void> _share(BuildContext context, WatchStatsSummary s) async {
    final live = s.byKind[HistoryKind.live] ?? Duration.zero;
    final vod = s.byKind[HistoryKind.vod] ?? Duration.zero;
    final series = s.byKind[HistoryKind.series] ?? Duration.zero;
    final body = StringBuffer()
      ..writeln('AWAtv izleme istatistiklerim:')
      ..writeln('Toplam: ${_humanHours(s.totalAllTime)}')
      ..writeln('Bu hafta: ${_humanHours(s.totalLast7Days)}')
      ..writeln('Canli: ${_humanHours(live)}')
      ..writeln('Filmler: ${_humanHours(vod)}')
      ..writeln('Diziler: ${_humanHours(series)}')
      ..writeln('Streak: ${s.streakDays} gun')
      ..writeln('https://awa-tv.awastats.com');
    try {
      await Share.share(
        body.toString(),
        subject: 'AWAtv haftalik ozet',
      );
    } on Object {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paylasilamadi.')),
      );
    }
  }
}

enum _StatsRange { last7, last30, allTime }

class _HeroCard extends StatefulWidget {
  const _HeroCard({
    required this.summary,
    required this.range,
    required this.onRangeChanged,
    required this.premium,
  });

  final WatchStatsSummary summary;
  final _StatsRange range;
  final ValueChanged<_StatsRange> onRangeChanged;
  final bool premium;

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  late Animation<double> _anim;
  Duration? _previousDur;

  @override
  void initState() {
    super.initState();
    _retarget(_durationFor(widget.range));
  }

  @override
  void didUpdateWidget(covariant _HeroCard old) {
    super.didUpdateWidget(old);
    final next = _durationFor(widget.range);
    if (next != _durationFor(old.range)) _retarget(next);
  }

  Duration _durationFor(_StatsRange r) {
    return switch (r) {
      _StatsRange.last7 => widget.summary.totalLast7Days,
      _StatsRange.last30 => widget.summary.totalLast30Days,
      _StatsRange.allTime => widget.summary.totalAllTime,
    };
  }

  void _retarget(Duration target) {
    final start = (_previousDur ?? Duration.zero).inSeconds.toDouble();
    final end = target.inSeconds.toDouble();
    _previousDur = target;
    _anim = Tween<double>(begin: start, end: end).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl
      ..reset()
      ..forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          gradient: LinearGradient(
            colors: <Color>[
              scheme.primary.withValues(alpha: 0.30),
              scheme.secondary.withValues(alpha: 0.15),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.timelapse_rounded,
                  color: scheme.primary,
                ),
                const SizedBox(width: DesignTokens.spaceS),
                Text(
                  'Toplam izleme',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            AnimatedBuilder(
              animation: _anim,
              builder: (BuildContext _, __) {
                final secs = _anim.value.toInt();
                return Text(
                  _humanHours(Duration(seconds: secs)),
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                );
              },
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Wrap(
              spacing: DesignTokens.spaceS,
              children: <Widget>[
                for (final r in _StatsRange.values)
                  ChoiceChip(
                    label: Text(_rangeLabel(r)),
                    selected: r == widget.range,
                    avatar: !widget.premium && r != _StatsRange.last7
                        ? const Icon(Icons.lock_outline, size: 16)
                        : null,
                    onSelected: (_) => widget.onRangeChanged(r),
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Row(
              children: <Widget>[
                _StreakBadge(days: widget.summary.streakDays),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: Text(
                    '${widget.summary.totalSessions} farkli icerik izledin',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakBadge extends StatelessWidget {
  const _StreakBadge({required this.days});
  final int days;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceS,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.local_fire_department_rounded, size: 16),
          const SizedBox(width: 4),
          Text(
            '$days gun streak',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: scheme.onTertiaryContainer,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

String _rangeLabel(_StatsRange r) => switch (r) {
      _StatsRange.last7 => 'Son 7 gun',
      _StatsRange.last30 => 'Son 30 gun',
      _StatsRange.allTime => 'Tum zaman',
    };

class _WeeklyDigestCard extends StatelessWidget {
  const _WeeklyDigestCard({required this.summary});

  final WatchStatsSummary summary;

  @override
  Widget build(BuildContext context) {
    final live = summary.byKind[HistoryKind.live] ?? Duration.zero;
    final vod = summary.byKind[HistoryKind.vod] ?? Duration.zero;
    final series = summary.byKind[HistoryKind.series] ?? Duration.zero;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    String highlight;
    if (live >= vod && live >= series) {
      highlight = 'Bu hafta ${summary.topChannels.isNotEmpty ? "en cok ${summary.topChannels.first.label} kanalini izledin" : "Canli TV en buyuk pay aldi"}.';
    } else if (vod >= series) {
      highlight =
          'Filmler haftan boyunca ${_humanHours(vod)} ile ilk sirada.';
    } else {
      highlight = summary.topSeries.isNotEmpty
          ? '${summary.topSeries.first.label} dizisini bitirmeye yakin gibisin.'
          : 'Diziler bu hafta yildizdi.';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.auto_awesome_rounded, color: scheme.primary),
                const SizedBox(width: DesignTokens.spaceS),
                Text(
                  'Haftalik ozet',
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            _DigestLine(label: 'Toplam', value: _humanHours(summary.totalLast7Days)),
            _DigestLine(label: 'Canli', value: _humanHours(live)),
            _DigestLine(label: 'Film', value: _humanHours(vod)),
            _DigestLine(label: 'Dizi', value: _humanHours(series)),
            const Divider(height: DesignTokens.spaceL),
            Text(
              highlight,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _DigestLine extends StatelessWidget {
  const _DigestLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall,
          ),
        ],
      ),
    );
  }
}

class _TopList extends StatelessWidget {
  const _TopList({
    required this.entries,
    required this.icon,
    required this.maxEntries,
    required this.isPremium,
  });

  final List<TopWatchEntry> entries;
  final IconData icon;
  final int maxEntries;
  final bool isPremium;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            child: Row(
              children: <Widget>[
                Icon(icon, color: Theme.of(context).colorScheme.outline),
                const SizedBox(width: DesignTokens.spaceM),
                const Expanded(child: Text('Henuz veri yok.')),
              ],
            ),
          ),
        ),
      );
    }
    final visible = entries.take(maxEntries).toList();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Card(
        child: Column(
          children: <Widget>[
            for (final e in visible) _TopRow(entry: e, fallbackIcon: icon),
            if (!isPremium && entries.length > maxEntries)
              ListTile(
                leading: const Icon(Icons.workspace_premium_rounded),
                title: const Text('Daha fazlasi premium ile'),
                subtitle: Text(
                  'Tum ${entries.length} sonucu, 30 gun ve tum-zaman ozetlerini ac.',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push('/premium'),
              ),
          ],
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.entry, required this.fallbackIcon});

  final TopWatchEntry entry;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = entry.posterUrl;
    return ListTile(
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        child: SizedBox(
          width: 44,
          height: 44,
          child: url == null || url.isEmpty
              ? Container(
                  color: scheme.surfaceContainerHighest,
                  child: Icon(
                    fallbackIcon,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                )
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (BuildContext _, __, ___) => Container(
                    color: scheme.surfaceContainerHighest,
                    child: Icon(
                      fallbackIcon,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                  placeholder: (BuildContext _, __) => Container(
                    color: scheme.surfaceContainerHighest,
                  ),
                ),
        ),
      ),
      title: Text(
        entry.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: entry.subtitle == null ? null : Text(entry.subtitle!),
      trailing: Text(
        _humanHours(entry.watched),
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
      ),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      ),
    );
  }
}

String _humanHours(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  if (hours == 0 && minutes == 0) return '0 dk';
  if (hours == 0) return '$minutes dk';
  if (minutes == 0) return '$hours sa';
  return '$hours sa $minutes dk';
}
