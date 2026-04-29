import 'package:awatv_mobile/src/features/player/player_screen.dart' show PlayerScreen;
import 'package:awatv_mobile/src/shared/parental/parental_controller.dart';
import 'package:awatv_mobile/src/shared/parental/parental_gate.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Full-bleed lock overlay used by [PlayerScreen] when the active
/// profile is forbidden from watching the current content.
///
/// Renders a glass-style PIN entry. On success the parental
/// controller flips into "session unlocked" mode for ~30 minutes and
/// the host calls [onUnlocked] so it can drop the overlay and resume
/// playback.
class ParentalLockOverlay extends ConsumerStatefulWidget {
  const ParentalLockOverlay({
    required this.outcome,
    required this.onUnlocked,
    required this.onCancel,
    super.key,
  });

  final ParentalGateOutcome outcome;
  final VoidCallback onUnlocked;
  final VoidCallback onCancel;

  @override
  ConsumerState<ParentalLockOverlay> createState() =>
      _ParentalLockOverlayState();
}

class _ParentalLockOverlayState extends ConsumerState<ParentalLockOverlay> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final pin = _ctrl.text.trim();
    if (pin.isEmpty) {
      setState(() => _error = 'PIN gerekli');
      return;
    }
    setState(() => _busy = true);
    final controller = ref.read(parentalControllerProvider);
    try {
      final ok = await controller.tryUnlock(pin);
      if (!mounted) return;
      if (ok) {
        widget.onUnlocked();
        return;
      }
      setState(() {
        _error = 'Yanlış PIN';
        _busy = false;
      });
      _ctrl.clear();
    } on ParentalLockedOutException catch (e) {
      if (!mounted) return;
      final remaining = e.until.difference(DateTime.now().toUtc());
      final mins = remaining.inMinutes.clamp(1, 60);
      setState(() {
        _error = 'Çok fazla deneme. $mins dk sonra tekrar dene.';
        _busy = false;
      });
    } on ParentalPinNotSetException {
      if (!mounted) return;
      // Pin has been cleared while the overlay was open — let the
      // host close it.
      widget.onUnlocked();
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Hata: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.black.withValues(alpha: 0.85),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceL),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.error.withValues(alpha: 0.15),
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 32,
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                Text(
                  _titleFor(widget.outcome),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceS),
                Text(
                  _subtitleFor(widget.outcome),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: DesignTokens.spaceL),
                TextField(
                  controller: _ctrl,
                  focusNode: _focus,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                  ],
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    letterSpacing: 12,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    filled: true,
                    fillColor: Colors.white.withValues(alpha: 0.08),
                    border: const OutlineInputBorder(
                      borderSide: BorderSide.none,
                    ),
                    errorText: _error,
                    errorStyle: TextStyle(
                      color: theme.colorScheme.error,
                    ),
                    hintText: '••••',
                    hintStyle: TextStyle(
                      color: Colors.white.withValues(alpha: 0.35),
                      letterSpacing: 8,
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: DesignTokens.spaceM),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: widget.onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.4),
                          ),
                        ),
                        child: const Text('Geri'),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.spaceM),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : _submit,
                        child: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Aç'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String _titleFor(ParentalGateOutcome outcome) {
    switch (outcome) {
      case ParentalGateOutcome.blockedByRating:
        return 'Yaş kısıtlaması';
      case ParentalGateOutcome.blockedByCategory:
        return 'Engellenen kategori';
      case ParentalGateOutcome.blockedByBedtime:
        return 'Yatma saati';
      case ParentalGateOutcome.allowed:
        return 'Kilit';
    }
  }

  static String _subtitleFor(ParentalGateOutcome outcome) {
    switch (outcome) {
      case ParentalGateOutcome.blockedByRating:
        return 'Bu içerik bu profil için izin verilen yaş seviyesinin '
            "üstünde. Devam etmek için ebeveyn PIN'i gir.";
      case ParentalGateOutcome.blockedByCategory:
        return 'Bu kategori bu profil için engellenmiş. '
            'PIN ile geçici olarak açabilirsin.';
      case ParentalGateOutcome.blockedByBedtime:
        return 'Çocuk profillerinde yatma saatinden sonra '
            'oynatma engelli. PIN ile bir kez aç.';
      case ParentalGateOutcome.allowed:
        return 'Devam etmek için PIN gir.';
    }
  }
}
