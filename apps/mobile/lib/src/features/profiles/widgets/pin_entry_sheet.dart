import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Modal that asks for a PIN. Returns the entered string on success or
/// `null` when the user dismissed without confirming.
///
/// Used in two places:
///   * profile picker — verifying a per-profile lock,
///   * parental gate — verifying the device-wide parental PIN.
///
/// The optional [validator] runs synchronously after the user taps
/// "Onayla" and lets the caller surface a "Yanlış PIN" message
/// without closing the sheet. Returning `null` from the validator
/// signals success and pops the sheet.
class PinEntrySheet extends StatefulWidget {
  const PinEntrySheet({
    required this.title,
    required this.subtitle,
    this.validator,
    this.minLength = 4,
    this.maxLength = 6,
    super.key,
  });

  final String title;
  final String subtitle;
  final String? Function(String pin)? validator;
  final int minLength;
  final int maxLength;

  /// Convenience opener.
  static Future<String?> show(
    BuildContext context, {
    required String title,
    required String subtitle,
    String? Function(String pin)? validator,
    int minLength = 4,
    int maxLength = 6,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetCtx) => PinEntrySheet(
        title: title,
        subtitle: subtitle,
        validator: validator,
        minLength: minLength,
        maxLength: maxLength,
      ),
    );
  }

  @override
  State<PinEntrySheet> createState() => _PinEntrySheetState();
}

class _PinEntrySheetState extends State<PinEntrySheet> {
  final TextEditingController _ctrl = TextEditingController();
  final FocusNode _focus = FocusNode();
  String? _error;
  bool _obscure = true;

  @override
  void initState() {
    super.initState();
    // Focus the field so the keyboard surfaces immediately.
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

  void _submit() {
    final raw = _ctrl.text.trim();
    if (raw.length < widget.minLength) {
      setState(() => _error = 'En az ${widget.minLength} hane gerekli');
      return;
    }
    final v = widget.validator;
    if (v != null) {
      final err = v(raw);
      if (err != null) {
        setState(() => _error = err);
        _ctrl.clear();
        return;
      }
    }
    Navigator.of(context).pop(raw);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.of(context).viewInsets;
    return AnimatedPadding(
      duration: DesignTokens.motionFast,
      curve: DesignTokens.motionStandard,
      padding: EdgeInsets.only(bottom: viewInsets.bottom),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(DesignTokens.radiusXL),
        ),
        child: ColoredBox(
          color: scheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.spaceL,
                DesignTokens.spaceM,
                DesignTokens.spaceL,
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
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: scheme.onSurface.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: DesignTokens.spaceXs),
                  Text(
                    widget.subtitle,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.75),
                        ),
                  ),
                  const SizedBox(height: DesignTokens.spaceL),
                  TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    keyboardType: TextInputType.number,
                    obscureText: _obscure,
                    autofocus: true,
                    maxLength: widget.maxLength,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.digitsOnly,
                    ],
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 28,
                      letterSpacing: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      border: const OutlineInputBorder(),
                      errorText: _error,
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                  const SizedBox(height: DesignTokens.spaceM),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const SizedBox(width: DesignTokens.spaceM),
                      Expanded(
                        child: FilledButton(
                          onPressed: _submit,
                          child: const Text('Onayla'),
                        ),
                      ),
                    ],
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
