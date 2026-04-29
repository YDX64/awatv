import 'package:awatv_mobile/src/shared/player/sleep_timer.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-modal that lets the user pick a sleep-timer preset.
///
/// Options surfaced (in order):
///   1. Kapali — cancels any active timer.
///   2. Fixed durations: 15 / 30 / 45 / 60 / 90 dakika.
///   3. Ozel sure — picker for any minutes value (1..240).
///   4. Bolum/programa sonu — only when the host can give us an
///      `endsAt` (live programme stop OR VOD/episode duration). The
///      sheet labels it correctly via [SleepTriggerKind].
///   5. Belirli saat — pick an absolute time of day.
///
/// All options trigger a 10-second smart fade + pause once the timer
/// elapses (handled by [SleepTimerNotifier._fire]).
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({
    required this.endOfProgrammeAt,
    this.endOfEpisodeAt,
    super.key,
  });

  /// `endsAt` for the currently airing live programme, if known.
  final DateTime? endOfProgrammeAt;

  /// `endsAt` for the currently playing VOD / episode (start +
  /// total duration), if known. Null for live or when the engine
  /// hasn't reported a duration yet.
  final DateTime? endOfEpisodeAt;

  /// Convenience opener.
  static Future<void> show(
    BuildContext context, {
    DateTime? endOfProgrammeAt,
    DateTime? endOfEpisodeAt,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetCtx) => SleepTimerSheet(
        endOfProgrammeAt: endOfProgrammeAt,
        endOfEpisodeAt: endOfEpisodeAt,
      ),
    );
  }

  static const List<Duration> _presets = <Duration>[
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
    Duration(minutes: 90),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(sleepTimerProvider);
    final notifier = ref.read(sleepTimerProvider.notifier);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(DesignTokens.radiusXL),
      ),
      child: ColoredBox(
        color: scheme.surface,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceM,
                DesignTokens.spaceS,
                DesignTokens.spaceM,
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
                      margin: const EdgeInsets.only(top: 6, bottom: 12),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spaceS,
                      0,
                      DesignTokens.spaceS,
                      DesignTokens.spaceXs,
                    ),
                    child: Row(
                      children: <Widget>[
                        Icon(Icons.bedtime_rounded,
                            color: scheme.primary, size: 20),
                        const SizedBox(width: DesignTokens.spaceS),
                        Text(
                          'Uyku zamanlayicisi',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        Text(
                          'Yumusak gecis ile durdurur',
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.55),
                          ),
                        ),
                      ],
                    ),
                  ),
                  _OptionTile(
                    label: 'Kapali',
                    selected: !state.isActive,
                    onTap: () {
                      notifier.cancel();
                      Navigator.of(context).pop();
                    },
                  ),
                  for (final d in _presets)
                    _OptionTile(
                      label: '${d.inMinutes} dakika',
                      selected: state.duration == d &&
                          state.trigger == SleepTriggerKind.duration,
                      onTap: () {
                        notifier.set(d, trigger: SleepTriggerKind.duration);
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${d.inMinutes} dakika sonra oynatma duracak.',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  _OptionTile(
                    label: 'Ozel sure',
                    subtitle: 'Dakika cinsinden sec (1-240)',
                    icon: Icons.timer_rounded,
                    selected: state.isActive &&
                        state.trigger == SleepTriggerKind.duration &&
                        !_presets.contains(state.duration),
                    onTap: () async {
                      final picked = await _pickCustomMinutes(context);
                      if (picked == null) return;
                      notifier.set(
                        Duration(minutes: picked),
                        trigger: SleepTriggerKind.duration,
                      );
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '$picked dakika sonra oynatma duracak.',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                  if (endOfEpisodeAt != null)
                    _OptionTile(
                      label: 'Bolum sonu',
                      subtitle: _formatEndsAt(endOfEpisodeAt!),
                      icon: Icons.movie_rounded,
                      selected: state.isActive &&
                          state.trigger == SleepTriggerKind.endOfEpisode,
                      onTap: () {
                        notifier.setUntil(
                          endOfEpisodeAt!,
                          trigger: SleepTriggerKind.endOfEpisode,
                        );
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Bolum bitince oynatma duracak.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  if (endOfProgrammeAt != null)
                    _OptionTile(
                      label: 'Program sonu',
                      subtitle: _formatEndsAt(endOfProgrammeAt!),
                      icon: Icons.live_tv_rounded,
                      selected: state.isActive &&
                          state.trigger == SleepTriggerKind.endOfProgramme,
                      onTap: () {
                        notifier.setUntil(
                          endOfProgrammeAt!,
                          trigger: SleepTriggerKind.endOfProgramme,
                        );
                        Navigator.of(context).pop();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Program sonunda oynatma duracak.',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                  _OptionTile(
                    label: 'Belirli saat',
                    subtitle: 'Saat:dakika sec, o anda oynatma duracak',
                    icon: Icons.schedule_rounded,
                    selected: state.isActive &&
                        state.trigger == SleepTriggerKind.custom,
                    onTap: () async {
                      final picked = await _pickClockTime(context);
                      if (picked == null) return;
                      notifier.setUntil(
                        picked,
                        trigger: SleepTriggerKind.custom,
                      );
                      if (!context.mounted) return;
                      Navigator.of(context).pop();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '${_formatEndsAt(picked)} sonra oynatma duracak.',
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<int?> _pickCustomMinutes(BuildContext context) async {
    final controller = TextEditingController(text: '20');
    final picked = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text('Ozel sure'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Dakika',
            hintText: '1-240 arasi',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Vazgec'),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text.trim());
              if (value == null || value < 1 || value > 240) {
                Navigator.of(ctx).pop();
                return;
              }
              Navigator.of(ctx).pop(value);
            },
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
    return picked;
  }

  Future<DateTime?> _pickClockTime(BuildContext context) async {
    final now = DateTime.now();
    final initial = TimeOfDay(hour: now.hour, minute: now.minute);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: 'Oynatmanin durmasini istedigin saat',
    );
    if (picked == null) return null;
    var target = DateTime(
      now.year,
      now.month,
      now.day,
      picked.hour,
      picked.minute,
    );
    if (!target.isAfter(now)) {
      // Picked time is earlier today — schedule for tomorrow.
      target = target.add(const Duration(days: 1));
    }
    return target;
  }

  static String _formatEndsAt(DateTime when) {
    final delta = when.difference(DateTime.now());
    if (delta.isNegative) return 'Simdi';
    if (delta.inMinutes < 60) {
      return 'Yaklasik ${delta.inMinutes} dakika';
    }
    final h = delta.inHours;
    final m = delta.inMinutes.remainder(60);
    return '$h sa $m dk';
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(DesignTokens.radiusM),
      child: AnimatedContainer(
        duration: DesignTokens.motionFast,
        curve: DesignTokens.motionStandard,
        margin: const EdgeInsets.symmetric(vertical: DesignTokens.spaceXs),
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
            if (icon != null) ...<Widget>[
              Icon(
                icon,
                color: selected
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.65),
                size: 20,
              ),
              const SizedBox(width: DesignTokens.spaceS),
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
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle!,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                      ),
                    ),
                ],
              ),
            ),
            if (selected) Icon(Icons.check_rounded, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
