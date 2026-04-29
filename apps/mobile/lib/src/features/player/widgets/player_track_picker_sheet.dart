import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-sheet modal exposing the engine's full track matrix:
/// audio, subtitles (embedded + OpenSubtitles + local file), and
/// quality. The sheet is intentionally tall (78% of screen) so all
/// three tabs stay reachable on a phone in landscape.
///
/// `searchHint` lets the host screen seed the OpenSubtitles section
/// based on whatever it knows about the playing item. For VOD detail
/// pages we pass `${title}` and (optionally) the year; for episodes we
/// pass `${seriesTitle} S${e.season}E${e.number}` so the upstream
/// query lands on the right release.
///
/// The picker reads the controller directly. All selections close the
/// sheet and surface a snackbar so the user gets feedback without
/// the player chrome reappearing immediately.
class PlayerTrackPickerSheet extends ConsumerStatefulWidget {
  const PlayerTrackPickerSheet({
    required this.controller,
    super.key,
    this.searchHint,
    this.searchYear,
  });

  final AwaPlayerController controller;
  final String? searchHint;
  final int? searchYear;

  static Future<void> show(
    BuildContext context, {
    required AwaPlayerController controller,
    String? searchHint,
    int? searchYear,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      useSafeArea: true,
      builder: (BuildContext _) => PlayerTrackPickerSheet(
        controller: controller,
        searchHint: searchHint,
        searchYear: searchYear,
      ),
    );
  }

  @override
  ConsumerState<PlayerTrackPickerSheet> createState() =>
      _PlayerTrackPickerSheetState();
}

class _PlayerTrackPickerSheetState
    extends ConsumerState<PlayerTrackPickerSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this, initialIndex: 1);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXL),
        ),
        child: ColoredBox(
          color: scheme.surface,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.78,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(top: 6, bottom: 8),
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                TabBar(
                  controller: _tab,
                  isScrollable: false,
                  labelColor: scheme.primary,
                  unselectedLabelColor:
                      scheme.onSurface.withValues(alpha: 0.7),
                  indicatorColor: scheme.primary,
                  tabs: const <Tab>[
                    Tab(icon: Icon(Icons.audiotrack_rounded), text: 'Ses'),
                    Tab(icon: Icon(Icons.subtitles_rounded), text: 'Altyazı'),
                    Tab(icon: Icon(Icons.high_quality_rounded), text: 'Kalite'),
                  ],
                ),
                const Divider(height: 1),
                Expanded(
                  child: TabBarView(
                    controller: _tab,
                    children: <Widget>[
                      _AudioTab(controller: widget.controller),
                      _SubtitleTab(
                        controller: widget.controller,
                        searchHint: widget.searchHint,
                        searchYear: widget.searchYear,
                      ),
                      _QualityTab(controller: widget.controller),
                    ],
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
// Shared list row
// ---------------------------------------------------------------------------

class _PickerRow extends StatelessWidget {
  const _PickerRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.leading,
    this.trailing,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignTokens.motionFast,
        curve: DesignTokens.motionStandard,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceM,
          vertical: DesignTokens.spaceM,
        ),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : Colors.transparent,
        ),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              leading!,
              const SizedBox(width: DesignTokens.spaceM),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight:
                              selected ? FontWeight.w700 : FontWeight.w500,
                        ),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.7),
                            ),
                      ),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: DesignTokens.spaceS),
              trailing!,
            ],
            if (selected)
              Padding(
                padding: const EdgeInsets.only(left: DesignTokens.spaceS),
                child: Icon(Icons.check_rounded, color: scheme.primary),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text, this.action});
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
      ),
      child: Row(
        children: <Widget>[
          Text(
            text,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Spacer(),
          if (action != null) action!,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Audio
// ---------------------------------------------------------------------------

class _AudioTab extends StatelessWidget {
  const _AudioTab({required this.controller});
  final AwaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<AudioTrack>>(
      stream: controller.audioTracksStream,
      initialData: controller.audioTracks,
      builder: (BuildContext _, AsyncSnapshot<List<AudioTrack>> snap) {
        final tracks = snap.data ?? const <AudioTrack>[];
        return StreamBuilder<AudioTrack>(
          stream: controller.currentAudioTrackStream,
          initialData: controller.currentAudioTrack,
          builder: (BuildContext __, AsyncSnapshot<AudioTrack> curSnap) {
            final current = curSnap.data;
            if (tracks.isEmpty) {
              return const _EmptyHint(
                icon: Icons.audiotrack_outlined,
                label: 'Bu yayında ses parçası bilgisi yok.',
              );
            }
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: tracks.length,
              itemBuilder: (BuildContext ctx, int i) {
                final t = tracks[i];
                return _PickerRow(
                  label: _audioLabel(t),
                  subtitle: _audioSubtitle(t),
                  selected: current?.id == t.id,
                  onTap: () async {
                    await controller.setAudioTrack(t);
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Ses: ${_audioLabel(t)}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  static String _audioLabel(AudioTrack t) {
    if (t.id == 'auto') return 'Otomatik';
    if (t.id == 'no') return 'Sesi kapat';
    final lang = t.language;
    final title = t.title;
    if (title != null && title.isNotEmpty) {
      return lang != null && lang.isNotEmpty ? '$title ($lang)' : title;
    }
    if (lang != null && lang.isNotEmpty) return lang.toUpperCase();
    return t.id;
  }

  static String _audioSubtitle(AudioTrack t) {
    final parts = <String>[];
    if (t.channels != null && t.channels!.isNotEmpty) parts.add(t.channels!);
    if (t.codec != null && t.codec!.isNotEmpty) parts.add(t.codec!);
    if (t.samplerate != null && t.samplerate! > 0) {
      parts.add('${(t.samplerate! / 1000).toStringAsFixed(1)} kHz');
    }
    return parts.join(' · ');
  }
}

// ---------------------------------------------------------------------------
// Quality
// ---------------------------------------------------------------------------

class _QualityTab extends StatelessWidget {
  const _QualityTab({required this.controller});
  final AwaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<VideoTrack>>(
      stream: controller.videoTracksStream,
      initialData: controller.videoTracks,
      builder: (BuildContext _, AsyncSnapshot<List<VideoTrack>> snap) {
        final tracks = snap.data ?? const <VideoTrack>[];
        return StreamBuilder<VideoTrack>(
          stream: controller.currentVideoTrackStream,
          initialData: controller.currentVideoTrack,
          builder: (BuildContext __, AsyncSnapshot<VideoTrack> curSnap) {
            final current = curSnap.data;
            if (tracks.isEmpty) {
              return const _EmptyHint(
                icon: Icons.high_quality_outlined,
                label: 'Bu yayında ek kalite seçeneği yok.',
              );
            }
            // Make sure an "Otomatik" entry sits at the top — when the
            // engine reports its own auto track we use it; otherwise we
            // synthesise one that re-applies the engine default.
            final hasAuto = tracks.any((t) => t.id == 'auto');
            return ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: tracks.length + (hasAuto ? 0 : 1),
              itemBuilder: (BuildContext ctx, int i) {
                if (!hasAuto && i == 0) {
                  final autoTrack = VideoTrack.auto();
                  return _PickerRow(
                    label: 'Otomatik',
                    subtitle: 'Ağ koşullarına göre seç',
                    selected: current?.id == 'auto',
                    onTap: () async {
                      await controller.setVideoTrack(autoTrack);
                      if (!ctx.mounted) return;
                      Navigator.of(ctx).pop();
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                          content: Text('Kalite: Otomatik'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                  );
                }
                final idx = hasAuto ? i : i - 1;
                final t = tracks[idx];
                return _PickerRow(
                  label: _qualityLabel(t),
                  subtitle: _qualitySubtitle(t),
                  selected: current?.id == t.id,
                  onTap: () async {
                    await controller.setVideoTrack(t);
                    if (!ctx.mounted) return;
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text('Kalite: ${_qualityLabel(t)}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  static String _qualityLabel(VideoTrack t) {
    if (t.id == 'auto') return 'Otomatik';
    if (t.id == 'no') return 'Yalnızca ses';
    final h = t.h;
    if (h != null && h > 0) {
      if (h >= 2160) return '4K (UHD)';
      if (h >= 1440) return '2K';
      return '${h}p';
    }
    return t.title ?? t.id;
  }

  static String _qualitySubtitle(VideoTrack t) {
    final parts = <String>[];
    if (t.w != null && t.h != null && t.w! > 0 && t.h! > 0) {
      parts.add('${t.w}×${t.h}');
    }
    if (t.bitrate != null && t.bitrate! > 0) {
      parts.add('${(t.bitrate! / 1000).round()} kbps');
    }
    if (t.codec != null && t.codec!.isNotEmpty) parts.add(t.codec!);
    return parts.join(' · ');
  }
}

// ---------------------------------------------------------------------------
// Subtitles
// ---------------------------------------------------------------------------

class _SubtitleTab extends ConsumerStatefulWidget {
  const _SubtitleTab({
    required this.controller,
    this.searchHint,
    this.searchYear,
  });

  final AwaPlayerController controller;
  final String? searchHint;
  final int? searchYear;

  @override
  ConsumerState<_SubtitleTab> createState() => _SubtitleTabState();
}

class _SubtitleTabState extends ConsumerState<_SubtitleTab> {
  late final TextEditingController _queryController;
  Future<List<SubtitleResult>>? _searchFuture;
  bool _downloading = false;
  String _lang = 'tr';

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController(text: widget.searchHint ?? '');
    _kickoffAutoSearch();
  }

  void _kickoffAutoSearch() {
    final svc = ref.read(subtitlesServiceProvider);
    if (!svc.isAvailable) return;
    final q = (widget.searchHint ?? '').trim();
    if (q.isEmpty) return;
    setState(() {
      _searchFuture = svc.searchByQuery(
        q,
        lang: _lang,
        year: widget.searchYear,
      );
    });
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    final svc = ref.read(subtitlesServiceProvider);
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    setState(() {
      _searchFuture = svc.searchByQuery(q, lang: _lang, year: widget.searchYear);
    });
  }

  Future<void> _applyOpenSubtitle(SubtitleResult r) async {
    final svc = ref.read(subtitlesServiceProvider);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _downloading = true);
    try {
      final body = await svc.fetchSrt(r.fileId, lang: r.language);
      // media_kit accepts an SRT body verbatim via `SubtitleTrack.data` —
      // works on every platform (web included) without round-tripping
      // through a tmp file. We still expose `writeToTempFile` on the
      // service for callers that explicitly want a `file://` URI.
      await widget.controller.setSubtitleTrack(
        SubtitleTrack.data(body, language: r.language, title: r.release),
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Altyazı yüklendi: ${r.release}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Altyazı indirilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _pickLocalFile() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      const group = XTypeGroup(
        label: 'Altyazı',
        extensions: <String>['srt', 'vtt', 'ass', 'ssa'],
      );
      final file = await openFile(
        acceptedTypeGroups: <XTypeGroup>[group],
      );
      if (file == null) return;
      // Read the file content and feed it as data — works identically
      // on iOS / Android / desktop / web because we sidestep the
      // platform-specific path semantics.
      final body = await file.readAsString();
      await widget.controller.setSubtitleTrack(
        SubtitleTrack.data(body, title: file.name),
      );
      if (!mounted) return;
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Altyazı yüklendi: ${file.name}'),
          duration: const Duration(seconds: 2),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Altyazı yüklenemedi: $e')),
      );
    }
  }

  Future<void> _disableSubtitles() async {
    await widget.controller.setSubtitleTrack(SubtitleTrack.no());
    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Altyazı kapatıldı.'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final svc = ref.watch(subtitlesServiceProvider);
    final canAutoFetch =
        ref.watch(canUseFeatureProvider(PremiumFeature.autoSubtitles));

    return StreamBuilder<List<SubtitleTrack>>(
      stream: widget.controller.subtitleTracksStream,
      initialData: widget.controller.subtitleTracks,
      builder: (BuildContext _, AsyncSnapshot<List<SubtitleTrack>> snap) {
        final embedded = snap.data ?? const <SubtitleTrack>[];
        return StreamBuilder<SubtitleTrack>(
          stream: widget.controller.currentSubtitleTrackStream,
          initialData: widget.controller.currentSubtitleTrack,
          builder: (BuildContext __, AsyncSnapshot<SubtitleTrack> curSnap) {
            final current = curSnap.data;
            return ListView(
              padding: EdgeInsets.zero,
              children: <Widget>[
                _PickerRow(
                  leading: const Icon(Icons.visibility_off_outlined),
                  label: 'Kapat',
                  subtitle: 'Altyazıyı tamamen gizle',
                  selected: current?.id == 'no',
                  onTap: _disableSubtitles,
                ),
                _PickerRow(
                  leading: const Icon(Icons.upload_file_outlined),
                  label: 'Yükle (.srt / .vtt)',
                  subtitle: 'Cihazdan dosya seç',
                  selected: false,
                  onTap: _pickLocalFile,
                ),
                if (embedded.isNotEmpty) ...<Widget>[
                  const _SectionLabel(text: 'Mevcut'),
                  for (final SubtitleTrack t in embedded)
                    _PickerRow(
                      label: _embeddedLabel(t),
                      subtitle: _embeddedSubtitle(t),
                      selected: current?.id == t.id,
                      onTap: () async {
                        await widget.controller.setSubtitleTrack(t);
                        if (!mounted) return;
                        Navigator.of(context).pop();
                      },
                    ),
                ],
                const SizedBox(height: DesignTokens.spaceM),
                _SectionLabel(
                  text: 'OpenSubtitles',
                  action: !canAutoFetch
                      ? _PremiumChip(
                          onTap: () => PremiumLockSheet.show(
                            context,
                            PremiumFeature.autoSubtitles,
                          ),
                        )
                      : null,
                ),
                if (!svc.isAvailable)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(
                      DesignTokens.spaceM,
                      DesignTokens.spaceXs,
                      DesignTokens.spaceM,
                      DesignTokens.spaceM,
                    ),
                    child: Text(
                      'OpenSubtitles API anahtarı .env dosyasında '
                      'tanımlanmamış. Aramayı etkinleştirmek için '
                      'OPENSUBTITLES_API_KEY değerini doldurun.',
                    ),
                  )
                else ...<Widget>[
                  _SubtitleSearchBar(
                    controller: _queryController,
                    lang: _lang,
                    onLangChanged: (String l) {
                      setState(() => _lang = l);
                      _runSearch();
                    },
                    onSubmit: _runSearch,
                  ),
                  if (_downloading) const _DownloadProgress(),
                  if (_searchFuture != null)
                    FutureBuilder<List<SubtitleResult>>(
                      future: _searchFuture,
                      builder: (BuildContext ctx,
                          AsyncSnapshot<List<SubtitleResult>> s) {
                        if (s.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.all(DesignTokens.spaceM),
                            child: LinearProgressIndicator(),
                          );
                        }
                        if (s.hasError) {
                          return Padding(
                            padding:
                                const EdgeInsets.all(DesignTokens.spaceM),
                            child: Text('Arama başarısız: ${s.error}'),
                          );
                        }
                        final results = s.data ?? const <SubtitleResult>[];
                        if (results.isEmpty) {
                          return const Padding(
                            padding: EdgeInsets.all(DesignTokens.spaceM),
                            child: Text(
                              'Sonuç bulunamadı. Başlığı veya yılı '
                              'değiştirip tekrar deneyin.',
                            ),
                          );
                        }
                        return Column(
                          children: <Widget>[
                            for (final SubtitleResult r in results)
                              _PickerRow(
                                label: r.release,
                                subtitle: _osSubtitle(r),
                                selected: false,
                                trailing: r.fromTrusted
                                    ? const Icon(
                                        Icons.verified_outlined,
                                        size: 18,
                                      )
                                    : null,
                                onTap: () => _applyOpenSubtitle(r),
                              ),
                          ],
                        );
                      },
                    ),
                ],
                const SizedBox(height: DesignTokens.spaceXl),
              ],
            );
          },
        );
      },
    );
  }

  static String _embeddedLabel(SubtitleTrack t) {
    if (t.id == 'auto') return 'Otomatik';
    if (t.id == 'no') return 'Kapalı';
    final title = t.title;
    final lang = t.language;
    if (title != null && title.isNotEmpty) {
      return lang != null && lang.isNotEmpty ? '$title ($lang)' : title;
    }
    if (lang != null && lang.isNotEmpty) return lang.toUpperCase();
    return t.id;
  }

  static String _embeddedSubtitle(SubtitleTrack t) {
    if (t.codec != null && t.codec!.isNotEmpty) return t.codec!;
    return '';
  }

  static String _osSubtitle(SubtitleResult r) {
    final parts = <String>[
      r.language.toUpperCase(),
      '${r.downloadCount} indirme',
      if (r.rating > 0) '${r.rating.toStringAsFixed(1)} puan',
      if (r.hi) 'CC',
      if (r.releaseGroup != null && r.releaseGroup!.isNotEmpty)
        r.releaseGroup!,
    ];
    return parts.join(' · ');
  }
}

class _SubtitleSearchBar extends StatelessWidget {
  const _SubtitleSearchBar({
    required this.controller,
    required this.lang,
    required this.onLangChanged,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final String lang;
  final ValueChanged<String> onLangChanged;
  final VoidCallback onSubmit;

  static const Map<String, String> _langs = <String, String>{
    'tr': 'Türkçe',
    'en': 'English',
    'de': 'Deutsch',
    'es': 'Español',
    'fr': 'Français',
    'ar': 'العربية',
    'ru': 'Русский',
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
        DesignTokens.spaceM,
        DesignTokens.spaceS,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Başlık ara…',
                prefixIcon: Icon(Icons.search_rounded),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.spaceS),
          DropdownButton<String>(
            value: lang,
            onChanged: (String? v) => v == null ? null : onLangChanged(v),
            items: <DropdownMenuItem<String>>[
              for (final entry in _langs.entries)
                DropdownMenuItem<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
            ],
          ),
          const SizedBox(width: DesignTokens.spaceXs),
          IconButton(
            tooltip: 'Ara',
            onPressed: onSubmit,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
        DesignTokens.spaceM,
        DesignTokens.spaceXs,
      ),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: DesignTokens.spaceM),
          Text('Altyazı indiriliyor…'),
        ],
      ),
    );
  }
}

class _PremiumChip extends StatelessWidget {
  const _PremiumChip({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: scheme.tertiary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'PRO',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.tertiary,
                fontWeight: FontWeight.w800,
              ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 36, color: scheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(height: DesignTokens.spaceS),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

