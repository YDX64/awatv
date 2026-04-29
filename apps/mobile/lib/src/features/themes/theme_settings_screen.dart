import 'dart:async';

import 'package:awatv_mobile/src/app/theme_mode_provider.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/features/themes/app_custom_theme.dart';
import 'package:awatv_mobile/src/features/themes/custom_theme_controller.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Premium theme customisation screen.
///
/// Layout (top → bottom):
///   1. Live mini preview card — picks up the current draft so users
///      see the result immediately without committing.
///   2. Accent colour preset chips (9 swatches incl. brand).
///   3. Variant chooser — Standart / Canli / Yumusak / OLED siyah.
///   4. Corner-radius slider (0.5x .. 2x).
///   5. "Test et" floating button — applies the draft for 5 seconds.
///   6. "Kaydet" + "Sifirla" actions in a sticky bottom bar.
///
/// Free users hit the [PremiumLockSheet] before reaching this screen
/// (the settings tile gates the link). The screen still defends itself
/// at boot with a soft check so a stray deep-link can't bypass the
/// lock; it surfaces a paywall sheet and falls back to the persisted
/// theme without committing any changes.
class ThemeSettingsScreen extends ConsumerStatefulWidget {
  const ThemeSettingsScreen({super.key});

  @override
  ConsumerState<ThemeSettingsScreen> createState() =>
      _ThemeSettingsScreenState();
}

class _ThemeSettingsScreenState extends ConsumerState<ThemeSettingsScreen> {
  /// Working copy. Edits here flow into `ref.read(...).preview()` so the
  /// MaterialApp rebuilds with the candidate; only `save` persists.
  late AppCustomTheme _draft;

  /// Outstanding "Test et" timer — cancelled if the user changes their
  /// mind or saves before it fires.
  Timer? _previewTimer;

  /// Initial value captured on first build; used to compute "dirty"
  /// state so we can dim the Save button when nothing changed.
  late AppCustomTheme _initial;

  bool _gateChecked = false;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(customThemeControllerProvider.notifier);
    _initial = controller.persisted;
    _draft = _initial;
  }

  @override
  void dispose() {
    _previewTimer?.cancel();
    // Always release any active preview so leaving via the back button
    // never strands the app on a half-applied theme.
    ref.read(customThemeControllerProvider.notifier).endPreview();
    super.dispose();
  }

  void _ensurePremium() {
    if (_gateChecked) return;
    _gateChecked = true;
    final canTheme =
        ref.read(canUseFeatureProvider(PremiumFeature.customThemes));
    if (canTheme) return;
    // Schedule for after first frame so the sheet has a Navigator
    // ready. The screen still renders the picker behind the modal so
    // the user can preview-only without subscribing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      PremiumLockSheet.show(context, PremiumFeature.customThemes);
    });
  }

  void _setDraft(AppCustomTheme next) {
    setState(() => _draft = next);
    ref.read(customThemeControllerProvider.notifier).preview(next);
    // Editing while a preview countdown is still running cancels it —
    // any further edit replaces the snapshot anyway.
    _previewTimer?.cancel();
    _previewTimer = null;
  }

  Future<void> _save() async {
    _previewTimer?.cancel();
    _previewTimer = null;
    final canTheme =
        ref.read(canUseFeatureProvider(PremiumFeature.customThemes));
    if (!canTheme) {
      await PremiumLockSheet.show(context, PremiumFeature.customThemes);
      return;
    }
    await ref.read(customThemeControllerProvider.notifier).save(_draft);
    if (!mounted) return;
    setState(() => _initial = _draft);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tema kaydedildi')),
    );
  }

  Future<void> _reset() async {
    _previewTimer?.cancel();
    _previewTimer = null;
    await ref.read(customThemeControllerProvider.notifier).reset();
    if (!mounted) return;
    setState(() {
      _draft = AppCustomTheme.defaults;
      _initial = AppCustomTheme.defaults;
    });
  }

  void _runPreviewWindow() {
    _previewTimer?.cancel();
    ref.read(customThemeControllerProvider.notifier).preview(_draft);
    _previewTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted) return;
      ref.read(customThemeControllerProvider.notifier).endPreview();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onizleme bitti — kaydetmek icin "Kaydet" tikla'),
          duration: Duration(seconds: 3),
        ),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('5 saniyelik onizleme aktif'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _ensurePremium();
    final theme = Theme.of(context);
    final dirty = _draft != _initial;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ozel temalar'),
        actions: <Widget>[
          if (_initial != AppCustomTheme.defaults)
            TextButton(
              onPressed: _reset,
              child: const Text('Sifirla'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(
          vertical: DesignTokens.spaceM,
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
            ),
            child: _ThemePreviewCard(draft: _draft),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          const _SectionHeader(title: 'Vurgu rengi'),
          _AccentPicker(
            selected: _draft.seedColor,
            onPick: (Color c) =>
                _setDraft(_draft.copyWith(seedColor: c)),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          const _SectionHeader(title: 'Stil'),
          _VariantPicker(
            selected: _draft.variant,
            onPick: (ThemeVariant v) =>
                _setDraft(_draft.copyWith(variant: v)),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          const _SectionHeader(title: 'Kose yuvarlakligi'),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Slider(
                  min: 0.5,
                  max: 2,
                  divisions: 15,
                  value: _draft.cornerRadiusScale,
                  label: '${_draft.cornerRadiusScale.toStringAsFixed(2)}x',
                  onChanged: (double v) =>
                      _setDraft(_draft.copyWith(cornerRadiusScale: v)),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: DesignTokens.spaceM,
                  ),
                  child: Row(
                    children: <Widget>[
                      Text(
                        'Sert',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_draft.cornerRadiusScale.toStringAsFixed(2)}x',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Yumusak',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: DesignTokens.spaceL),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
            ),
            child: OutlinedButton.icon(
              onPressed: _runPreviewWindow,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Test et (5 sn)'),
            ),
          ),
          const SizedBox(height: 96),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.spaceM,
            DesignTokens.spaceS,
            DesignTokens.spaceM,
            DesignTokens.spaceM,
          ),
          child: SizedBox(
            height: DesignTokens.minTapTarget + 4,
            child: FilledButton.icon(
              onPressed: dirty ? _save : null,
              icon: const Icon(Icons.save_rounded),
              label: Text(dirty ? 'Kaydet' : 'Degisiklik yok'),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title});
  final String title;

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
        title.toUpperCase(),
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

/// Live preview surface — renders representative chips, buttons, a
/// scaffold-like row and a card so the user can read the impact of
/// every adjustment without opening another screen.
class _ThemePreviewCard extends ConsumerWidget {
  const _ThemePreviewCard({required this.draft});

  final AppCustomTheme draft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final mode = ref.watch(appThemeModeProvider);
    final isDark = mode == ThemeMode.dark ||
        (mode == ThemeMode.system &&
            MediaQuery.platformBrightnessOf(context) == Brightness.dark);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: draft.seedColor,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: scheme.onSurface.withValues(alpha: 0.16),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'AWAtv',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        '${draft.variant.tr} • ${isDark ? "Koyu" : "Acik"}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(Icons.live_tv_rounded, color: scheme.primary),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Wrap(
              spacing: DesignTokens.spaceS,
              runSpacing: DesignTokens.spaceXs,
              children: <Widget>[
                FilledButton(onPressed: () {}, child: const Text('Birincil')),
                OutlinedButton(
                  onPressed: () {},
                  child: const Text('Ikincil'),
                ),
                Chip(
                  avatar: Icon(
                    Icons.bolt_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
                  label: const Text('Cip'),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            ClipRRect(
              borderRadius: BorderRadius.circular(
                DesignTokens.radiusM * draft.cornerRadiusScale,
              ),
              child: Container(
                height: 8,
                color: scheme.primary.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Horizontally-scrollable strip of accent presets. The selected
/// swatch gets a checkmark overlay so it's instantly visible without
/// requiring a colour comparison against the live preview.
class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.selected, required this.onPick});

  final Color selected;
  final ValueChanged<Color> onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
        ),
        itemCount: ThemeAccentPresets.values.length,
        separatorBuilder: (_, __) =>
            const SizedBox(width: DesignTokens.spaceM),
        itemBuilder: (BuildContext _, int i) {
          final p = ThemeAccentPresets.values[i];
          // Compare via the toARGB32 helper rather than the deprecated
          // Color.value accessor — same numeric identity, future-proofed
          // against the upstream getter being removed.
          final isSelected = _argb(p.color) == _argb(selected);
          return _AccentSwatch(
            preset: p,
            selected: isSelected,
            onTap: () => onPick(p.color),
          );
        },
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ThemeAccentPreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      selected: selected,
      label: '${preset.label} vurgu rengi',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            AnimatedContainer(
              duration: DesignTokens.motionFast,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: preset.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.outline.withValues(alpha: 0.4),
                  width: selected ? 3 : 1,
                ),
                boxShadow: selected
                    ? <BoxShadow>[
                        BoxShadow(
                          color: preset.color.withValues(alpha: 0.55),
                          blurRadius: 12,
                        ),
                      ]
                    : const <BoxShadow>[],
              ),
              child: selected
                  ? const Icon(Icons.check_rounded, color: Colors.white)
                  : null,
            ),
            const SizedBox(height: 6),
            Text(
              preset.label,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Variant picker rendered as a vertical list of cards so each option
/// has room for a subtitle that explains the trade-off.
class _VariantPicker extends StatelessWidget {
  const _VariantPicker({required this.selected, required this.onPick});

  final ThemeVariant selected;
  final ValueChanged<ThemeVariant> onPick;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Column(
        children: <Widget>[
          for (final v in ThemeVariant.values)
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.spaceS),
              child: InkWell(
                borderRadius: BorderRadius.circular(DesignTokens.radiusL),
                onTap: () => onPick(v),
                child: Ink(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusL),
                    border: Border.all(
                      color: v == selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.outline
                              .withValues(alpha: 0.35),
                      width: v == selected ? 2 : 1,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(DesignTokens.spaceM),
                    child: Row(
                      children: <Widget>[
                        Icon(
                          v == selected
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_unchecked_rounded,
                          color: v == selected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface
                                  .withValues(alpha: 0.55),
                        ),
                        const SizedBox(width: DesignTokens.spaceM),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                v.tr,
                                style: theme.textTheme.titleMedium,
                              ),
                              Text(
                                v.description,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurface
                                      .withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Pack a [Color] into a 32-bit ARGB int for stable equality across
/// builds. Replaces the deprecated `Color.value` accessor with a
/// composition over the per-channel `r/g/b` doubles.
int _argb(Color c) {
  final r = (c.r * 255).round() & 0xFF;
  final g = (c.g * 255).round() & 0xFF;
  final b = (c.b * 255).round() & 0xFF;
  return 0xFF000000 | (r << 16) | (g << 8) | b;
}
