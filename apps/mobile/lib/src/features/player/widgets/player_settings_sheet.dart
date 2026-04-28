import 'package:awatv_mobile/src/features/player/player_backend_preference.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_player/awatv_player.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-modal sheet that exposes track and speed pickers for the
/// player. Sections appear top-down:
/// Quality → Audio → Subtitles → Speed → Engine.
///
/// The engine section is gated behind the `vlcBackend` premium feature.
/// Selecting a different engine triggers [onBackendChanged] (when
/// provided) — the player screen uses that to tear down the current
/// controller and rebuild it against the chosen backend.
///
/// The sheet reads the controller directly and is fully self-contained:
/// the player screen only has to push it. Selections close the sheet and
/// surface a brief toast confirmation in the parent's [Scaffold].
class PlayerSettingsSheet extends StatelessWidget {
  const PlayerSettingsSheet({
    required this.controller,
    super.key,
    this.onBackendChanged,
  });

  final AwaPlayerController controller;

  /// Invoked when the user picks a different player engine. The parent
  /// screen disposes the active controller and creates a new one bound
  /// to the chosen backend. Null disables the engine section entirely.
  final Future<void> Function(PlayerBackend next)? onBackendChanged;

  /// Convenience — present the sheet with the standard AWAtv chrome.
  static Future<void> show(
    BuildContext context, {
    required AwaPlayerController controller,
    Future<void> Function(PlayerBackend next)? onBackendChanged,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      useSafeArea: true,
      builder: (BuildContext sheetCtx) => PlayerSettingsSheet(
        controller: controller,
        onBackendChanged: onBackendChanged,
      ),
    );
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceM,
                DesignTokens.spaceS,
                DesignTokens.spaceM,
                DesignTokens.spaceL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 6, bottom: 12),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  _QualitySection(controller: controller),
                  const SizedBox(height: DesignTokens.spaceL),
                  _AudioSection(controller: controller),
                  const SizedBox(height: DesignTokens.spaceL),
                  _SubtitleSection(controller: controller),
                  const SizedBox(height: DesignTokens.spaceL),
                  _SpeedSection(controller: controller),
                  if (onBackendChanged != null) ...<Widget>[
                    const SizedBox(height: DesignTokens.spaceL),
                    _BackendSection(
                      currentBackend: controller.backend,
                      onBackendChanged: onBackendChanged!,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceS,
        vertical: DesignTokens.spaceXs,
      ),
      child: Row(
        children: <Widget>[
          Icon(icon, color: scheme.primary, size: 20),
          const SizedBox(width: DesignTokens.spaceS),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusM),
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
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: <Widget>[
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

class _QualitySection extends StatelessWidget {
  const _QualitySection({required this.controller});
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _SectionHeader(
                  icon: Icons.high_quality_rounded,
                  title: 'Görüntü kalitesi',
                ),
                if (tracks.isEmpty)
                  const _EmptyHint(label: 'Bu yayında ek kalite seçeneği yok.')
                else
                  ...tracks.map(
                    (VideoTrack t) => _OptionRow(
                      label: _qualityLabel(t),
                      subtitle: _qualitySubtitle(t),
                      selected: current?.id == t.id,
                      onTap: () async {
                        await controller.setVideoTrack(t);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Kalite: ${_qualityLabel(t)}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
              ],
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

class _AudioSection extends StatelessWidget {
  const _AudioSection({required this.controller});
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
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _SectionHeader(
                  icon: Icons.audiotrack_rounded,
                  title: 'Ses parçası',
                ),
                if (tracks.isEmpty)
                  const _EmptyHint(label: 'Ses parçası bulunamadı.')
                else
                  ...tracks.map(
                    (AudioTrack t) => _OptionRow(
                      label: _audioLabel(t),
                      subtitle: _audioSubtitle(t),
                      selected: current?.id == t.id,
                      onTap: () async {
                        await controller.setAudioTrack(t);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Ses: ${_audioLabel(t)}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
              ],
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

class _SubtitleSection extends StatelessWidget {
  const _SubtitleSection({required this.controller});
  final AwaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<SubtitleTrack>>(
      stream: controller.subtitleTracksStream,
      initialData: controller.subtitleTracks,
      builder: (BuildContext _, AsyncSnapshot<List<SubtitleTrack>> snap) {
        final tracks = snap.data ?? const <SubtitleTrack>[];
        return StreamBuilder<SubtitleTrack>(
          stream: controller.currentSubtitleTrackStream,
          initialData: controller.currentSubtitleTrack,
          builder: (BuildContext __, AsyncSnapshot<SubtitleTrack> curSnap) {
            final current = curSnap.data;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                const _SectionHeader(
                  icon: Icons.subtitles_rounded,
                  title: 'Altyazı',
                ),
                if (tracks.isEmpty)
                  const _EmptyHint(label: 'Altyazı bulunamadı.')
                else
                  ...tracks.map(
                    (SubtitleTrack t) => _OptionRow(
                      label: _subtitleLabel(t),
                      subtitle: _subtitleSubtitle(t),
                      selected: current?.id == t.id,
                      onTap: () async {
                        await controller.setSubtitleTrack(t);
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Altyazı: ${_subtitleLabel(t)}'),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  static String _subtitleLabel(SubtitleTrack t) {
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

  static String _subtitleSubtitle(SubtitleTrack t) {
    if (t.codec != null && t.codec!.isNotEmpty) return t.codec!;
    return '';
  }
}

class _SpeedSection extends StatefulWidget {
  const _SpeedSection({required this.controller});
  final AwaPlayerController controller;

  @override
  State<_SpeedSection> createState() => _SpeedSectionState();
}

class _SpeedSectionState extends State<_SpeedSection> {
  static const List<double> _speeds = <double>[0.5, 0.75, 1, 1.25, 1.5, 2];
  double _selected = 1;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionHeader(
          icon: Icons.speed_rounded,
          title: 'Oynatma hızı',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceS,
            vertical: DesignTokens.spaceXs,
          ),
          child: Wrap(
            spacing: DesignTokens.spaceS,
            runSpacing: DesignTokens.spaceS,
            children: _speeds.map((double s) {
              final picked = (_selected - s).abs() < 0.001;
              return ChoiceChip(
                selected: picked,
                onSelected: (bool _) async {
                  setState(() => _selected = s);
                  await widget.controller.setSpeed(s);
                  if (!context.mounted) return;
                  Navigator.of(context).pop();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Oynatma hızı: ${_formatSpeed(s)}',
                      ),
                      duration: const Duration(seconds: 2),
                    ),
                  );
                },
                label: Text(_formatSpeed(s)),
                selectedColor: scheme.primary.withValues(alpha: 0.18),
                side: BorderSide(
                  color: picked
                      ? scheme.primary.withValues(alpha: 0.6)
                      : scheme.outline.withValues(alpha: 0.4),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  static String _formatSpeed(double s) {
    if (s == s.roundToDouble()) return '${s.toInt()}×';
    return '${s.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '')}×';
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceS,
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.6),
            ),
      ),
    );
  }
}

/// Picker that lets the user switch between Auto / media_kit / VLC.
///
/// Wraps the sheet's tap row in a Riverpod consumer so the persisted
/// preference shows the live "selected" highlight without the parent
/// having to forward state. The premium gate is checked here so the
/// row stays visible to free users (they get a `PRO` chip and a tap-
/// through to the paywall sheet) instead of being hidden entirely.
class _BackendSection extends ConsumerWidget {
  const _BackendSection({
    required this.currentBackend,
    required this.onBackendChanged,
  });

  /// Backend currently powering the active controller — used as the
  /// "selected" indicator when the persisted preference is `auto`.
  final PlayerBackend currentBackend;
  final Future<void> Function(PlayerBackend next) onBackendChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preference = ref.watch(playerBackendPreferenceProvider);
    final allowed =
        ref.watch(canUseFeatureProvider(PremiumFeature.vlcBackend));
    final vlcAvailable = PlayerBackendCapabilities.vlcSupported;

    Future<void> select(PlayerBackend next) async {
      // Snackbars must be dispatched via the *root* ScaffoldMessenger,
      // not the sheet's local context — the sheet element unmounts the
      // moment we pop, and `ScaffoldMessenger.of(context)` would resolve
      // against a dead element. Capture the messenger first.
      final messenger = ScaffoldMessenger.of(context);
      final navigator = Navigator.of(context);

      if (next == PlayerBackend.vlc && !vlcAvailable) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(PlayerBackendCapabilities.vlcReason),
            duration: const Duration(seconds: 3),
          ),
        );
        return;
      }
      if (next == PlayerBackend.vlc && !allowed) {
        navigator.pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('VLC motoru Premium üyelik gerektirir.'),
            duration: Duration(seconds: 3),
          ),
        );
        return;
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Oynatıcı motoru: ${_label(next)}'),
          duration: const Duration(seconds: 2),
        ),
      );
      await onBackendChanged(next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const _SectionHeader(
          icon: Icons.tune_rounded,
          title: 'Oynatıcı motoru',
        ),
        _OptionRow(
          label: 'Otomatik',
          subtitle: 'Cihaz için en iyi motoru seç',
          selected: preference == PlayerBackend.auto,
          onTap: () => select(PlayerBackend.auto),
        ),
        _OptionRow(
          label: 'Yerel motor (libmpv)',
          subtitle: 'HEVC, AV1, HLS, DASH için optimize',
          selected: preference == PlayerBackend.mediaKit ||
              (preference == PlayerBackend.auto &&
                  currentBackend == PlayerBackend.mediaKit),
          onTap: () => select(PlayerBackend.mediaKit),
        ),
        _BackendVlcRow(
          selected: preference == PlayerBackend.vlc ||
              (preference == PlayerBackend.auto &&
                  currentBackend == PlayerBackend.vlc),
          locked: !allowed,
          unsupported: !vlcAvailable,
          onTap: () => select(PlayerBackend.vlc),
        ),
      ],
    );
  }

  static String _label(PlayerBackend b) => switch (b) {
        PlayerBackend.auto => 'Otomatik',
        PlayerBackend.mediaKit => 'Yerel (libmpv)',
        PlayerBackend.vlc => 'VLC',
      };
}

/// VLC row — variant of `_OptionRow` that surfaces the premium gate
/// and the platform-unsupported state inline. Disabled rows still respond
/// to taps so the user gets a snackbar explaining why; `_OptionRow`'s
/// strict on/off model didn't fit those paths cleanly.
class _BackendVlcRow extends StatelessWidget {
  const _BackendVlcRow({
    required this.selected,
    required this.locked,
    required this.unsupported,
    required this.onTap,
  });

  final bool selected;
  final bool locked;
  final bool unsupported;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dimmed = unsupported;
    final subtitle = unsupported
        ? PlayerBackendCapabilities.vlcReason
        : 'Zorlu codec / DRM / panel kıvrımı için yedek';
    return Opacity(
      opacity: dimmed ? 0.55 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
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
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          'VLC motoru',
                          style: Theme.of(context)
                              .textTheme
                              .bodyLarge
                              ?.copyWith(
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                        ),
                        if (locked) ...<Widget>[
                          const SizedBox(width: DesignTokens.spaceS),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: scheme.tertiary.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'PRO',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                    color: scheme.tertiary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(
                              color: scheme.onSurface
                                  .withValues(alpha: 0.7),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Padding(
                  padding: const EdgeInsets.only(left: DesignTokens.spaceS),
                  child: Icon(Icons.check_rounded, color: scheme.primary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
