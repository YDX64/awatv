import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// 4-digit PIN numpad used by the profile picker (PIN modal) and add /
/// edit profile screens.
///
/// Anatomy (per `/tmp/Streas/artifacts/iptv-app/app/add-profile.tsx`):
///
/// * Four dot indicators above the keypad — filled cherry when entered,
///   muted with a 1px outline otherwise.
/// * 3×4 grid of round-rect buttons: `1 2 3 / 4 5 6 / 7 8 9 / · 0 ⌫`.
///   The bottom-left slot is empty (Streas renders it transparent).
/// * Optional eye icon to mask/unmask the entered digits as plain text
///   beneath the dots.
///
/// [onComplete] fires once when the 4th digit is entered. The widget does
/// **not** clear itself — the caller decides whether to advance the flow
/// or reset the controller via [controller].
class StreasPinNumpad extends StatefulWidget {
  const StreasPinNumpad({
    this.controller,
    this.onChanged,
    this.onComplete,
    this.length = 4,
    this.allowReveal = true,
    this.label,
    this.errorText,
    super.key,
  });

  /// Optional controller exposing the current digit string. Disposed by
  /// the caller; if null, an internal one is created.
  final TextEditingController? controller;

  /// Fires on every digit add/remove with the current PIN string.
  final ValueChanged<String>? onChanged;

  /// Fires once when the entered string reaches [length] digits.
  final ValueChanged<String>? onComplete;

  /// Total PIN length. Streas uses 4. Keep small (3-6) for layout reasons.
  final int length;

  /// Whether to surface the eye icon that toggles `••••` ↔ `1234`.
  final bool allowReveal;

  /// Optional caption above the dots ("Limit access to this profile…").
  final String? label;

  /// Error caption shown beneath the dots when set (cherry colour).
  final String? errorText;

  @override
  State<StreasPinNumpad> createState() => _StreasPinNumpadState();
}

class _StreasPinNumpadState extends State<StreasPinNumpad> {
  TextEditingController? _internalController;
  bool _revealed = false;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  @override
  void initState() {
    super.initState();
    _controller.addListener(_handle);
  }

  @override
  void didUpdateWidget(covariant StreasPinNumpad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handle);
      _internalController?.removeListener(_handle);
      _controller.addListener(_handle);
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handle);
    _internalController?.dispose();
    super.dispose();
  }

  void _handle() {
    setState(() {});
    widget.onChanged?.call(_controller.text);
    if (_controller.text.length == widget.length) {
      widget.onComplete?.call(_controller.text);
    }
  }

  void _push(String digit) {
    if (_controller.text.length >= widget.length) return;
    _controller.text = '${_controller.text}$digit';
  }

  void _pop() {
    final value = _controller.text;
    if (value.isEmpty) return;
    _controller.text = value.substring(0, value.length - 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final value = _controller.text;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (widget.label != null && widget.label!.isNotEmpty) ...<Widget>[
          Text(
            widget.label!,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 12),
        ],
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (int i = 0; i < widget.length; i++) ...<Widget>[
              if (i > 0) const SizedBox(width: 14),
              _PinDot(
                filled: i < value.length,
                primary: scheme.primary,
                outline: scheme.onSurface.withValues(alpha: 0.3),
                muted: scheme.onSurface.withValues(alpha: 0.2),
              ),
            ],
          ],
        ),
        if (widget.allowReveal) ...<Widget>[
          const SizedBox(height: 8),
          InkResponse(
            onTap: () => setState(() => _revealed = !_revealed),
            radius: 18,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    _revealed ? Icons.visibility_off : Icons.visibility,
                    size: 14,
                    color: scheme.onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _revealed
                        ? (value.isEmpty ? '----' : value.padRight(widget.length, '-'))
                        : 'Show',
                    style: TextStyle(
                      fontSize: 12,
                      letterSpacing: _revealed ? 4 : 0,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (widget.errorText != null && widget.errorText!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 6),
          Text(
            widget.errorText!,
            style: TextStyle(
              fontSize: 12,
              color: scheme.error,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          width: 240,
          child: GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 1.2,
            children: <Widget>[
              for (int n = 1; n <= 9; n++)
                _NumKey(label: '$n', onTap: () => _push('$n')),
              const SizedBox.shrink(),
              _NumKey(label: '0', onTap: () => _push('0')),
              _NumKey(
                icon: Icons.backspace_outlined,
                onTap: _pop,
                tooltip: 'Delete',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _PinDot extends StatelessWidget {
  const _PinDot({
    required this.filled,
    required this.primary,
    required this.outline,
    required this.muted,
  });
  final bool filled;
  final Color primary;
  final Color outline;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: DesignTokens.motionFast,
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: filled ? primary : muted,
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: outline),
      ),
    );
  }
}

class _NumKey extends StatefulWidget {
  const _NumKey({required this.onTap, this.label, this.icon, this.tooltip});

  final String? label;
  final IconData? icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<_NumKey> createState() => _NumKeyState();
}

class _NumKeyState extends State<_NumKey>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press = AnimationController(
    vsync: this,
    duration: DesignTokens.motionFast,
  );

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final child = AnimatedBuilder(
      animation: _press,
      builder: (BuildContext _, Widget? __) {
        final t = _press.value;
        return Transform.scale(
          scale: 1 - 0.04 * t,
          child: Opacity(opacity: 1 - 0.2 * t, child: __),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: scheme.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: widget.icon != null
            ? Icon(widget.icon, size: 22, color: scheme.onSurface)
            : Text(
                widget.label!,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w400,
                  color: scheme.onSurface,
                ),
              ),
      ),
    );

    return Semantics(
      button: true,
      label: widget.tooltip ?? widget.label ?? '',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _press.forward(),
        onTapUp: (_) => _press.reverse(),
        onTapCancel: () => _press.reverse(),
        onTap: widget.onTap,
        child: child,
      ),
    );
  }
}
