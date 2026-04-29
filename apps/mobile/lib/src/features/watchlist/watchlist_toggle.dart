import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Saat-iconlu watchlist togglesi — VOD ve series detay ekranlarinda
/// kalbin yaninda durur. Toggle aksiyonu Hive'a yazar; UI rebuild'i
/// `watchlistIdsProvider` uzerinden olur.
class WatchlistToggleButton extends ConsumerWidget {
  const WatchlistToggleButton({
    required this.itemId,
    required this.kind,
    required this.title,
    this.posterUrl,
    this.year,
    this.compact = false,
    super.key,
  });

  /// VodItem.id veya SeriesItem.id.
  final String itemId;

  /// `vod` ya da `series`. `live` reddedilir.
  final HistoryKind kind;

  /// Snapshot baslik — service entry'siyle birlikte saklaniyor ki, kaynak
  /// kaldirilsa bile watchlist ekraninda ad doru gorunsun.
  final String title;

  /// Snapshot poster URL.
  final String? posterUrl;

  /// Snapshot release year, optional.
  final int? year;

  /// Compact = 36dp ikon, kalp dugmesinin yaninda durmasi icin.
  /// Genis = 44dp dolgun pill, FAB benzeri.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncIds = ref.watch(watchlistIdsProvider);
    final saved = asyncIds.maybeWhen(
      data: (Set<String> ids) => ids.contains(itemId),
      orElse: () => false,
    );
    final scheme = Theme.of(context).colorScheme;
    final accent = saved ? scheme.primary : scheme.onSurface.withValues(alpha: 0.7);

    if (compact) {
      return IconButton(
        tooltip: saved ? "Watchlist'ten cikar" : 'Watch later',
        onPressed: () => _toggle(context, ref, saved),
        icon: AnimatedSwitcher(
          duration: DesignTokens.motionFast,
          transitionBuilder: (Widget child, Animation<double> a) =>
              ScaleTransition(scale: a, child: child),
          child: Icon(
            saved
                ? Icons.watch_later_rounded
                : Icons.watch_later_outlined,
            key: ValueKey<bool>(saved),
            color: accent,
            size: 22,
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: () => _toggle(context, ref, saved),
      icon: Icon(
        saved
            ? Icons.watch_later_rounded
            : Icons.watch_later_outlined,
        color: accent,
      ),
      label: Text(saved ? "Watchlist'te" : 'Watch later'),
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(
          color: accent.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Future<void> _toggle(
    BuildContext context,
    WidgetRef ref,
    bool currentlySaved,
  ) async {
    if (kind == HistoryKind.live) return;
    final svc = ref.read(watchlistServiceProvider);
    final entry = WatchlistEntry(
      itemId: itemId,
      kind: kind,
      title: title,
      posterUrl: posterUrl,
      year: year,
      addedAt: DateTime.now().toUtc(),
    );
    final added = await svc.toggle(entry);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          added
              ? "$title watchlist'e eklendi"
              : "$title watchlist'ten cikarildi",
        ),
        action: SnackBarAction(
          label: added ? 'Geri al' : 'Tekrar ekle',
          onPressed: () => svc.toggle(entry),
        ),
      ),
    );
  }
}
