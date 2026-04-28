import 'package:awatv_mobile/src/shared/network/network_info.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tiny status chip — rendered in the home-screen app bar so users can
/// glance at their connection at any time. Hidden when the snapshot
/// can't provide anything useful (early boot, web, no consent + Wi-Fi).
class NetworkChip extends ConsumerWidget {
  const NetworkChip({
    this.compact = false,
    super.key,
  });

  /// Show only the icon; collapse the SSID label. Used inside the
  /// channel header where horizontal space is tight.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snap = networkSnapshotOrOffline(ref);
    if (!snap.hasDisplayableInfo) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final IconData icon;
    final String label;
    switch (snap.kind) {
      case ConnectivityKind.wifi:
        icon = Icons.wifi_rounded;
        label = snap.ssid ?? 'Wi-Fi';
      case ConnectivityKind.ethernet:
        icon = Icons.lan_outlined;
        label = 'Ethernet';
      case ConnectivityKind.cellular:
        icon = Icons.signal_cellular_alt_rounded;
        label = 'Mobil veri';
      case ConnectivityKind.unknown:
        icon = Icons.public_rounded;
        label = 'Online';
      case ConnectivityKind.none:
        return const SizedBox.shrink();
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : DesignTokens.spaceS,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.35),
          width: 0.6,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: scheme.primary),
          if (!compact) ...<Widget>[
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One-shot consent banner shown above the home rows the FIRST time the
/// user opens the home screen. After grant/deny it never reappears
/// unless the user resets it from settings.
class SsidConsentBanner extends ConsumerWidget {
  const SsidConsentBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(networkSsidConsentProvider.notifier);
    final granted = ref.watch(networkSsidConsentProvider);
    if (granted || notifier.hasAsked) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceS,
        DesignTokens.spaceM,
        DesignTokens.spaceS,
      ),
      child: Material(
        color: theme.colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(DesignTokens.radiusL),
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceM),
          child: Row(
            children: <Widget>[
              const Icon(Icons.wifi_rounded, color: BrandColors.primary),
              const SizedBox(width: DesignTokens.spaceM),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Wi-Fi adini gormek ister misin?',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Izin verirsen Wi-Fi adin kanal listesi basliginda '
                      'gozukur. Veri cihazindan disari cikmaz.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
              Column(
                children: <Widget>[
                  TextButton(
                    onPressed: notifier.deny,
                    child: const Text('Hayir'),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceM,
                      ),
                    ),
                    onPressed: notifier.grant,
                    child: const Text('Izin ver'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
