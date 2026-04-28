import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/profiles/profile.dart';
import 'package:awatv_mobile/src/shared/profiles/profile_scoped_storage.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

/// Hive `prefs` keys.
const String _kProfilesListKey = 'profiles:list';
const String _kActiveProfileKey = 'profiles:active';

/// Default avatar palette — picked at random when the user creates a
/// profile and didn't manually choose a colour. Material-3 friendly.
const List<Color> kProfileAvatarPalette = <Color>[
  Color(0xFF6750A4),
  Color(0xFFE91E63),
  Color(0xFFE57373),
  Color(0xFFEF6C00),
  Color(0xFFF59E0B),
  Color(0xFF10B981),
  Color(0xFF14B8A6),
  Color(0xFF0EA5E9),
  Color(0xFF6366F1),
  Color(0xFF8B5CF6),
];

/// Single-place provider that yields the persisted profile list.
///
/// We cannot use `keepAlive: true` codegen here without `build_runner`,
/// so we use a manual [StreamProvider] that reads the Hive `prefs` box,
/// emits an initial value, and listens for further changes.
final profilesListProvider =
    StreamProvider<List<UserProfile>>((Ref ref) async* {
  final storage = ref.watch(awatvStorageProvider);
  final box = storage.prefsBox;

  List<UserProfile> read() {
    final raw = box.get(_kProfilesListKey);
    if (raw is! String || raw.isEmpty) return const <UserProfile>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList(growable: false);
    } on Object {
      return const <UserProfile>[];
    }
  }

  yield read();
  yield* box.watch(key: _kProfilesListKey).map((_) => read());
});

/// The active profile id — emits the id only. Watching this is cheap
/// enough that consumers can also use it as a "selected profile changed"
/// trigger to rebuild scoped state.
final activeProfileIdProvider = StreamProvider<String>((Ref ref) async* {
  final storage = ref.watch(awatvStorageProvider);
  final box = storage.prefsBox;

  String read() {
    final raw = box.get(_kActiveProfileKey);
    if (raw is String && raw.isNotEmpty) return raw;
    return ProfileScopedStorage.defaultProfileId;
  }

  yield read();
  yield* box.watch(key: _kActiveProfileKey).map((_) => read());
});

/// The full active profile — joins `profilesListProvider` with the
/// active id. Emits `null` only during the very first frame before the
/// default profile auto-creates.
final activeProfileProvider = Provider<UserProfile?>((Ref ref) {
  final list = ref.watch(profilesListProvider).valueOrNull ??
      const <UserProfile>[];
  final id =
      ref.watch(activeProfileIdProvider).valueOrNull ??
          ProfileScopedStorage.defaultProfileId;
  if (list.isEmpty) return null;
  for (final p in list) {
    if (p.id == id) return p;
  }
  // The persisted active id no longer exists (profile was deleted on
  // another device). Fall back to the first profile in the list.
  return list.first;
});

/// Imperative controller for create / update / delete / switch. Held
/// in a `Provider` because we don't need any internal state — every
/// mutation reads the current list straight from Hive.
final profileControllerProvider = Provider<ProfileController>((Ref ref) {
  return ProfileController(ref);
});

/// Thrown by [ProfileController.switchTo] when the caller-supplied PIN
/// did not match the target profile's stored hash.
class ProfilePinMismatchException implements Exception {
  const ProfilePinMismatchException();
  @override
  String toString() => 'ProfilePinMismatchException';
}

/// Imperative façade that owns CRUD on the profile list.
///
/// This is a plain class — Riverpod just gives every screen access to
/// the same instance. State lives in Hive; the providers above stream
/// changes back to listeners.
class ProfileController {
  ProfileController(this._ref);

  /// Re-export of the default-profile sentinel id so screens don't
  /// need to import [ProfileScopedStorage] just to compare against it.
  static String get defaultProfileSentinel =>
      ProfileScopedStorage.defaultProfileId;

  final Ref _ref;
  final Uuid _uuid = const Uuid();
  final Random _rng = Random.secure();

  AwatvStorage get _storage => _ref.read(awatvStorageProvider);

  /// Read the persisted list. Returns an empty list when no profiles
  /// have been created yet — call [bootstrapDefaultProfile] from boot to
  /// guarantee at least one profile exists.
  List<UserProfile> currentList() {
    final raw = _storage.prefsBox.get(_kProfilesListKey);
    if (raw is! String || raw.isEmpty) return const <UserProfile>[];
    try {
      final list = jsonDecode(raw) as List<dynamic>;
      return list
          .whereType<Map<String, dynamic>>()
          .map(UserProfile.fromJson)
          .toList(growable: false);
    } on Object {
      return const <UserProfile>[];
    }
  }

  String currentActiveId() {
    final raw = _storage.prefsBox.get(_kActiveProfileKey);
    if (raw is String && raw.isNotEmpty) return raw;
    return ProfileScopedStorage.defaultProfileId;
  }

  UserProfile? currentActive() {
    final list = currentList();
    if (list.isEmpty) return null;
    final id = currentActiveId();
    for (final p in list) {
      if (p.id == id) return p;
    }
    return list.first;
  }

  /// Called once on app boot before `runApp`. If no profiles exist yet,
  /// create a single "Ana Profil" that takes over the legacy
  /// favourites + history boxes (so users upgrading from a pre-profiles
  /// build see their data on the right profile).
  Future<UserProfile> bootstrapDefaultProfile() async {
    final list = currentList();
    if (list.isNotEmpty) {
      // Make sure the active id still resolves; otherwise fall back to
      // the first profile in the list.
      final activeId = currentActiveId();
      final found = list.any((UserProfile p) => p.id == activeId);
      if (!found) {
        await _persistActiveId(list.first.id);
      }
      // Open scoped boxes for the active profile so providers don't
      // throw on first access.
      await ProfileScopedStorage.openBoxesFor(currentActiveId());
      return currentActive()!;
    }
    final now = DateTime.now().toUtc();
    final profile = UserProfile(
      id: ProfileScopedStorage.defaultProfileId,
      name: 'Ana Profil',
      avatarColor: kProfileAvatarPalette.first,
      avatarEmoji: 'TV',
      createdAt: now,
      updatedAt: now,
    );
    await _persistList(<UserProfile>[profile]);
    await _persistActiveId(profile.id);
    await ProfileScopedStorage.openBoxesFor(profile.id);
    return profile;
  }

  /// Create a new profile. The caller is expected to have validated the
  /// fields (non-empty name, etc.).
  Future<UserProfile> createProfile({
    required String name,
    String? avatarEmoji,
    Color? avatarColor,
    bool isKids = false,
    bool requiresPin = false,
    String? pin,
  }) async {
    if (name.trim().isEmpty) {
      throw ArgumentError('Profile name cannot be empty.');
    }
    final now = DateTime.now().toUtc();
    final color = avatarColor ??
        kProfileAvatarPalette[_rng.nextInt(kProfileAvatarPalette.length)];
    String? hash;
    String? salt;
    if (requiresPin && pin != null && pin.isNotEmpty) {
      final pair = _hashPin(pin);
      salt = pair.salt;
      hash = pair.hash;
    }
    final profile = UserProfile(
      id: _uuid.v4(),
      name: name.trim(),
      avatarEmoji: avatarEmoji,
      avatarColor: color,
      isKids: isKids,
      requiresPin: requiresPin && hash != null,
      pinHash: hash,
      pinSalt: salt,
      createdAt: now,
      updatedAt: now,
    );
    final next = <UserProfile>[...currentList(), profile];
    await _persistList(next);
    await ProfileScopedStorage.openBoxesFor(profile.id);
    return profile;
  }

  /// Update an existing profile. Pass [pin] (with [requiresPin] true)
  /// to set a fresh PIN. Pass [clearPin] to remove an existing PIN.
  Future<UserProfile> updateProfile(
    String id, {
    String? name,
    String? avatarEmoji,
    bool clearAvatarEmoji = false,
    Color? avatarColor,
    bool? isKids,
    bool? requiresPin,
    String? pin,
    bool clearPin = false,
  }) async {
    final list = currentList();
    final idx = list.indexWhere((UserProfile p) => p.id == id);
    if (idx == -1) {
      throw StateError('Profile $id not found');
    }
    final existing = list[idx];
    String? newHash = existing.pinHash;
    String? newSalt = existing.pinSalt;
    var resolvedRequiresPin = requiresPin ?? existing.requiresPin;
    if (clearPin) {
      newHash = null;
      newSalt = null;
      resolvedRequiresPin = false;
    } else if (pin != null && pin.isNotEmpty) {
      final pair = _hashPin(pin);
      newSalt = pair.salt;
      newHash = pair.hash;
      resolvedRequiresPin = true;
    }
    final updated = existing.copyWith(
      name: name?.trim().isEmpty ?? true ? null : name!.trim(),
      avatarEmoji: avatarEmoji,
      clearAvatarEmoji: clearAvatarEmoji,
      avatarColor: avatarColor,
      isKids: isKids,
      requiresPin: resolvedRequiresPin && newHash != null,
      pinHash: clearPin ? null : newHash,
      pinSalt: clearPin ? null : newSalt,
      clearPin: clearPin,
      updatedAt: DateTime.now().toUtc(),
    );
    final next = List<UserProfile>.from(list)..[idx] = updated;
    await _persistList(next);
    return updated;
  }

  /// Delete a profile. The default profile cannot be deleted because it
  /// owns the legacy un-scoped Hive boxes. If the deleted profile was
  /// active, the next available profile becomes active.
  Future<void> deleteProfile(String id) async {
    if (id == ProfileScopedStorage.defaultProfileId) {
      throw StateError('The default profile cannot be deleted.');
    }
    final list = currentList();
    final next = list.where((UserProfile p) => p.id != id).toList();
    if (next.length == list.length) return; // already gone
    if (next.isEmpty) {
      // Should never happen because we always keep the default profile,
      // but be defensive: re-bootstrap.
      await _persistList(const <UserProfile>[]);
      await bootstrapDefaultProfile();
      return;
    }
    await _persistList(next);
    if (currentActiveId() == id) {
      await switchTo(next.first.id, skipPin: true);
    }
    await ProfileScopedStorage.deleteBoxesFor(id);
  }

  /// Switch the active profile. If the target profile [requiresPin],
  /// the caller must pass [pin] — wrong / missing PIN throws
  /// [ProfilePinMismatchException].
  ///
  /// [skipPin] is set internally during deletion fall-through and on
  /// boot; UI screens never set it.
  Future<UserProfile> switchTo(
    String id, {
    String? pin,
    bool skipPin = false,
  }) async {
    final list = currentList();
    final target = list.firstWhere(
      (UserProfile p) => p.id == id,
      orElse: () => throw StateError('Profile $id not found'),
    );
    if (!skipPin && target.requiresPin && target.hasPin) {
      if (pin == null || !verifyPin(target, pin)) {
        throw const ProfilePinMismatchException();
      }
    }
    await _persistActiveId(target.id);
    await ProfileScopedStorage.openBoxesFor(target.id);
    return target;
  }

  /// Set or change a profile's PIN. If [requiresPin] is false the
  /// stored PIN is cleared.
  Future<UserProfile> setPin(
    String id, {
    required String pin,
    bool requiresPin = true,
  }) async {
    return updateProfile(
      id,
      pin: pin,
      requiresPin: requiresPin,
    );
  }

  /// Verify a candidate PIN against the profile's stored hash. Pure
  /// function — exposed for the picker screen so it can show the
  /// "wrong PIN" error inline before calling [switchTo].
  bool verifyPin(UserProfile profile, String candidate) {
    final hash = profile.pinHash;
    final salt = profile.pinSalt;
    if (hash == null || salt == null) return false;
    final computed = _digest(salt: salt, pin: candidate);
    return computed == hash;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _persistList(List<UserProfile> list) async {
    final encoded =
        jsonEncode(list.map((UserProfile p) => p.toJson()).toList());
    await _storage.prefsBox.put(_kProfilesListKey, encoded);
  }

  Future<void> _persistActiveId(String id) async {
    await _storage.prefsBox.put(_kActiveProfileKey, id);
  }

  ({String hash, String salt}) _hashPin(String pin) {
    final salt = _generateSalt();
    final digest = _digest(salt: salt, pin: pin);
    return (hash: digest, salt: salt);
  }

  String _generateSalt() {
    final bytes = List<int>.generate(
      ProfilePinHasher.saltLengthBytes,
      (_) => _rng.nextInt(256),
    );
    return base64UrlEncode(bytes);
  }

  String _digest({required String salt, required String pin}) {
    final bytes = utf8.encode('$salt::$pin');
    return sha256.convert(bytes).toString();
  }
}
