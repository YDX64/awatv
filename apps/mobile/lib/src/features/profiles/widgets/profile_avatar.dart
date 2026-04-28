import 'package:awatv_mobile/src/shared/profiles/profile.dart';
import 'package:flutter/material.dart';

/// Round avatar tile — coloured circle with the emoji or the first
/// letter of the profile name.
///
/// We deliberately avoid network avatars here: profiles are local-only
/// state, so a free Material Symbols glyph or emoji keeps the boot
/// path zero-network and makes the picker render instantly.
class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    required this.profile,
    this.size = 56,
    super.key,
  });

  final UserProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final emoji = profile.avatarEmoji;
    final fallback = profile.name.isEmpty
        ? '?'
        : profile.name.substring(0, 1).toUpperCase();
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: profile.avatarColor,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: profile.avatarColor.withValues(alpha: 0.35),
            blurRadius: size * 0.3,
            spreadRadius: 1,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        emoji != null && emoji.isNotEmpty ? emoji : fallback,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          height: 1,
        ),
      ),
    );
  }
}
