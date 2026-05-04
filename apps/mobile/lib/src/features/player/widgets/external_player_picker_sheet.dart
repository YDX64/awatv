import 'dart:io' show Platform;

import 'package:awatv_mobile/src/features/player/external_player_launcher.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
// `url_launcher` is resolved transitively via other plugins; the
// direct dep is not yet in apps/mobile/pubspec.yaml. See the launcher
// file for the same note. Adding it explicitly is tracked outside
// this scope.
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';

/// Outcome reported back to the caller when the sheet closes.
class ExternalPlayerPickResult {
  const ExternalPlayerPickResult({required this.player, required this.launched});

  /// The picked player.
  final ExternalPlayer player;

  /// `true` if the deep-link launched (or fell through gracefully when
  /// MX Player Pro was missing but Free took over). `false` when the
  /// player is not installed or the OS refused the URI.
  final bool launched;
}

/// Bottom sheet that lets the user pick which external player to open
/// the current stream in.
///
/// Presented from `_onExternalPlayerRequested` in `PlayerScreen`. The
/// sheet inspects the platform, hides players that are not advertised
/// there, and returns an [ExternalPlayerPickResult] when the user
/// selects one. The host then surfaces a snackbar (with a one-tap
/// install link) if [ExternalPlayerPickResult.launched] is `false`.
class ExternalPlayerPickerSheet extends ConsumerStatefulWidget {
  const ExternalPlayerPickerSheet({
    required this.streamUri,
    super.key,
    this.headers,
  });

  /// Stream URL to forward to the picked player. Must be a fully-
  /// qualified URI — file:// and http(s):// are accepted; rtmp / rtsp
  /// also work but only on VLC.
  final Uri streamUri;

  /// Optional HTTP headers to forward (User-Agent, Referer). Best-
  /// effort; see [ExternalPlayerLauncher.launch] for the per-player
  /// behaviour.
  final Map<String, String>? headers;

  /// Convenience opener.
  ///
  /// Returns the [ExternalPlayerPickResult] of the selection, or `null`
  /// if the user dismissed the sheet without picking anything.
  static Future<ExternalPlayerPickResult?> show(
    BuildContext context, {
    required Uri streamUri,
    Map<String, String>? headers,
  }) {
    return showModalBottomSheet<ExternalPlayerPickResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.6),
      builder: (BuildContext _) => ExternalPlayerPickerSheet(
        streamUri: streamUri,
        headers: headers,
      ),
    );
  }

  @override
  ConsumerState<ExternalPlayerPickerSheet> createState() =>
      _ExternalPlayerPickerSheetState();
}

class _ExternalPlayerPickerSheetState
    extends ConsumerState<ExternalPlayerPickerSheet> {
  final ExternalPlayerLauncher _launcher = const ExternalPlayerLauncher();
  ExternalPlayer? _busy;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    // Filter out players we know cannot run on the current platform.
    // The launcher is the single source of truth for this — keeping
    // the list policy here would drift over time.
    final options = ExternalPlayer.values
        .where(_launcher.isPlatformSupported)
        .toList(growable: false);

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
                  // Drag handle — matches sleep_timer_sheet / track picker.
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
                        Icon(
                          Icons.open_in_new_rounded,
                          color: scheme.primary,
                          size: 20,
                        ),
                        const SizedBox(width: DesignTokens.spaceS),
                        Text(
                          'Harici oynatici',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      DesignTokens.spaceS,
                      0,
                      DesignTokens.spaceS,
                      DesignTokens.spaceM,
                    ),
                    child: Text(
                      'Yayini su uygulamada ac',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurface.withValues(alpha: 0.65),
                          ),
                    ),
                  ),
                  if (options.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: DesignTokens.spaceM,
                        vertical: DesignTokens.spaceL,
                      ),
                      child: Text(
                        'Bu cihazda desteklenen harici oynatici yok.',
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.7),
                                ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else
                    for (final ExternalPlayer p in options)
                      _PlayerTile(
                        player: p,
                        loading: _busy == p,
                        onTap: () => _launchPlayer(p),
                      ),
                  const SizedBox(height: DesignTokens.spaceS),
                  // Cancel footer — matches the sheet conventions used
                  // elsewhere in the player feature.
                  TextButton(
                    onPressed: _busy != null
                        ? null
                        : () => Navigator.of(context).maybePop(),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.onSurface.withValues(alpha: 0.75),
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.spaceM,
                      ),
                    ),
                    child: const Text('Iptal'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _launchPlayer(ExternalPlayer player) async {
    if (_busy != null) return;
    setState(() => _busy = player);

    var launched = await _launcher.launch(
      player,
      widget.streamUri,
      headers: widget.headers,
    );

    // MX Player Pro ↔ Free fallback. The launcher dispatches the Pro
    // intent first; if that handler is absent we retry with the Free
    // package id, which has a different `package=` target. Keeping
    // the fallback at the picker layer (rather than baking it into
    // [ExternalPlayerLauncher]) means callers that explicitly want
    // Free can target it via a dedicated enum value later without
    // breaking the existing single-MX surface.
    if (!launched && player == ExternalPlayer.mxPlayer && _isAndroid) {
      launched = await _launchMxFreeFallback();
    }

    if (!mounted) return;
    setState(() => _busy = null);
    await Navigator.of(context).maybePop(
      ExternalPlayerPickResult(player: player, launched: launched),
    );
  }

  bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  Future<bool> _launchMxFreeFallback() async {
    // The free build's package id differs from the pro build by one
    // suffix component. We construct the same intent shape by hand
    // because the launcher abstracts the package id behind its enum.
    final sb = StringBuffer('intent:')
      ..write(widget.streamUri.toString())
      ..write('#Intent;')
      ..write('package=com.mxtech.videoplayer.ad;')
      ..write('type=video/*;');
    final headers = widget.headers;
    if (headers != null) {
      final ua = headers['User-Agent'] ?? headers['user-agent'];
      final referer = headers['Referer'] ?? headers['referer'];
      if (ua != null && ua.isNotEmpty) {
        sb.write('S.User-Agent=${Uri.encodeComponent(ua)};');
      }
      if (referer != null && referer.isNotEmpty) {
        sb.write('S.Referer=${Uri.encodeComponent(referer)};');
      }
    }
    sb.write('end');
    final uri = Uri.parse(sb.toString());
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}

/// Single-row tile for one player option. Layout:
/// `[icon] Name  ¶ Tagline                  [chevron / spinner]`.
class _PlayerTile extends StatelessWidget {
  const _PlayerTile({
    required this.player,
    required this.loading,
    required this.onTap,
  });

  final ExternalPlayer player;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: loading ? null : onTap,
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
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(DesignTokens.radiusM),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
        child: Row(
          children: <Widget>[
            // Use a generic play-arrow because the project does not
            // ship per-app brand icons; the label below disambiguates.
            Icon(
              Icons.play_circle_outline_rounded,
              color: scheme.primary,
              size: 24,
            ),
            const SizedBox(width: DesignTokens.spaceM),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    player.displayName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    player.tagline,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                  ),
                ],
              ),
            ),
            if (loading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                      AlwaysStoppedAnimation<Color>(scheme.primary),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                color: scheme.onSurface.withValues(alpha: 0.55),
              ),
          ],
        ),
      ),
    );
  }
}
