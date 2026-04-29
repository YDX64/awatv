import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Full-screen overlay shown after 4 hours of continuous playback.
///
/// Two buttons:
///   * "Evet, izliyorum" — resumes playback and resets the 4h counter.
///   * "Hayir, kapat" — keeps the player paused and pops the route.
///
/// The tracker (see [stillWatchingProvider] in `sleep_timer.dart`)
/// owns the state machine; this widget is the visual half. The player
/// screen wires both: when the tracker flips `shouldPrompt` true the
/// player pauses and renders this overlay over the controls.
class AreYouStillWatchingOverlay extends StatelessWidget {
  const AreYouStillWatchingOverlay({
    required this.onContinue,
    required this.onExit,
    super.key,
  });

  final VoidCallback onContinue;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(DesignTokens.spaceL),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.45),
                        width: 2,
                      ),
                    ),
                    child: Icon(
                      Icons.help_outline_rounded,
                      size: 48,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  const Text(
                    'Hala izliyor musun?',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  const Text(
                    '4 saattir kesintisiz oynatim suruyor. '
                    'Ekrandan ayrildiysan, sana ozel olarak duraklattik.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXl),
                  FilledButton.icon(
                    onPressed: onContinue,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Evet, izliyorum'),
                  ),
                  const SizedBox(height: DesignTokens.spaceS),
                  OutlinedButton.icon(
                    onPressed: onExit,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: BorderSide(
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('Hayir, kapat'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
