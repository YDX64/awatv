import 'package:flutter/material.dart';

/// Where the subtitle strip sits relative to the player frame.
enum SubtitleOverlayPosition { top, bottom }

/// Floating subtitle strip rendered above the player surface.
///
/// Pure-UI widget — takes only primitives so it can live in the
/// design-system package without depending on `awatv_core`. The host
/// screen is expected to map its `SubtitleSettings` model to these
/// parameters before passing them in.
///
/// Multi-line cues are split on `\n` and stacked with 2px gap to
/// mirror Streas's RN behaviour. Uses [IgnorePointer] internally so
/// taps pass through to the player's gesture detector — the overlay
/// must never absorb taps that should reveal the controls.
class SubtitleOverlay extends StatelessWidget {
  const SubtitleOverlay({
    required this.text,
    this.fontSize = 16,
    this.color = Colors.white,
    this.backgroundColor = const Color(0x99000000),
    this.bold = false,
    this.position = SubtitleOverlayPosition.bottom,
    this.bottomOffset = 60,
    this.topOffset = 80,
    super.key,
  });

  /// Active cue text. When null or empty the widget renders nothing.
  /// Multi-line cues use `\n` as the line separator.
  final String? text;

  /// Subtitle font size in logical pixels (Streas presets: 13/16/20/26).
  final double fontSize;

  /// Foreground colour for the subtitle text.
  final Color color;

  /// Plate behind each line. Use [Colors.transparent] for the "none"
  /// preset; semi/solid map to alpha 0.6 / 0.92 in the spec.
  final Color backgroundColor;

  /// When true, lines render with FontWeight.w700 instead of w600.
  final bool bold;

  /// Where the strip sits relative to the parent stack.
  final SubtitleOverlayPosition position;

  /// Distance from the bottom of the parent stack when
  /// [position] is bottom. The host screen typically passes 60 in
  /// landscape and 8 in portrait so the strip sits above the
  /// progress bar.
  final double bottomOffset;

  /// Distance from the top of the parent stack when [position] is top.
  /// Defaults to 80 — clear of the top chrome on phones with a notch.
  final double topOffset;

  @override
  Widget build(BuildContext context) {
    final raw = text;
    if (raw == null || raw.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final lines = raw.split('\n');
    final fontWeight = bold ? FontWeight.w700 : FontWeight.w600;
    final isTop = position == SubtitleOverlayPosition.top;

    return Positioned(
      left: 0,
      right: 0,
      top: isTop ? topOffset : null,
      bottom: !isTop ? bottomOffset : null,
      child: IgnorePointer(
        // Pointer events must pass through to the gesture layer beneath.
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              for (int i = 0; i < lines.length; i++) ...<Widget>[
                if (i > 0) const SizedBox(height: 2),
                _SubtitleLine(
                  text: lines[i],
                  fontSize: fontSize,
                  color: color,
                  fontWeight: fontWeight,
                  bgColor: backgroundColor,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SubtitleLine extends StatelessWidget {
  const _SubtitleLine({
    required this.text,
    required this.fontSize,
    required this.color,
    required this.fontWeight,
    required this.bgColor,
  });

  final String text;
  final double fontSize;
  final Color color;
  final FontWeight fontWeight;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Rounded plate behind the text. When background is "none" the
      // alpha is 0 so the container is invisible but still defines
      // padding — keeps the type rhythm consistent across presets.
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: fontSize,
          color: color,
          fontWeight: fontWeight,
          letterSpacing: 0.2,
          height: 24 / fontSize,
          // Always-on text shadow for legibility against bright frames.
          shadows: const <Shadow>[
            Shadow(
              color: Color(0xE6000000),
              offset: Offset(1, 1),
              blurRadius: 3,
            ),
          ],
        ),
      ),
    );
  }
}
