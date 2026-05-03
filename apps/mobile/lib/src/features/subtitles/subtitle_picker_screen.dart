import 'dart:async';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/features/subtitles/subtitle_settings_controller.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Modal-style screen pushed over the player. Lets the user search
/// OpenSubtitles (real client when configured, stub otherwise),
/// pick a language from the 27 supported codes, tweak the visual
/// settings (size / colour / background opacity / position) and
/// disable subtitles altogether.
///
/// Free tier: tapping a result row pushes the paywall.
/// Premium tier: tapping downloads + applies the SRT.
class SubtitlePickerScreen extends ConsumerStatefulWidget {
  const SubtitlePickerScreen({this.title, super.key});

  /// Optional auto-search seed — usually the title of the currently
  /// playing item so the picker opens already pointed at the right
  /// search query.
  final String? title;

  @override
  ConsumerState<SubtitlePickerScreen> createState() =>
      _SubtitlePickerScreenState();
}

class _SubtitlePickerScreenState
    extends ConsumerState<SubtitlePickerScreen> {
  late final TextEditingController _query;
  bool _showLangPicker = false;
  bool _isSearching = false;
  int? _downloadingFileId;
  String? _searchError;
  List<SubtitleResult> _results = const <SubtitleResult>[];
  late final _DraftSettings _draft;
  bool _settingsExpanded = false;

  @override
  void initState() {
    super.initState();
    _query = TextEditingController(text: widget.title ?? '');
    final s = ref.read(subtitleSettingsControllerProvider);
    _draft = _DraftSettings.from(s);
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final q = _query.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _isSearching = true;
      _searchError = null;
      _results = const <SubtitleResult>[];
    });
    try {
      final svc = ref.read(subtitlesServiceProvider);
      List<SubtitleResult> results;
      if (svc.isAvailable) {
        results = await svc.searchByQuery(
          q,
          lang: _draft.preferredLanguage,
        );
      } else {
        // Stub mode: fabricate plausible results so the UI is fully
        // exercisable when the OpenSubtitles API key is missing.
        // Real OpenSubtitles integration ships in Phase 3 — see
        // /Users/max/AWAtv/docs/streas-port/player-spec.md §6.6.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        results = _stubResultsFor(q, _draft.preferredLanguage);
      }
      if (!mounted) return;
      setState(() {
        _results = results;
        _isSearching = false;
        if (results.isEmpty) {
          _searchError = 'Sonuc bulunamadi. Farkli bir aramayi dene.';
        }
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _searchError = 'Arama basarisiz: $e';
      });
    }
  }

  Future<void> _onSelect(SubtitleResult sub) async {
    final allowed =
        ref.read(canUseFeatureProvider(PremiumFeature.autoSubtitles));
    if (!allowed) {
      // Free tier: bounce to the paywall.
      await PremiumLockSheet.show(context, PremiumFeature.autoSubtitles);
      return;
    }
    setState(() => _downloadingFileId = sub.fileId);
    try {
      final svc = ref.read(subtitlesServiceProvider);
      String body;
      if (svc.isAvailable) {
        body = await svc.fetchSrt(sub.fileId, lang: sub.language);
      } else {
        // Stub: pretend to download a simple 3-cue SRT so the overlay
        // has something to render in dev builds.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        body = _stubSrtFor(sub);
      }
      final fileName = sub.release.isEmpty ? 'subtitle.srt' : sub.release;
      final label = '${widget.title ?? "Subtitles"} '
          '[${sub.language.toUpperCase()}]';
      await ref
          .read(subtitleSettingsControllerProvider.notifier)
          .markLoaded(fileName: fileName, label: label);
      // Persist the picker draft if the user tweaked anything in this
      // session — mirrors the "Kaydet ve uygula" semantics so a
      // download implicitly commits the draft state too.
      await ref
          .read(subtitleSettingsControllerProvider.notifier)
          .apply(_draft.toSettings(loadedFileName: fileName, loadedLabel: label));
      if (!mounted) return;
      // Hand the SRT body back to the caller via context.pop's result so
      // the player can hand it to the engine without re-reading the
      // file. The body is small (typically <100 KB) so passing it in
      // memory is fine.
      Navigator.of(context).pop<SubtitlePickResult>(
        SubtitlePickResult(
          srtBody: body,
          label: label,
          fileName: fileName,
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _downloadingFileId = null;
        _searchError = 'Indirme basarisiz: $e';
      });
    }
  }

  Future<void> _disable() async {
    await ref
        .read(subtitleSettingsControllerProvider.notifier)
        .clearLoaded();
    await ref
        .read(subtitleSettingsControllerProvider.notifier)
        .setEnabled(value: false);
    if (!mounted) return;
    Navigator.of(context).pop<SubtitlePickResult>(
      const SubtitlePickResult(disabled: true),
    );
  }

  Future<void> _saveDraft() async {
    await ref
        .read(subtitleSettingsControllerProvider.notifier)
        .apply(_draft.toSettings());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Altyazi ayarlari kaydedildi.'),
        duration: Duration(milliseconds: 1400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(subtitleSettingsControllerProvider);
    final selectedLang = kSubtitleLanguages.firstWhere(
      (SubtitleLanguage l) => l.code == _draft.preferredLanguage,
      orElse: () => kSubtitleLanguages.first,
    );
    final isSubscribed =
        ref.watch(canUseFeatureProvider(PremiumFeature.autoSubtitles));

    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: <Widget>[
            _Header(onClose: () => context.pop()),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.spaceM,
                ),
                children: <Widget>[
                  if (!isSubscribed)
                    _PremiumBanner(
                      onTap: () => context.push('/premium'),
                    ),
                  if (settings.loadedFileName != null) ...<Widget>[
                    const SizedBox(height: DesignTokens.spaceS),
                    _LoadedIndicator(fileName: settings.loadedFileName!),
                  ],
                  const SizedBox(height: DesignTokens.spaceM),
                  _SearchField(
                    controller: _query,
                    onSubmit: _runSearch,
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  _LanguageSelectorRow(
                    selected: selectedLang,
                    expanded: _showLangPicker,
                    onTap: () => setState(
                      () => _showLangPicker = !_showLangPicker,
                    ),
                  ),
                  if (_showLangPicker)
                    _LanguagePicker(
                      currentCode: _draft.preferredLanguage,
                      onPick: (String code) async {
                        setState(() {
                          _draft.preferredLanguage = code;
                          _showLangPicker = false;
                        });
                        await ref
                            .read(subtitleSettingsControllerProvider
                                .notifier)
                            .setPreferredLanguage(code);
                      },
                    ),
                  const SizedBox(height: DesignTokens.spaceS),
                  _DisableRow(onTap: _disable),
                  const SizedBox(height: DesignTokens.spaceS),
                  _SearchButton(
                    isLoading: _isSearching,
                    enabled: _query.text.trim().isNotEmpty,
                    onTap: _runSearch,
                  ),
                  const SizedBox(height: DesignTokens.spaceXs),
                  Center(
                    child: Text(
                      'Powered by opensubtitles.com',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.55),
                            fontSize: 10,
                          ),
                    ),
                  ),
                  if (_searchError != null) ...<Widget>[
                    const SizedBox(height: DesignTokens.spaceM),
                    _ErrorBox(message: _searchError!),
                  ],
                  if (_results.isNotEmpty) ...<Widget>[
                    const SizedBox(height: DesignTokens.spaceL),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceM,
                      ),
                      child: Text(
                        '${_results.length} altyazi bulundu',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                      ),
                    ),
                    const SizedBox(height: DesignTokens.spaceXs),
                    for (final r in _results)
                      _ResultCard(
                        result: r,
                        downloading: _downloadingFileId == r.fileId,
                        locked: !isSubscribed,
                        onTap: () => _onSelect(r),
                      ),
                  ],
                  const SizedBox(height: DesignTokens.spaceXl),
                  _SettingsHeader(
                    expanded: _settingsExpanded,
                    onTap: () => setState(
                      () => _settingsExpanded = !_settingsExpanded,
                    ),
                  ),
                  if (_settingsExpanded) ...<Widget>[
                    _SettingsPanel(
                      draft: _draft,
                      onChanged: () => setState(() {}),
                    ),
                    const SizedBox(height: DesignTokens.spaceM),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceM,
                      ),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Kaydet ve uygula'),
                          onPressed: _saveDraft,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: DesignTokens.spaceXl),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Result returned from the picker via `Navigator.pop`. Allows the
/// caller to immediately load the SRT body into the player engine
/// without re-reading from disk.
class SubtitlePickResult {
  const SubtitlePickResult({
    this.srtBody,
    this.label,
    this.fileName,
    this.disabled = false,
  });

  /// Raw SRT text. Null when [disabled] is true.
  final String? srtBody;

  /// Display label (e.g. `Movie [TR]`).
  final String? label;

  /// File name surfaced in the "Yuklenen altyazi" indicator.
  final String? fileName;

  /// True when the user explicitly chose "Disable subtitles".
  final bool disabled;
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceS,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Kapat',
            icon: const Icon(Icons.close_rounded),
            onPressed: onClose,
          ),
          Expanded(
            child: Text(
              'Altyazilar',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Premium banner
// ---------------------------------------------------------------------------

class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Material(
        color: scheme.primary.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: Container(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
              border: Border.all(
                color: scheme.primary.withValues(alpha: 0.33),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.lock_outline_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Premium Ozellik',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'OpenSubtitles indirmeleri Premium ile acilir',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.65),
                            ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Yukselt ->',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Loaded indicator
// ---------------------------------------------------------------------------

class _LoadedIndicator extends StatelessWidget {
  const _LoadedIndicator({required this.fileName});

  final String fileName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceS,
        ),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          border: Border.all(
            color: scheme.primary.withValues(alpha: 0.33),
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.subtitles_rounded,
              size: 14,
              color: scheme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Yuklenen altyazi: $fileName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search field
// ---------------------------------------------------------------------------

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: TextField(
        controller: controller,
        onSubmitted: (_) => onSubmit(),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Film veya dizi adi...',
          prefixIcon: const Icon(Icons.search_rounded, size: 18),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  tooltip: 'Temizle',
                  onPressed: controller.clear,
                ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Language selector + picker
// ---------------------------------------------------------------------------

class _LanguageSelectorRow extends StatelessWidget {
  const _LanguageSelectorRow({
    required this.selected,
    required this.expanded,
    required this.onTap,
  });

  final SubtitleLanguage selected;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceM,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
              border: Border.all(color: scheme.outline),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.language_rounded,
                  color: scheme.primary,
                  size: 18,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    selected.nativeName,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: scheme.outline,
                  size: 18,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({
    required this.currentCode,
    required this.onPick,
  });

  final String currentCode;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
        DesignTokens.spaceM,
        0,
      ),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          border: Border.all(color: scheme.outline),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          child: ListView.separated(
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            itemCount: kSubtitleLanguages.length,
            separatorBuilder: (_, __) => Divider(
              height: 1,
              color: scheme.outline,
            ),
            itemBuilder: (BuildContext context, int i) {
              final lang = kSubtitleLanguages[i];
              final selected = lang.code == currentCode;
              return Material(
                color: selected
                    ? scheme.primary.withValues(alpha: 0.13)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => onPick(lang.code),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: DesignTokens.spaceM,
                      vertical: 10,
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            lang.nativeName,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        Text(
                          lang.name,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: scheme.onSurface
                                    .withValues(alpha: 0.6),
                              ),
                        ),
                        if (selected) ...<Widget>[
                          const SizedBox(width: 8),
                          Icon(
                            Icons.check_rounded,
                            size: 14,
                            color: scheme.primary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Disable button + Search button + Error box
// ---------------------------------------------------------------------------

class _DisableRow extends StatelessWidget {
  const _DisableRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceM,
              vertical: DesignTokens.spaceM,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
              border: Border.all(color: scheme.outline),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.block_rounded,
                  color: scheme.onSurface.withValues(alpha: 0.65),
                  size: 18,
                ),
                const SizedBox(width: 10),
                Text(
                  'Altyaziyi kapat',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color:
                            scheme.onSurface.withValues(alpha: 0.65),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.isLoading,
    required this.enabled,
    required this.onTap,
  });

  final bool isLoading;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: (isLoading || !enabled) ? null : onTap,
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            ),
          ),
          child: isLoading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.search_rounded, size: 16, color: Colors.white),
                    SizedBox(width: 8),
                    Text('OpenSubtitles ara'),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          border: Border.all(color: scheme.outline),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.error_outline_rounded,
              size: 16,
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Result card
// ---------------------------------------------------------------------------

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.result,
    required this.downloading,
    required this.locked,
    required this.onTap,
  });

  final SubtitleResult result;
  final bool downloading;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        0,
        DesignTokens.spaceM,
        DesignTokens.spaceS,
      ),
      child: Material(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        child: InkWell(
          onTap: downloading ? null : onTap,
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          child: Container(
            padding: const EdgeInsets.all(DesignTokens.spaceM),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusS),
              border: Border.all(color: scheme.outline),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        result.release.isEmpty
                            ? 'Subtitle'
                            : result.release,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: <Widget>[
                          _Pill(
                            text: result.language.toUpperCase(),
                            bg: scheme.primary.withValues(alpha: 0.13),
                            fg: scheme.primary,
                          ),
                          if (result.hi)
                            _Pill(
                              text: 'CC',
                              bg: scheme.outline,
                              fg: scheme.onSurface
                                  .withValues(alpha: 0.65),
                            ),
                          if (result.fromTrusted)
                            const _Pill(
                              text: 'HD',
                              bg: Color(0x2222C55E),
                              fg: Color(0xFF22C55E),
                            ),
                          Icon(
                            Icons.download_rounded,
                            size: 11,
                            color: scheme.onSurface
                                .withValues(alpha: 0.6),
                          ),
                          Text(
                            _shortCount(result.downloadCount),
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.6),
                                ),
                          ),
                          if (result.rating > 0) ...<Widget>[
                            const Icon(
                              Icons.star_rounded,
                              size: 11,
                              color: BrandColors.goldRating,
                            ),
                            Text(
                              result.rating.toStringAsFixed(1),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.onSurface
                                        .withValues(alpha: 0.6),
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceS),
                if (locked)
                  Icon(
                    Icons.lock_rounded,
                    size: 16,
                    color: scheme.outline,
                  )
                else if (downloading)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: scheme.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.download_rounded,
                    size: 16,
                    color: scheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _shortCount(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.text,
    required this.bg,
    required this.fg,
  });

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: fg,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings panel
// ---------------------------------------------------------------------------

class _SettingsHeader extends StatelessWidget {
  const _SettingsHeader({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.tune_rounded,
                  size: 18,
                  color: scheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Gorunum ayarlari',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: scheme.outline,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mutable draft surface for the picker — collects in-flight settings
/// changes so they only land in Hive when the user taps "Kaydet ve uygula".
class _DraftSettings {
  _DraftSettings({
    required this.preferredLanguage,
    required this.size,
    required this.color,
    required this.background,
    required this.position,
    required this.bold,
  });

  factory _DraftSettings.from(SubtitleSettings s) => _DraftSettings(
        preferredLanguage: s.preferredLanguage,
        size: s.size,
        color: s.color,
        background: s.background,
        position: s.position,
        bold: s.bold,
      );

  String preferredLanguage;
  SubtitleSize size;
  SubtitleColor color;
  SubtitleBackground background;
  SubtitlePosition position;
  bool bold;

  SubtitleSettings toSettings({
    String? loadedFileName,
    String? loadedLabel,
  }) {
    return SubtitleSettings(
      preferredLanguage: preferredLanguage,
      size: size,
      color: color,
      background: background,
      position: position,
      bold: bold,
      loadedFileName: loadedFileName,
      loadedLabel: loadedLabel,
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel({
    required this.draft,
    required this.onChanged,
  });

  final _DraftSettings draft;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: DesignTokens.spaceM),
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.spaceM),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          border: Border.all(color: scheme.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // Size slider — maps the four discrete buckets to a 0..3
            // continuous slider for an iOS-style feel.
            Text(
              'Boyut: ${draft.size.px.toInt()} px',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            Slider(
              value: SubtitleSize.values.indexOf(draft.size).toDouble(),
              max: 3,
              divisions: 3,
              label: draft.size.wire,
              onChanged: (double v) {
                draft.size = SubtitleSize.values[v.round()];
                onChanged();
              },
            ),
            const SizedBox(height: DesignTokens.spaceS),
            Text(
              'Renk',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: <Widget>[
                for (final c in SubtitleColor.values)
                  _ColorSwatch(
                    color: Color(c.argb),
                    selected: c == draft.color,
                    onTap: () {
                      draft.color = c;
                      onChanged();
                    },
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Text(
              'Arka plan',
              style: Theme.of(context).textTheme.labelMedium,
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                for (final b in SubtitleBackground.values)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: _BgChip(
                        label: switch (b) {
                          SubtitleBackground.none => 'Yok',
                          SubtitleBackground.semi => 'Yarı',
                          SubtitleBackground.solid => 'Tam',
                        },
                        selected: b == draft.background,
                        onTap: () {
                          draft.background = b;
                          onChanged();
                        },
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            Row(
              children: <Widget>[
                Expanded(
                  child: SegmentedButton<SubtitlePosition>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const <ButtonSegment<SubtitlePosition>>[
                      ButtonSegment<SubtitlePosition>(
                        value: SubtitlePosition.bottom,
                        label: Text('Alt'),
                        icon: Icon(Icons.vertical_align_bottom_rounded),
                      ),
                      ButtonSegment<SubtitlePosition>(
                        value: SubtitlePosition.top,
                        label: Text('Ust'),
                        icon: Icon(Icons.vertical_align_top_rounded),
                      ),
                    ],
                    selected: <SubtitlePosition>{draft.position},
                    onSelectionChanged: (Set<SubtitlePosition> next) {
                      draft.position = next.first;
                      onChanged();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceS),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'Kalin',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              value: draft.bold,
              onChanged: (bool v) {
                draft.bold = v;
                onChanged();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outline,
            width: selected ? 2 : 1,
          ),
        ),
      ),
    );
  }
}

class _BgChip extends StatelessWidget {
  const _BgChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.18)
          : scheme.surface,
      borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(DesignTokens.radiusS),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
            ),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stub data for dev/no-API-key builds
// ---------------------------------------------------------------------------

List<SubtitleResult> _stubResultsFor(String query, String lang) {
  // Produce 3 plausible search results so the picker is fully clickable
  // without an OpenSubtitles key. Real client kicks in once the key is
  // wired through `subtitlesServiceProvider`.
  return <SubtitleResult>[
    SubtitleResult(
      fileId: 1,
      language: lang,
      release: '$query.2024.1080p.WEB-DL.H264-AWAtv',
      downloadCount: 12423,
      rating: 8.4,
      hi: false,
      fromTrusted: true,
    ),
    SubtitleResult(
      fileId: 2,
      language: lang,
      release: '$query.2024.HDRip.XviD-CC',
      downloadCount: 5104,
      rating: 7.1,
      hi: true,
      fromTrusted: false,
    ),
    SubtitleResult(
      fileId: 3,
      language: lang,
      release: '$query.S01E01.720p.SVA',
      downloadCount: 998,
      rating: 0,
      hi: false,
      fromTrusted: false,
    ),
  ];
}

String _stubSrtFor(SubtitleResult r) {
  // Minimal valid SRT — three short cues across the first 9 seconds
  // so the overlay has visible output during dev.
  return '1\n'
      '00:00:01,000 --> 00:00:03,000\n'
      '${r.release}\n'
      '\n'
      '2\n'
      '00:00:04,000 --> 00:00:06,000\n'
      '[${r.language.toUpperCase()}] AWAtv stub subtitle\n'
      '\n'
      '3\n'
      '00:00:07,000 --> 00:00:09,000\n'
      'OpenSubtitles entegrasyonu Phase 3.\n';
}
