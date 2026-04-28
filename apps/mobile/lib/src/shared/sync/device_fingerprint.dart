import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/sync/sync_envelope.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

/// Stable per-install identity used to populate `device_sessions`.
///
/// We persist the generated id in the shared `prefs` Hive box so the
/// same row keeps its identity across app restarts. A `(user_id,
/// device_id)` pair is the natural sync key — re-using it lets us
/// upsert heartbeats instead of accumulating ghost rows.
class DeviceFingerprint {
  const DeviceFingerprint({
    required this.deviceId,
    required this.kind,
    required this.platform,
    this.userAgent,
  });

  final String deviceId;
  final DeviceKind kind;

  /// Free-form OS+version string, e.g. `ios-17.4`, `android-14`,
  /// `macos-14.3`, `web`. Stored verbatim on the server.
  final String platform;

  final String? userAgent;

  /// Persisted Hive key used by [resolve].
  static const String _kPrefsDeviceIdKey = 'sync:device_id';

  /// Read the existing id or generate + persist a fresh uuid. Cheap
  /// enough to call on every engine activate so callers don't need to
  /// memoise the result themselves.
  static DeviceFingerprint resolve(AwatvStorage storage) {
    final box = storage.prefsBox;
    final existing = box.get(_kPrefsDeviceIdKey);
    final id = existing is String && existing.isNotEmpty
        ? existing
        : _newId();
    if (existing != id) {
      // Fire-and-forget: a duplicate write on a hot loop is fine.
      // Writing here keeps the behaviour idempotent.
      box.put(_kPrefsDeviceIdKey, id);
    }

    final platform = _detectPlatform();
    final kind = _detectKind();

    return DeviceFingerprint(
      deviceId: id,
      kind: kind,
      platform: platform,
    );
  }

  static String _newId() => const Uuid().v4();

  static String _detectPlatform() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isIOS) return 'ios-${Platform.operatingSystemVersion}';
      if (Platform.isAndroid) {
        return 'android-${Platform.operatingSystemVersion}';
      }
      if (Platform.isMacOS) return 'macos-${Platform.operatingSystemVersion}';
      if (Platform.isWindows) {
        return 'windows-${Platform.operatingSystemVersion}';
      }
      if (Platform.isLinux) return 'linux-${Platform.operatingSystemVersion}';
    } on Object {
      // Platform throws on unsupported targets; fall through.
    }
    return 'unknown';
  }

  /// Heuristic — there is no "is this a TV" probe in dart:io, but the
  /// only consumer that reports `tv` is the Android TV / Apple TV shell
  /// which sets [_overrideTvForCurrentProcess] before the engine
  /// activates. Phones default to `phone`, desktop OSes to `desktop`,
  /// browsers to `web`. The user can rename the row on the manage
  /// devices screen.
  static DeviceKind _detectKind() {
    if (_overrideTvForCurrentProcess) return DeviceKind.tv;
    if (kIsWeb) return DeviceKind.web;
    try {
      if (Platform.isIOS || Platform.isAndroid) return DeviceKind.phone;
      if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
        return DeviceKind.desktop;
      }
    } on Object {
      // ignore: best-effort
    }
    return DeviceKind.phone;
  }

  /// Set by the TV shell during boot. Untyped to keep this file from
  /// depending on the TV runtime in either direction.
  static bool _overrideTvForCurrentProcess = false;

  // ignore: use_setters_to_change_properties
  static void markCurrentProcessAsTv() {
    _overrideTvForCurrentProcess = true;
  }
}
