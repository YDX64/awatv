import 'package:flutter/material.dart';

/// A single user-profile on this device.
///
/// Profiles scope favourites + history + parental settings via the
/// per-profile Hive box names exposed by [ProfileScopedStorage]. They
/// are deliberately a flat, JSON-serialisable struct (no Freezed) so the
/// list can live in a single Hive `prefs:profiles:list` entry without
/// pulling new packages or codegen into the mobile app.
@immutable
class UserProfile {
  const UserProfile({
    required this.id,
    required this.name,
    required this.avatarColor,
    required this.createdAt,
    required this.updatedAt,
    this.avatarEmoji,
    this.isKids = false,
    this.requiresPin = false,
    this.pinHash,
    this.pinSalt,
  });

  /// UUID — stable for the lifetime of the profile, never reused.
  final String id;

  /// User-given display name (e.g. "Anne", "Cocuk").
  final String name;

  /// Optional emoji avatar — keeps avatars zero-cost (no image upload).
  final String? avatarEmoji;

  /// Coloured tile background used in the picker grid.
  final Color avatarColor;

  /// Kids flag — used by the parental gate to enforce maxRating.
  final bool isKids;

  /// When `true`, switching INTO this profile demands the PIN.
  final bool requiresPin;

  /// SHA-256 hex digest of the PIN. `null` until the user sets one.
  final String? pinHash;

  /// Random salt used when hashing the PIN. Re-used on every verify.
  final String? pinSalt;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get hasPin => pinHash != null && pinHash!.isNotEmpty;

  UserProfile copyWith({
    String? id,
    String? name,
    String? avatarEmoji,
    bool clearAvatarEmoji = false,
    Color? avatarColor,
    bool? isKids,
    bool? requiresPin,
    String? pinHash,
    String? pinSalt,
    bool clearPin = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarEmoji: clearAvatarEmoji ? null : (avatarEmoji ?? this.avatarEmoji),
      avatarColor: avatarColor ?? this.avatarColor,
      isKids: isKids ?? this.isKids,
      requiresPin: requiresPin ?? this.requiresPin,
      pinHash: clearPin ? null : (pinHash ?? this.pinHash),
      pinSalt: clearPin ? null : (pinSalt ?? this.pinSalt),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'avatarEmoji': avatarEmoji,
        // Persist the ARGB int — Color is not JSON natively. We wrap
        // through the ARGB getter so theme-driven Material colours
        // serialise round-trippably.
        'avatarColor': avatarColor.toARGB32(),
        'isKids': isKids,
        'requiresPin': requiresPin,
        'pinHash': pinHash,
        'pinSalt': pinSalt,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final colorRaw = json['avatarColor'];
    final colorInt = colorRaw is int
        ? colorRaw
        : (colorRaw is num ? colorRaw.toInt() : 0xFF6750A4);
    return UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      avatarEmoji: json['avatarEmoji'] as String?,
      avatarColor: Color(colorInt),
      isKids: json['isKids'] as bool? ?? false,
      requiresPin: json['requiresPin'] as bool? ?? false,
      pinHash: json['pinHash'] as String?,
      pinSalt: json['pinSalt'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      updatedAt: DateTime.parse(json['updatedAt'] as String).toUtc(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UserProfile &&
      other.id == id &&
      other.name == name &&
      other.avatarEmoji == avatarEmoji &&
      other.avatarColor.toARGB32() == avatarColor.toARGB32() &&
      other.isKids == isKids &&
      other.requiresPin == requiresPin &&
      other.pinHash == pinHash &&
      other.pinSalt == pinSalt &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        avatarEmoji,
        avatarColor.toARGB32(),
        isKids,
        requiresPin,
        pinHash,
        pinSalt,
        createdAt,
        updatedAt,
      );
}

/// PIN hashing helpers — kept on the model file because they are
/// used both by the controller (when setting a pin) and the parental
/// gate (when verifying).
///
/// We use the project's existing `crypto` dependency: SHA-256 with a
/// 16-byte random salt per PIN. The salt is stored alongside the hash
/// so verification is deterministic.
class ProfilePinHasher {
  const ProfilePinHasher._();

  /// Length of the random salt in bytes. 16 bytes (~128 bits) gives
  /// plenty of headroom against rainbow-table attacks while staying
  /// short enough to be readable when dumping prefs.
  static const int saltLengthBytes = 16;
}
