import 'package:awatv_mobile/src/app/env.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Watch-party hub at `/party`. Two big buttons:
///   * "Yeni parti baslat" — generates an 8-char id and pushes
///     `/party/<id>?host=1`.
///   * "Partiye katil" — code-input + "Bagla" button, pushes
///     `/party/<id>`.
///
/// Premium-gated under [PremiumFeature.cloudSync] (uses Supabase
/// Realtime, same gate as remote-control + cloud sync).
class WatchPartyLandingScreen extends ConsumerWidget {
  const WatchPartyLandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Env.hasSupabase) {
      return Scaffold(
        appBar: AppBar(title: const Text('Watch parti')),
        body: const Center(
          child: EmptyState(
            icon: Icons.cloud_off_outlined,
            title: 'Bulut hesabi gerekli',
            subtitle:
                'Watch parti icin AWAtv hesabi ile giris yapmaniz gerekir. '
                'Bu yapida Supabase yapilandirmasi yok.',
          ),
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Watch parti')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const SizedBox(height: DesignTokens.spaceM),
              Text(
                'Arkadaslarinla ayni anda izle',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceS),
              Text(
                'Bir parti baslat, kodu paylas; ayni an ayni sahneyi gorun. '
                'Sohbet ve otomatik senkron dahil.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color:
                      theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: DesignTokens.spaceXl),
              _HostCard(
                onStart: (String name) => _onHost(context, ref, name),
              ),
              const SizedBox(height: DesignTokens.spaceL),
              _JoinCard(
                onJoin: (String name, String code) =>
                    _onJoin(context, ref, name, code),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onHost(
    BuildContext context,
    WidgetRef ref,
    String name,
  ) async {
    final allowed = ref.read(canUseFeatureProvider(PremiumFeature.cloudSync));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.cloudSync);
      return;
    }
    final id = generatePartyId();
    if (!context.mounted) return;
    context.push('/party/$id?host=1&name=${Uri.encodeComponent(name)}');
  }

  Future<void> _onJoin(
    BuildContext context,
    WidgetRef ref,
    String name,
    String rawCode,
  ) async {
    final allowed = ref.read(canUseFeatureProvider(PremiumFeature.cloudSync));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.cloudSync);
      return;
    }
    final code = normalisePartyId(rawCode);
    if (!isValidPartyId(code)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gecersiz parti kodu')),
      );
      return;
    }
    if (!context.mounted) return;
    context.push('/party/$code?name=${Uri.encodeComponent(name)}');
  }
}

class _HostCard extends StatefulWidget {
  const _HostCard({required this.onStart});

  final ValueChanged<String> onStart;

  @override
  State<_HostCard> createState() => _HostCardState();
}

class _HostCardState extends State<_HostCard> {
  final _nameCtrl = TextEditingController(text: 'Host');

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.primary.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.primary.withValues(alpha: 0.18),
                  ),
                  child: Icon(
                    Icons.celebration_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Yeni parti baslat',
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        'Sen host olursun, oynat-duraklat senin elindedir.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Goruenecek isim',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            FilledButton.icon(
              icon: const Icon(Icons.play_circle_filled_rounded),
              label: const Text('Parti baslat'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => widget.onStart(_nameCtrl.text.trim()),
            ),
          ],
        ),
      ),
    );
  }
}

class _JoinCard extends StatefulWidget {
  const _JoinCard({required this.onJoin});

  final void Function(String name, String code) onJoin;

  @override
  State<_JoinCard> createState() => _JoinCardState();
}

class _JoinCardState extends State<_JoinCard> {
  final _nameCtrl = TextEditingController(text: 'Misafir');
  final _codeCtrl = TextEditingController();
  String _normalised = '';

  @override
  void dispose() {
    _nameCtrl.dispose();
    _codeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final canSubmit = isValidPartyId(_normalised);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(DesignTokens.radiusXL),
      child: Padding(
        padding: const EdgeInsets.all(DesignTokens.spaceL),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.tertiary.withValues(alpha: 0.18),
                  ),
                  child: Icon(
                    Icons.group_add_rounded,
                    color: scheme.tertiary,
                  ),
                ),
                const SizedBox(width: DesignTokens.spaceM),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Partiye katil',
                        style: theme.textTheme.titleLarge,
                      ),
                      Text(
                        'Host\'un paylastigi 8 haneli kodu gir.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.spaceM),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Goruenecek isim',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: DesignTokens.spaceM),
            TextField(
              controller: _codeCtrl,
              autofocus: false,
              textAlign: TextAlign.center,
              textCapitalization: TextCapitalization.characters,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontFamily: 'monospace',
                letterSpacing: 6,
                fontWeight: FontWeight.w700,
              ),
              decoration: const InputDecoration(
                labelText: 'Parti kodu',
                hintText: 'AB CD 23 45',
                border: OutlineInputBorder(),
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                LengthLimitingTextInputFormatter(kPartyIdLength),
              ],
              onChanged: (String v) =>
                  setState(() => _normalised = normalisePartyId(v)),
              onSubmitted: (String _) {
                if (canSubmit) {
                  widget.onJoin(_nameCtrl.text.trim(), _normalised);
                }
              },
            ),
            const SizedBox(height: DesignTokens.spaceM),
            FilledButton.tonalIcon(
              icon: const Icon(Icons.login_rounded),
              label: const Text('Bagla'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: canSubmit
                  ? () => widget.onJoin(_nameCtrl.text.trim(), _normalised)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
