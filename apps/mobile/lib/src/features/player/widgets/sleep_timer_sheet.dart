import 'package:awatv_mobile/src/shared/player/sleep_timer.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bottom-modal that lets the user pick a sleep-timer preset.
///
/// "Bölüm sonu" only shows up when the host can give us an
/// `endsAt` — for VOD this is the total runtime, for live it is the
/// programme end derived from EPG (the player screen passes `null` if
/// it can't compute either).
class SleepTimerSheet extends ConsumerWidget {
  const SleepTimerSheet({
    required this.endOfProgrammeAt,
    super.key,
  });

  final DateTime? endOfProgrammeAt;

  /// Convenience opener.
  static Future<void> show(
    BuildContext context, {
    DateTime? endOfProgrammeAt,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetCtx) => SleepTimerSheet(
        endOfProgrammeAt: endOfProgrammeAt,
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
                        'Uyku zamanlayıcısı',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                      ),
                    ],
                  ),
                ),
                _OptionTile(
                  label: 'Kapalı',
                  selected: !state.isActive,
                  onTap: () {
                    notifier.cancel();
                    Navigator.of(context).pop();
                  },
                ),
                for (final d in _presets)
                  _OptionTile(
                    label: '${d.inMinutes} dakika',
                    selected: state.duration == d,
                    onTap: () {
                      notifier.set(d);
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
                if (endOfProgrammeAt != null)
                  _OptionTile(
                    label: 'Bölüm/programa sonuna kadar',
                    subtitle: _formatEndsAt(endOfProgrammeAt!),
                    selected: state.duration == null && state.isActive,
                    onTap: () {
                      notifier.setUntil(endOfProgrammeAt!);
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
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _formatEndsAt(DateTime when) {
    final delta = when.difference(DateTime.now());
    if (delta.isNegative) return 'Şimdi';
    if (delta.inMinutes < 60) {
      return 'Yaklaşık ${delta.inMinutes} dakika';
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
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final String? subtitle;

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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color:
                                  scheme.onSurface.withValues(alpha: 0.7),
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
