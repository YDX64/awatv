import 'dart:convert';
import 'dart:math';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/parental/parental_settings.dart';
import 'package:awatv_mobile/src/shared/profiles/profile.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

const String _kParentalSettingsKey = 'parental:settings';
const String _kParentalLockoutKey = 'parental:lockoutUntil';
const String _kParentalFailedAttemptsKey = 'parental:failedAttempts';
const String _kParentalSessionUnlockKey = 'parental:sessionUnlockUntil';

/// Live snapshot of [ParentalSettings] from Hive `prefs`. UI screens
/// watch this provider; mutations go through [parentalControllerProvider].
final parentalSettingsProvider =
    StreamProvider<ParentalSettings>((Ref ref) async* {
  final storage = ref.watch(awatvStorageProvider);
  final box = storage.prefsBox;

  ParentalSettings read() {
    final raw = box.get(_kParentalSettingsKey);
    if (raw is! String || raw.isEmpty) return const ParentalSettings();
    try {
      return ParentalSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const ParentalSettings();
    }
  }

  yield read();
  yield* box.watch(key: _kParentalSettingsKey).map((_) => read());
});

final parentalControllerProvider = Provider<ParentalController>((Ref ref) {
  return ParentalController(ref);
});

/// Brute-force lockout spec — 5 wrong PINs lock the gate for 10
/// minutes. Failed attempts are kept across app restarts via
/// [_kParentalFailedAttemptsKey].
class ParentalLockoutSpec {
  const ParentalLockoutSpec._();

  static const int maxAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 10);

  /// How long a successful PIN unlocks playback for the active session.
  /// Avoids the parent having to re-enter the PIN every couple of
  /// minutes when their kid is still in the same chair.
  static const Duration sessionUnlockDuration = Duration(minutes: 30);
}

class ParentalPinNotSetException implements Exception {
  const ParentalPinNotSetException();
}

class ParentalLockedOutException implements Exception {
  const ParentalLockedOutException(this.until);
  final DateTime until;
}

/// Imperative façade around parental settings + the lock-out counter.
class ParentalController {
  ParentalController(this._ref);

  final Ref _ref;
  final Random _rng = Random.secure();

  AwatvStorage get _storage => _ref.read(awatvStorageProvider);

  ParentalSettings current() {
    final raw = _storage.prefsBox.get(_kParentalSettingsKey);
    if (raw is! String || raw.isEmpty) return const ParentalSettings();
    try {
      return ParentalSettings.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on Object {
      return const ParentalSettings();
    }
  }

  /// Update a subset of fields. Returns the new settings so the screen
  /// can render an optimistic update without a stream round-trip.
  Future<ParentalSettings> update({
    bool? enabled,
    int? maxRating,
    List<String>? blockedCategories,
    Duration? dailyWatchLimit,
    int? bedtimeHour,
    int? bedtimeMinute,
    bool clearBedtime = false,
  }) async {
    final current = this.current();
    final next = current.copyWith(
      enabled: enabled,
      maxRating: maxRating,
      blockedCategories: blockedCategories,
      dailyWatchLimit: dailyWatchLimit,
      bedtimeHour: bedtimeHour,
      bedtimeMinute: bedtimeMinute,
      clearBedtime: clearBedtime,
    );
    await _persist(next);
    return next;
  }

  /// Set or replace the parental PIN. Pass [oldPin] to verify when an
  /// existing PIN is in place; throws [ProfilePinMismatchException]-like
  /// behaviour by returning false. The first PIN can be set without
  /// [oldPin].
  Future<bool> setPin({
    required String pin,
    String? oldPin,
  }) async {
    if (pin.length < 4 || pin.length > 6) {
      throw ArgumentError('PIN must be 4-6 digits.');
    }
    final current = this.current();
    if (current.hasPin) {
      if (oldPin == null || !verifyPin(oldPin, current)) return false;
    }
    final salt = _generateSalt();
    final hash = _digest(salt: salt, pin: pin);
    final next = current.copyWith(
      pinHash: hash,
      pinSalt: salt,
      enabled: current.enabled || !current.hasPin,
    );
    await _persist(next);
    await _resetAttempts();
    return true;
  }

  /// Clear the PIN and disable parental controls. Requires the current
  /// PIN to authorise the change — returns false on mismatch.
  Future<bool> clearAll({required String currentPin}) async {
    final current = this.current();
    if (!current.hasPin) {
      // Nothing to clear; just turn the gate off.
      await _persist(const ParentalSettings());
      return true;
    }
    if (!verifyPin(currentPin, current)) return false;
    await _persist(const ParentalSettings());
    await _resetAttempts();
    return true;
  }

  /// Verify a candidate PIN. Tracks the failed-attempt counter — when
  /// it crosses [ParentalLockoutSpec.maxAttempts] the lock-out window
  /// is set and subsequent calls return false until the window expires.
  Future<bool> tryUnlock(String pin) async {
    final current = this.current();
    if (!current.hasPin) throw const ParentalPinNotSetException();
    final lockoutUntil = _readLockoutUntil();
    final now = DateTime.now().toUtc();
    if (lockoutUntil != null && lockoutUntil.isAfter(now)) {
      throw ParentalLockedOutException(lockoutUntil);
    }
    final ok = verifyPin(pin, current);
    if (ok) {
      await _resetAttempts();
      await _markSessionUnlocked();
      return true;
    }
    final attempts = _readAttempts() + 1;
    if (attempts >= ParentalLockoutSpec.maxAttempts) {
      final until = now.add(ParentalLockoutSpec.lockoutDuration);
      await _writeLockoutUntil(until);
      await _writeAttempts(0);
    } else {
      await _writeAttempts(attempts);
    }
    return false;
  }

  /// Synchronous PIN check — used by guard widgets that already have
  /// access to the [ParentalSettings] snapshot. Does *not* update the
  /// failed-attempt counter; use [tryUnlock] from interactive paths.
  bool verifyPin(String candidate, ParentalSettings settings) {
    final hash = settings.pinHash;
    final salt = settings.pinSalt;
    if (hash == null || salt == null) return false;
    return _digest(salt: salt, pin: candidate) == hash;
  }

  /// Returns true while the current session is allowed to bypass the
  /// rating gate (set after a successful PIN). The window survives
  /// process restarts via Hive persistence.
  bool isSessionUnlocked() {
    final raw = _storage.prefsBox.get(_kParentalSessionUnlockKey);
    if (raw is! String) return false;
    final until = DateTime.tryParse(raw);
    if (until == null) return false;
    return DateTime.now().toUtc().isBefore(until);
  }

  /// Manually clear the session-unlock timer — used by the "lock now"
  /// affordance on the parental settings screen and on profile switch.
  Future<void> lockSession() async {
    await _storage.prefsBox.delete(_kParentalSessionUnlockKey);
  }

  /// `null` when not currently locked out. Otherwise returns the UTC
  /// timestamp at which the lock-out lifts.
  DateTime? lockedUntil() => _readLockoutUntil();

  /// True when the kids profile [profile] should still be allowed to
  /// start playback at the current device time. Combines the bedtime
  /// hour and the simple "lock-out is active" check.
  bool isWithinAllowedHours(UserProfile profile) {
    if (!profile.isKids) return true;
    final settings = current();
    if (!settings.enabled) return true;
    final bed = settings.bedtimeOfDay;
    if (bed == null) return true;
    final now = DateTime.now();
    final nowMinutes = now.hour * 60 + now.minute;
    final bedMinutes = bed.hour * 60 + bed.minute;
    const wakeMinutes = 6 * 60; // 6 AM, matches the "kids hours" doc
    if (bedMinutes >= wakeMinutes) {
      // Window: bedtime → 6 AM. Block if now is in the window.
      return !(nowMinutes >= bedMinutes || nowMinutes < wakeMinutes);
    }
    // Bedtime before wake (rare — caregiver wants strict daytime
    // window). Block when inside the window.
    return !(nowMinutes >= bedMinutes && nowMinutes < wakeMinutes);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<void> _persist(ParentalSettings settings) async {
    await _storage.prefsBox
        .put(_kParentalSettingsKey, jsonEncode(settings.toJson()));
  }

  int _readAttempts() {
    final raw = _storage.prefsBox.get(_kParentalFailedAttemptsKey);
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return 0;
  }

  Future<void> _writeAttempts(int n) async {
    await _storage.prefsBox.put(_kParentalFailedAttemptsKey, n);
  }

  Future<void> _resetAttempts() async {
    await _storage.prefsBox.delete(_kParentalFailedAttemptsKey);
    await _storage.prefsBox.delete(_kParentalLockoutKey);
  }

  DateTime? _readLockoutUntil() {
    final raw = _storage.prefsBox.get(_kParentalLockoutKey);
    if (raw is! String) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> _writeLockoutUntil(DateTime until) async {
    await _storage.prefsBox
        .put(_kParentalLockoutKey, until.toUtc().toIso8601String());
  }

  Future<void> _markSessionUnlocked() async {
    final until =
        DateTime.now().toUtc().add(ParentalLockoutSpec.sessionUnlockDuration);
    await _storage.prefsBox
        .put(_kParentalSessionUnlockKey, until.toIso8601String());
  }

  String _generateSalt() {
    final bytes = List<int>.generate(
      ProfilePinHasher.saltLengthBytes,
      (_) => _rng.nextInt(256),
    );
    return base64UrlEncode(bytes);
  }

  String _digest({required String salt, required String pin}) {
    final bytes = utf8.encode('$salt::parental::$pin');
    return sha256.convert(bytes).toString();
  }
}
