import 'dart:async';

import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// Streas-style debounced search bar.
///
/// Anatomy (per `/tmp/Streas/artifacts/iptv-app/components/SearchBar.tsx`):
///
/// * Horizontal pill — search icon, [TextField], optional clear button,
///   optional voice button.
/// * `paddingHorizontal: 14`, `paddingVertical: 11`, `borderRadius: 10`,
///   1px outline border, 10px gap.
/// * Background lightens on focus (Streas RN has no focus animation —
///   we add this so the field reads as interactive on hover/focus).
///
/// Typing is debounced (default 300ms) before [onChanged] is invoked so
/// callers don't hammer the search service on every keystroke. Streas RN
/// debounces in the caller; the Flutter port pulls the timer in here so
/// callers don't have to reinvent it.
///
/// Pass [onVoice] to surface a microphone trailing icon — typically the
/// caller wires this to the voice search feature (`apps/mobile/lib/src/
/// features/voice_search`).
class StreasSearchBar extends StatefulWidget {
  const StreasSearchBar({
    this.controller,
    this.placeholder = 'Search shows, movies, channels...',
    this.onChanged,
    this.onSubmitted,
    this.debounce = const Duration(milliseconds: 300),
    this.onVoice,
    this.autofocus = false,
    this.focusNode,
    super.key,
  });

  /// Optional external controller. When null, an internal one is created
  /// and disposed.
  final TextEditingController? controller;

  /// Placeholder text. Defaults to the Streas string.
  final String placeholder;

  /// Debounced text-change callback. Fires `debounce` after the last edit.
  final ValueChanged<String>? onChanged;

  /// Fires immediately when the user hits the keyboard return key
  /// (`returnKeyType: 'search'` in Streas).
  final ValueChanged<String>? onSubmitted;

  /// Debounce window. Set to `Duration.zero` to disable.
  final Duration debounce;

  /// Voice button callback. When null the mic button is hidden.
  final VoidCallback? onVoice;

  /// Auto-focus the field on first mount.
  final bool autofocus;

  /// Optional focus node for parent control of focus state.
  final FocusNode? focusNode;

  @override
  State<StreasSearchBar> createState() => _StreasSearchBarState();
}

class _StreasSearchBarState extends State<StreasSearchBar> {
  TextEditingController? _internalController;
  FocusNode? _internalFocusNode;
  Timer? _debounceTimer;
  bool _hasText = false;
  bool _focused = false;

  TextEditingController get _controller =>
      widget.controller ?? (_internalController ??= TextEditingController());

  FocusNode get _focusNode =>
      widget.focusNode ?? (_internalFocusNode ??= FocusNode());

  @override
  void initState() {
    super.initState();
    _hasText = _controller.text.isNotEmpty;
    _controller.addListener(_handleTextChanged);
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant StreasSearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_handleTextChanged);
      _internalController?.removeListener(_handleTextChanged);
      _controller.addListener(_handleTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode?.removeListener(_handleFocusChanged);
      _internalFocusNode?.removeListener(_handleFocusChanged);
      _focusNode.addListener(_handleFocusChanged);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _controller.removeListener(_handleTextChanged);
    _focusNode.removeListener(_handleFocusChanged);
    _internalController?.dispose();
    _internalFocusNode?.dispose();
    super.dispose();
  }

  void _handleTextChanged() {
    final value = _controller.text;
    final hasText = value.isNotEmpty;
    if (hasText != _hasText) {
      setState(() => _hasText = hasText);
    }
    if (widget.onChanged == null) return;

    _debounceTimer?.cancel();
    if (widget.debounce == Duration.zero) {
      widget.onChanged!(value);
    } else {
      _debounceTimer = Timer(widget.debounce, () {
        if (!mounted) return;
        widget.onChanged!(value);
      });
    }
  }

  void _handleFocusChanged() {
    setState(() => _focused = _focusNode.hasFocus);
  }

  void _clear() {
    _controller.clear();
    // Make sure the debounced callback fires immediately on clear so the
    // results list resets without lag.
    _debounceTimer?.cancel();
    widget.onChanged?.call('');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.5);

    final baseColor = scheme.surface;
    final focusedColor = Color.lerp(baseColor, scheme.surfaceContainerHigh, 1)
        ?? baseColor;
    final containerColor = _focused ? focusedColor : baseColor;
    final borderColor = _focused
        ? scheme.primary.withValues(alpha: 0.6)
        : scheme.outlineVariant;

    return AnimatedContainer(
      duration: DesignTokens.motionFast,
      curve: Curves.easeOut,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: containerColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.search, size: 18, color: muted),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: widget.autofocus,
              onSubmitted: widget.onSubmitted,
              autocorrect: false,
              textInputAction: TextInputAction.search,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurface,
                fontSize: 14,
              ),
              cursorColor: scheme.primary,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.placeholder,
                hintStyle: theme.textTheme.bodyMedium?.copyWith(
                  fontSize: 14,
                  color: muted,
                ),
              ),
            ),
          ),
          if (_hasText) ...<Widget>[
            const SizedBox(width: 8),
            _IconAction(
              icon: Icons.cancel,
              tooltip: 'Clear',
              onPressed: _clear,
              color: muted,
              size: 16,
            ),
          ],
          if (widget.onVoice != null) ...<Widget>[
            const SizedBox(width: 8),
            _IconAction(
              icon: Icons.mic,
              tooltip: 'Voice search',
              onPressed: widget.onVoice!,
              color: muted,
              size: 18,
            ),
          ],
        ],
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    required this.color,
    required this.size,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      child: InkResponse(
        onTap: onPressed,
        radius: 18,
        child: Tooltip(
          message: tooltip,
          child: Icon(icon, size: size, color: color),
        ),
      ),
    );
  }
}
