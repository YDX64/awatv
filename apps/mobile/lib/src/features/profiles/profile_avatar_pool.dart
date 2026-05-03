import 'package:flutter/material.dart';

/// Streas avatar inventory ported 1:1 from `context/ProfileContext.tsx`.
///
/// 24 emoji and 12 colour swatches. The Streas reference has duplicate
/// `#E11D48` at indices 0 and 8; the spec asks the port to replace
/// index 8 with a fresh hue (`#FF5722`, orange-red) so the picker
/// always shows 12 distinct colours.
const List<String> kStreasAvatarEmojis = <String>[
  '🎭', '🎮', '🎵', '🎨',
  '🚀', '🌟', '🦋', '🐉',
  '🎪', '🌈', '🎯', '🏆',
  '🦁', '🐺', '🦊', '🐼',
  '🌊', '🔥', '⚡', '❄️',
  '🌙', '☀️', '🌴', '🎸',
];

/// 12-tone colour wheel for the avatar tile background. Index 8 is
/// `#FF5722` (orange-red) — replacing the duplicate Streas cherry so
/// every chip is visually distinct.
const List<Color> kStreasAvatarColors = <Color>[
  Color(0xFFE11D48), // 0 — cherry primary
  Color(0xFF8B5CF6), // 1 — violet
  Color(0xFFEC4899), // 2 — pink
  Color(0xFFEF4444), // 3 — red
  Color(0xFFF97316), // 4 — orange
  Color(0xFFEAB308), // 5 — amber
  Color(0xFF22C55E), // 6 — green
  Color(0xFF14B8A6), // 7 — teal
  Color(0xFFFF5722), // 8 — orange-red (was duplicate cherry; spec fix)
  Color(0xFF06B6D4), // 9 — cyan
  Color(0xFFA855F7), // 10 — purple
  Color(0xFFF43F5E), // 11 — rose
];

/// Closest matching index in [kStreasAvatarColors] for the given color.
/// Falls back to 0 (cherry) if no exact match — used when rehydrating
/// the picker from a legacy profile that stored a colour outside the
/// pool.
int avatarColorIndexFor(Color color) {
  final argb = color.toARGB32();
  for (var i = 0; i < kStreasAvatarColors.length; i++) {
    if (kStreasAvatarColors[i].toARGB32() == argb) return i;
  }
  return 0;
}

/// Closest matching index in [kStreasAvatarEmojis] for the given
/// emoji. Falls back to 0 when the persisted emoji is not in the pool
/// (older profiles created with ASCII glyphs like "TV").
int avatarEmojiIndexFor(String? emoji) {
  if (emoji == null || emoji.isEmpty) return 0;
  for (var i = 0; i < kStreasAvatarEmojis.length; i++) {
    if (kStreasAvatarEmojis[i] == emoji) return i;
  }
  return 0;
}
