import 'package:awatv_mobile/src/features/voice_search/voice_search_controller.dart';
import 'package:awatv_mobile/src/features/voice_search/voice_search_state.dart';
import 'package:awatv_mobile/src/shared/network/app_settings_helper.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Search-bar mic button.
///
/// Three visual states map 1:1 to the [VoiceSearchState] sealed type:
///   * **Idle** — outlined `mic_none_rounded`. Tap arms the engine.
///   * **Listening** — filled `mic_rounded` inside a pulsing ring.
///   * **Processing** — filled mic with a small spinner overlay.
///
/// On unsupported platforms (`voiceSearchSupportedProvider` returns
/// false) the button hides itself entirely so the search bar's
/// trailing slot collapses cleanly.
///
/// Permission failures route to a snackbar with a deep-link to OS
/// settings via [openOsSettingsOrToast]. Errors fall through to a
/// transient toast — the engine resets to idle so a retry tap
/// re-runs the bootstrap probe.
class VoiceSearchButton extends ConsumerStatefulWidget {
  const VoiceSearchButton({
    required this.onResult,
    super.key,
  });

  /// Called when the engine commits a final transcript. The search
  /// screen wires this to its query field + setState so the result
  /// flows into the live filter without an extra "submit" step.
  final ValueChanged<String> onResult;

  @override
  ConsumerState<VoiceSearchButton> createState() => _VoiceSearchButtonState();
}

class _VoiceSearchButtonState extends ConsumerState<VoiceSearchButton> {
  ProviderSubscription<VoiceSearchState>? _stateSub;
  bool _resultsAttached = false;

  @override
  void initState() {
    super.initState();
    // Listen for *errors* and *permission* states inside an explicit
    // listener so we can surface snackbars without forcing the parent
    // to re-render. We can't `ref.listen` from build because the
    // ScaffoldMessenger lookup needs a stable BuildContext.
    _stateSub = ref.listenManual<VoiceSearchState>(
      voiceSearchControllerProvider,
      (VoiceSearchState? prev, VoiceSearchState next) =>
          _handleStateChange(prev, next),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resultsAttached) return;
    // Subscribe to the result stream once we have a context — using
    // the controller's `recognisedTextStream` so the search field
    // gets the final transcript even if the button itself rebuilds
    // mid-session.
    final ctrl = ref.read(voiceSearchControllerProvider.notifier);
    ctrl.recognisedTextStream.listen((String text) {
      if (!mounted) return;
      widget.onResult(text);
    });
    _resultsAttached = true;
  }

  @override
  void dispose() {
    _stateSub?.close();
    super.dispose();
  }

  void _handleStateChange(VoiceSearchState? prev, VoiceSearchState next) {
    if (next is VoiceSearchPermissionDenied) {
      _showPermissionSnack(next.permanent);
    } else if (next is VoiceSearchError) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sesli arama hatasi: ${next.message}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } else if (next is VoiceSearchUnsupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next.reason ??
                'Sesli arama bu cihazda desteklenmiyor.',
          ),
        ),
      );
    }
  }

  void _showPermissionSnack(bool permanent) {
    final messenger = ScaffoldMessenger.of(context);
    if (permanent) {
      messenger.showSnackBar(
        SnackBar(
          content: const Text(
            'Mikrofon izni reddedildi. Sistem ayarlarindan acabilirsin.',
          ),
          action: SnackBarAction(
            label: 'AC',
            onPressed: () =>
                openOsSettingsOrToast(context, kind: OsSettingsPage.app),
          ),
          duration: const Duration(seconds: 5),
        ),
      );
    } else {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Sesli arama icin mikrofon izni gerekli.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  Future<void> _toggle() async {
    final ctrl = ref.read(voiceSearchControllerProvider.notifier);
    final current = ref.read(voiceSearchControllerProvider);
    if (current is VoiceSearchListening ||
        current is VoiceSearchProcessing) {
      await ctrl.stop();
      return;
    }
    await ctrl.start();
  }

  @override
  Widget build(BuildContext context) {
    final supported = ref.watch(voiceSearchSupportedProvider);
    if (!supported) return const SizedBox.shrink();
    final state = ref.watch(voiceSearchControllerProvider);
    return _MicAffordance(
      state: state,
      onTap: _toggle,
    );
  }
}

/// Visual representation of the mic state. Pulled out so the parent
/// can unit-test the controller without dragging Material chrome in.
class _MicAffordance extends StatefulWidget {
  const _MicAffordance({required this.state, required this.onTap});

  final VoiceSearchState state;
  final VoidCallback onTap;

  @override
  State<_MicAffordance> createState() => _MicAffordanceState();
}

class _MicAffordanceState extends State<_MicAffordance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
    lowerBound: 0,
    upperBound: 1,
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _MicAffordance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state.runtimeType != widget.state.runtimeType) {
      _syncAnimation();
    }
  }

  void _syncAnimation() {
    if (widget.state is VoiceSearchListening) {
      if (!_pulse.isAnimating) _pulse.repeat();
    } else {
      _pulse
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isHot = state is VoiceSearchListening;
    final isProc = state is VoiceSearchProcessing;
    final ring = isHot ? scheme.error : scheme.primary;

    return Tooltip(
      message: switch (state) {
        VoiceSearchListening() => 'Dinleniyor — durdurmak icin dokun',
        VoiceSearchProcessing() => 'Isleniyor…',
        VoiceSearchPermissionDenied() => 'Mikrofon izni gerekli',
        VoiceSearchUnsupported() => 'Bu cihaz desteklenmiyor',
        VoiceSearchError() => 'Hata olustu — yeniden dene',
        VoiceSearchIdle() => 'Sesli arama',
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: state is VoiceSearchUnsupported ? null : widget.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (BuildContext context, Widget? _) {
              final t = _pulse.value;
              return SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    if (isHot)
                      // Outer pulsing ring — fades from full opacity
                      // to transparent across one cycle to draw the
                      // user's eye to "I'm listening".
                      Opacity(
                        opacity: 0.55 * (1 - t),
                        child: Container(
                          width: 36 + 18 * t,
                          height: 36 + 18 * t,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: ring, width: 2),
                          ),
                        ),
                      ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isHot
                            ? scheme.error.withValues(alpha: 0.18)
                            : Colors.transparent,
                        border: Border.all(
                          color: isHot
                              ? scheme.error
                              : scheme.onSurface.withValues(alpha: 0.65),
                          width: 1.4,
                        ),
                      ),
                      child: Icon(
                        isHot
                            ? Icons.mic_rounded
                            : Icons.mic_none_rounded,
                        size: 20,
                        color: isHot ? scheme.error : scheme.onSurface,
                      ),
                    ),
                    if (isProc)
                      const SizedBox(
                        width: 38,
                        height: 38,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Compact partial-transcript hint rendered just below the search bar
/// while the engine is listening. Cosmetic — gives the user real-time
/// feedback that the mic is hearing them.
class VoiceSearchPartialHint extends ConsumerWidget {
  const VoiceSearchPartialHint({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(voiceSearchControllerProvider);
    final partial = switch (state) {
      VoiceSearchListening(:final partial) => partial,
      VoiceSearchProcessing(:final partial) => partial,
      _ => '',
    };
    if (partial.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceS,
      ),
      color: theme.colorScheme.primary.withValues(alpha: 0.08),
      child: Text(
        '"$partial"',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.primary,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }
}
