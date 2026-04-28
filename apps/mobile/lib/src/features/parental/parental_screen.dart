import 'package:awatv_mobile/src/features/profiles/widgets/pin_entry_sheet.dart';
import 'package:awatv_mobile/src/shared/parental/parental_controller.dart';
import 'package:awatv_mobile/src/shared/parental/parental_settings.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// `/settings/parental` — central parental-control management.
///
/// Premium-gated: callers can still navigate here, but the toggles are
/// disabled and a "Premium\'e geç" banner sits at the top when the user
/// lacks the feature. Keeps the surface discoverable without over-
/// stating what free users get.
class ParentalScreen extends ConsumerWidget {
  const ParentalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSettings = ref.watch(parentalSettingsProvider);
    final canUse =
        ref.watch(canUseFeatureProvider(PremiumFeature.parentalControls));

    return Scaffold(
      appBar: AppBar(title: const Text('Aile koruma')),
      body: asyncSettings.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object e, StackTrace _) =>
            Center(child: Text('Hata: $e')),
        data: (ParentalSettings settings) =>
            _Body(settings: settings, canUse: canUse),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.settings, required this.canUse});

  final ParentalSettings settings;
  final bool canUse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.watch(parentalControllerProvider);
    final theme = Theme.of(context);
    final disabled = !canUse;

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: DesignTokens.spaceM),
      children: <Widget>[
        if (!canUse)
          Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: Container(
              padding: const EdgeInsets.all(DesignTokens.spaceM),
              decoration: BoxDecoration(
                color: theme.colorScheme.tertiary.withValues(alpha: 0.12),
                borderRadius:
                    BorderRadius.circular(DesignTokens.radiusM),
                border: Border.all(
                  color: theme.colorScheme.tertiary.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(Icons.workspace_premium_rounded,
                      color: theme.colorScheme.tertiary),
                  const SizedBox(width: DesignTokens.spaceM),
                  const Expanded(
                    child: Text(
                      'Aile koruma Premium\'a özel. '
                      'Premium\'a geçerek tüm aile araçlarını '
                      'kullanabilirsin.',
                    ),
                  ),
                ],
              ),
            ),
          ),
        SwitchListTile(
          secondary: const Icon(Icons.shield_rounded),
          title: const Text('Ebeveyn kontrolünü etkinleştir'),
          subtitle: Text(
            settings.hasPin
                ? 'PIN ayarlandı'
                : 'Etkinleştirmek için bir PIN belirleyin',
          ),
          value: settings.enabled,
          onChanged: disabled
              ? null
              : (bool v) async {
                  if (v && !settings.hasPin) {
                    await _requireFreshPin(context, controller);
                  } else {
                    await controller.update(enabled: v);
                    if (!v) await controller.lockSession();
                  }
                },
        ),
        ListTile(
          enabled: !disabled,
          leading: const Icon(Icons.password_rounded),
          title: Text(settings.hasPin
              ? 'PIN\'i değiştir'
              : 'PIN ayarla'),
          subtitle: const Text('4-6 haneli sayısal PIN'),
          onTap: disabled
              ? null
              : () => _setOrChangePin(context, controller, settings),
        ),
        const Divider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceL,
            DesignTokens.spaceM,
            DesignTokens.spaceL,
            DesignTokens.spaceXs,
          ),
          child: Text(
            'KISITLAMALAR',
            style: theme.textTheme.labelSmall?.copyWith(
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        ListTile(
          enabled: !disabled,
          leading: const Icon(Icons.cake_outlined),
          title: const Text('Maksimum yaş sınırlaması'),
          subtitle: Text(ParentalRating.label(settings.maxRating)),
          onTap: disabled
              ? null
              : () => _pickRating(context, controller, settings),
        ),
        ListTile(
          enabled: !disabled,
          leading: const Icon(Icons.block_rounded),
          title: const Text('Engellenen kategoriler'),
          subtitle: Text(
            settings.blockedCategories.isEmpty
                ? 'Henüz kategori eklenmedi'
                : settings.blockedCategories.join(', '),
          ),
          onTap: disabled
              ? null
              : () => _editCategories(context, controller, settings),
        ),
        ListTile(
          enabled: !disabled,
          leading: const Icon(Icons.timer_outlined),
          title: const Text('Günlük izleme süresi'),
          subtitle: Text(
            settings.dailyWatchLimit == Duration.zero
                ? 'Sınırsız'
                : '${settings.dailyWatchLimit.inHours} sa '
                    '${settings.dailyWatchLimit.inMinutes.remainder(60)} dk',
          ),
          onTap: disabled
              ? null
              : () => _editDailyLimit(context, controller, settings),
        ),
        ListTile(
          enabled: !disabled,
          leading: const Icon(Icons.bedtime_outlined),
          title: const Text('Yatma saati'),
          subtitle: Text(
            settings.bedtimeOfDay == null
                ? 'Belirlenmedi'
                : 'Çocuk profillerinde ${_fmtTime(settings.bedtimeOfDay!)} sonrası kilit',
          ),
          onTap: disabled
              ? null
              : () => _editBedtime(context, controller, settings),
        ),
        const Divider(),
        ListTile(
          enabled: !disabled,
          leading: const Icon(Icons.lock_clock_rounded),
          title: const Text('Oturumu hemen kilitle'),
          subtitle: const Text(
            'PIN tekrar gerekene kadar bekle',
          ),
          onTap: disabled
              ? null
              : () async {
                  await controller.lockSession();
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Oturum kilitlendi'),
                    ),
                  );
                },
        ),
        if (settings.hasPin)
          ListTile(
            leading: Icon(
              Icons.delete_outline,
              color: theme.colorScheme.error,
            ),
            title: Text(
              'Tüm ayarları sıfırla',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            subtitle: const Text(
              'PIN ve tüm parental ayarları silinir',
            ),
            onTap: disabled
                ? null
                : () => _resetAll(context, controller),
          ),
      ],
    );
  }

  String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _requireFreshPin(
    BuildContext context,
    ParentalController controller,
  ) async {
    final pin = await PinEntrySheet.show(
      context,
      title: 'Yeni PIN belirle',
      subtitle: 'Aile korumayı etkinleştirmek için 4-6 haneli bir PIN seç',
    );
    if (pin == null) return;
    if (!context.mounted) return;
    final confirm = await PinEntrySheet.show(
      context,
      title: 'PIN\'i doğrula',
      subtitle: 'Tekrar gir',
      validator: (String s) => s == pin ? null : 'PIN eşleşmiyor',
    );
    if (confirm == null) return;
    final ok = await controller.setPin(pin: pin);
    if (!context.mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN ayarlanamadı')),
      );
      return;
    }
    await controller.update(enabled: true);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aile koruma etkinleştirildi')),
    );
  }

  Future<void> _setOrChangePin(
    BuildContext context,
    ParentalController controller,
    ParentalSettings settings,
  ) async {
    String? oldPin;
    if (settings.hasPin) {
      oldPin = await PinEntrySheet.show(
        context,
        title: 'Mevcut PIN',
        subtitle: 'Önce eski PIN\'i gir',
        validator: (String s) =>
            controller.verifyPin(s, settings) ? null : 'Yanlış PIN',
      );
      if (oldPin == null) return;
    }
    if (!context.mounted) return;
    final fresh = await PinEntrySheet.show(
      context,
      title: settings.hasPin ? 'Yeni PIN' : 'PIN belirle',
      subtitle: '4-6 haneli sayısal PIN',
    );
    if (fresh == null) return;
    if (!context.mounted) return;
    final confirm = await PinEntrySheet.show(
      context,
      title: 'PIN\'i doğrula',
      subtitle: 'Tekrar gir',
      validator: (String s) => s == fresh ? null : 'PIN eşleşmiyor',
    );
    if (confirm == null) return;
    final ok = await controller.setPin(pin: fresh, oldPin: oldPin);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'PIN güncellendi' : 'PIN değiştirilemedi')),
    );
  }

  Future<void> _pickRating(
    BuildContext context,
    ParentalController controller,
    ParentalSettings settings,
  ) async {
    final picked = await showModalBottomSheet<int>(
      context: context,
      builder: (BuildContext ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Padding(
              padding: EdgeInsets.all(DesignTokens.spaceM),
              child: Text(
                'Maksimum yaş sınırı',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            for (final r in ParentalRating.all)
              RadioListTile<int>(
                value: r,
                groupValue: settings.maxRating,
                title: Text(ParentalRating.label(r)),
                onChanged: (int? v) =>
                    Navigator.of(ctx).pop(v ?? settings.maxRating),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await controller.update(maxRating: picked);
  }

  Future<void> _editCategories(
    BuildContext context,
    ParentalController controller,
    ParentalSettings settings,
  ) async {
    final ctrl = TextEditingController(
      text: settings.blockedCategories.join(', '),
    );
    final updated = await showDialog<List<String>>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Engellenen kategoriler'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Virgülle ayır',
            hintText: 'XXX, Yetişkin, 18+',
            border: OutlineInputBorder(),
          ),
          minLines: 1,
          maxLines: 3,
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              ctrl.text
                  .split(',')
                  .map((String s) => s.trim())
                  .where((String s) => s.isNotEmpty)
                  .toList(),
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (updated == null) return;
    await controller.update(blockedCategories: updated);
  }

  Future<void> _editDailyLimit(
    BuildContext context,
    ParentalController controller,
    ParentalSettings settings,
  ) async {
    final hours = ValueNotifier<int>(settings.dailyWatchLimit.inHours);
    final minutes =
        ValueNotifier<int>(settings.dailyWatchLimit.inMinutes.remainder(60));
    final picked = await showDialog<Duration>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Günlük limit'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ValueListenableBuilder<int>(
                valueListenable: hours,
                builder: (_, int h, __) => Slider(
                  value: h.toDouble(),
                  min: 0,
                  max: 8,
                  divisions: 8,
                  label: '$h sa',
                  onChanged: (double v) => hours.value = v.round(),
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: minutes,
                builder: (_, int m, __) => Slider(
                  value: m.toDouble(),
                  min: 0,
                  max: 55,
                  divisions: 11,
                  label: '$m dk',
                  onChanged: (double v) => minutes.value = (v ~/ 5) * 5,
                ),
              ),
              ValueListenableBuilder<int>(
                valueListenable: hours,
                builder: (_, int h, __) =>
                    ValueListenableBuilder<int>(
                  valueListenable: minutes,
                  builder: (_, int m, __) => Text(
                    h == 0 && m == 0 ? 'Sınırsız' : '$h sa $m dk',
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(
              Duration(
                hours: hours.value,
                minutes: minutes.value,
              ),
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    await controller.update(dailyWatchLimit: picked);
  }

  Future<void> _editBedtime(
    BuildContext context,
    ParentalController controller,
    ParentalSettings settings,
  ) async {
    final initial = settings.bedtimeOfDay ??
        const TimeOfDay(hour: 21, minute: 0);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Çocuk profillerinde kilit saati',
    );
    if (picked == null) return;
    await controller.update(
      bedtimeHour: picked.hour,
      bedtimeMinute: picked.minute,
    );
  }

  Future<void> _resetAll(
    BuildContext context,
    ParentalController controller,
  ) async {
    final pin = await PinEntrySheet.show(
      context,
      title: 'PIN doğrula',
      subtitle: 'Tüm parental ayarları sıfırlamak için PIN gerekli',
    );
    if (pin == null) return;
    final ok = await controller.clearAll(currentPin: pin);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? 'Aile koruma sıfırlandı' : 'PIN doğrulanamadı'),
      ),
    );
  }
}
