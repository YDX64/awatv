import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/features/smart_alerts/keyword_alert.dart';
import 'package:awatv_mobile/src/features/smart_alerts/smart_alerts_provider.dart';
import 'package:awatv_mobile/src/features/smart_alerts/smart_alerts_service.dart';
import 'package:awatv_mobile/src/shared/notifications/notifications_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/premium/premium_status_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_tier.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

/// `/alerts` — list + manage keyword-driven EPG alerts.
///
/// Each row exposes:
///   * keyword + channel scope summary
///   * active toggle (pause without losing the keyword)
///   * delete button
///
/// FAB → "Yeni uyari" sheet that creates a [KeywordAlert]. Free tier is
/// capped at [SmartAlertsService.freeMax]; the FAB pushes the paywall
/// once the cap is hit.
class SmartAlertsScreen extends ConsumerWidget {
  const SmartAlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncList = ref.watch(smartAlertsListProvider);
    final tier = ref.watch(premiumStatusProvider);
    final premium = tier.isPremium;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Akilli uyarilar'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Yeniden tara',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => _runScan(context, ref, premium: premium),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _onAddPressed(context, ref, premium: premium),
        icon: const Icon(Icons.add_alert_rounded),
        label: const Text('Yeni uyari'),
      ),
      body: asyncList.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object err, StackTrace _) => ErrorView(message: err.toString()),
        data: (List<KeywordAlert> list) {
          if (list.isEmpty) {
            return EmptyState(
              icon: Icons.notifications_active_outlined,
              title: 'Akilli uyari yok',
              message: 'Favori kanallarinda Besiktas, Game of Thrones gibi '
                  'anahtar kelimelerini yakaladigimizda 5 dakika once '
                  'haberdar edelim.',
              actionLabel: 'Yeni uyari',
              onAction: () => _onAddPressed(context, ref, premium: premium),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceM,
              DesignTokens.spaceM,
              DesignTokens.spaceM,
              96,
            ),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) =>
                const SizedBox(height: DesignTokens.spaceS),
            itemBuilder: (BuildContext _, int i) {
              if (i == 0) return _AlertsHeaderCard(premium: premium, count: list.length);
              return _AlertTile(alert: list[i - 1]);
            },
          );
        },
      ),
    );
  }

  Future<void> _onAddPressed(
    BuildContext context,
    WidgetRef ref, {
    required bool premium,
  }) async {
    final list = await ref.read(smartAlertsServiceProvider).list();
    final activeCount = list.where((KeywordAlert a) => a.active).length;
    if (!premium && activeCount >= SmartAlertsService.freeMax) {
      if (!context.mounted) return;
      PremiumLockSheet.show(context, PremiumFeature.cloudSync);
      return;
    }
    if (!context.mounted) return;
    final created = await NewAlertSheet.show(context, ref);
    if (created == null) return;
    final notif = ref.read(awatvNotificationsProvider);
    final granted = await notif.ensurePermission();
    if (!granted) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bildirim izni reddedildi — Ayarlar > Bildirimler menusunden ac.',
          ),
        ),
      );
    }
    await ref.read(smartAlertsServiceProvider).add(created);
    if (!context.mounted) return;
    await _runScan(context, ref, premium: premium);
  }

  Future<void> _runScan(
    BuildContext context,
    WidgetRef ref, {
    required bool premium,
  }) async {
    try {
      final scheduled = await ref
          .read(smartAlertsServiceProvider)
          .scanAndSchedule(premium: premium);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 2),
          content: Text(
            scheduled == 0
                ? '24 saatlik EPG taramasi tamam — eslesme bulunamadi.'
                : '$scheduled hatirlatma planlandi.',
          ),
        ),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Tarama basarisiz: $e')),
      );
    }
  }
}

class _AlertsHeaderCard extends StatelessWidget {
  const _AlertsHeaderCard({required this.premium, required this.count});

  final bool premium;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final cap = premium ? '∞' : '${SmartAlertsService.freeMax}';
    return Container(
      padding: const EdgeInsets.all(DesignTokens.spaceM),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            scheme.primary.withValues(alpha: 0.18),
            scheme.tertiary.withValues(alpha: 0.10),
          ],
        ),
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.30),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            ),
            child: Icon(Icons.bolt_rounded, color: scheme.primary),
          ),
          const SizedBox(width: DesignTokens.spaceM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '$count uyari • $cap kontenjan',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  premium
                      ? 'Premium aboneliginle sinirsiz uyari ekleyebilirsin.'
                      : 'Ucretsiz uyelikte ${SmartAlertsService.freeMax} aktif uyari hakki var.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertTile extends ConsumerWidget {
  const _AlertTile({required this.alert});

  final KeywordAlert alert;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final scope = (alert.channelTvgIds == null || alert.channelTvgIds!.isEmpty)
        ? 'Tum favori kanallar'
        : '${alert.channelTvgIds!.length} kanal sec';
    final created = alert.createdAt;
    final createdLabel = created == null
        ? null
        : 'Eklendi ${DateFormat('d MMM', 'tr_TR').format(created.toLocal())}';
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(DesignTokens.radiusL),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Row(
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: alert.active
                    ? scheme.primary.withValues(alpha: 0.18)
                    : scheme.surface,
                borderRadius: BorderRadius.circular(DesignTokens.radiusM),
              ),
              child: Icon(
                Icons.search_rounded,
                color: alert.active
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(width: DesignTokens.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    '"${alert.keyword}"',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    scope,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (createdLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        createdLabel,
                        style: TextStyle(
                          fontSize: 11,
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: DesignTokens.spaceS),
            Switch(
              value: alert.active,
              onChanged: (bool v) async {
                await ref
                    .read(smartAlertsServiceProvider)
                    .setActive(alert.id, value: v);
              },
            ),
            IconButton(
              tooltip: 'Sil',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                await ref
                    .read(smartAlertsServiceProvider)
                    .remove(alert.id);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    duration: Duration(seconds: 2),
                    content: Text('Uyari silindi.'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom-sheet form for creating a [KeywordAlert]. Returns the
/// constructed alert (without persisting — caller persists so it can
/// also kick off a rescan in the same gesture).
class NewAlertSheet extends ConsumerStatefulWidget {
  const NewAlertSheet({super.key});

  static Future<KeywordAlert?> show(BuildContext context, WidgetRef _) {
    return showModalBottomSheet<KeywordAlert?>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext _) => const NewAlertSheet(),
    );
  }

  @override
  ConsumerState<NewAlertSheet> createState() => _NewAlertSheetState();
}

class _NewAlertSheetState extends ConsumerState<NewAlertSheet> {
  final TextEditingController _keywordCtrl = TextEditingController();
  final Set<String> _selectedTvgIds = <String>{};
  bool _restrictChannels = false;

  @override
  void dispose() {
    _keywordCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final liveAsync = ref.watch(liveChannelsProvider);
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXL),
        ),
        child: ColoredBox(
          color: scheme.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.spaceL,
              DesignTokens.spaceM,
              DesignTokens.spaceL,
              DesignTokens.spaceL,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                Text(
                  'Yeni akilli uyari',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  'Bir anahtar kelime gir; Besiktas, Game of Thrones, '
                  'F1, Avrupa Ligi gibi.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                TextField(
                  controller: _keywordCtrl,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Anahtar kelime',
                    hintText: 'Ornek: Game of Thrones',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                SwitchListTile(
                  value: _restrictChannels,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (bool v) =>
                      setState(() => _restrictChannels = v),
                  title: const Text('Belirli kanallarla sinirla'),
                  subtitle: const Text(
                    'Kapali oldugunda tum favorilerin taranir.',
                  ),
                ),
                if (_restrictChannels)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: liveAsync.when(
                      loading: () => const Center(
                        child: CircularProgressIndicator(),
                      ),
                      error: (Object e, StackTrace _) =>
                          Text('Kanallar yuklenemedi: $e'),
                      data: (List<Channel> channels) {
                        final withTvg = channels
                            .where((Channel c) =>
                                c.tvgId != null && c.tvgId!.trim().isNotEmpty)
                            .toList();
                        if (withTvg.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(DesignTokens.spaceM),
                            child: Text('TVG kimligi olan kanal bulunamadi.'),
                          );
                        }
                        return Scrollbar(
                          child: ListView.builder(
                            itemCount: withTvg.length,
                            itemBuilder: (BuildContext _, int i) {
                              final c = withTvg[i];
                              final tvg = c.tvgId!;
                              final selected = _selectedTvgIds.contains(tvg);
                              return CheckboxListTile(
                                dense: true,
                                value: selected,
                                onChanged: (bool? v) {
                                  setState(() {
                                    if (v ?? false) {
                                      _selectedTvgIds.add(tvg);
                                    } else {
                                      _selectedTvgIds.remove(tvg);
                                    }
                                  });
                                },
                                title: Text(c.name),
                                subtitle: Text(tvg),
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: DesignTokens.spaceM),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Vazgec'),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spaceS),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _onSubmit,
                        icon: const Icon(Icons.add_alert_rounded),
                        label: const Text('Olustur'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onSubmit() {
    final keyword = _keywordCtrl.text.trim();
    if (keyword.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Anahtar kelime bos olamaz.'),
        ),
      );
      return;
    }
    final ids = _restrictChannels && _selectedTvgIds.isNotEmpty
        ? _selectedTvgIds.toList()
        : null;
    final alert = KeywordAlert.create(
      keyword: keyword,
      channelTvgIds: ids,
    );
    Navigator.of(context).pop(alert);
  }
}
