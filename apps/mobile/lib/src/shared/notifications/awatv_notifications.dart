import 'dart:async';
import 'dart:io' show Platform;

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// One-shot platform initialiser + scheduler bridging
/// `flutter_local_notifications` to [ReminderNotifier] (defined in
/// awatv_core, platform-free).
///
/// Lifecycle:
///   * [init] is called from `main.dart` once the Flutter binding is up.
///     It configures the Android channel, the iOS request flags and the
///     Darwin / Linux init settings. **Permission is NOT requested here**
///     — we wait for the first user-driven scheduling attempt to ask, so
///     the system permission dialog only appears when the user actually
///     wants the feature (Android 13+ POST_NOTIFICATIONS, iOS alert/badge).
///   * [schedule] is the ReminderNotifier entry point — it requests
///     permission lazily, looks up the local IANA zone, and persists the
///     job in the OS scheduler.
///   * [cancel] removes a scheduled job.
///   * [tapsStream] surfaces notification taps so the app can deep-link
///     to `/play` for the reminded channel.
///
/// Web / desktop: every call is a no-op so callers don't need to guard.
class AwatvNotifications implements ReminderNotifier {
  AwatvNotifications._();

  /// Singleton — created once and shared across the Riverpod provider.
  static final AwatvNotifications instance = AwatvNotifications._();

  static const String _channelId = 'reminders';
  static const String _channelName = 'EPG hatirlatici';
  static const String _channelDesc =
      'Yakinda baslayacak programlar icin AWAtv hatirlatmalari';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final StreamController<NotificationTap> _taps =
      StreamController<NotificationTap>.broadcast();

  bool _initialized = false;
  bool _permissionGranted = false;

  /// Stream of user taps. Each event includes the payload that was
  /// attached when the notification was scheduled.
  Stream<NotificationTap> get tapsStream => _taps.stream;

  /// Set up the platform notification channels + tap handler. Idempotent.
  Future<void> init() async {
    if (_initialized) return;
    if (kIsWeb) {
      _initialized = true;
      return;
    }
    try {
      tzdata.initializeTimeZones();
    } on Object catch (e) {
      debugPrint('AwatvNotifications: tz init failed: $e');
    }

    const AndroidInitializationSettings androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings darwinInit =
        DarwinInitializationSettings(
      // Defer permission to the first schedule so the dialog appears in
      // the right moment for the user.
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final InitializationSettings initSettings = const InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
      macOS: darwinInit,
    );

    try {
      await _plugin.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _handleTap,
      );
    } on Object catch (e) {
      debugPrint('AwatvNotifications: init failed: $e');
      _initialized = true;
      return;
    }

    // Surface the notification that may have launched the app from a
    // cold start (user tapped while the app was not running).
    try {
      final NotificationAppLaunchDetails? launch =
          await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        final resp = launch!.notificationResponse;
        if (resp != null) {
          _handleTap(resp);
        }
      }
    } on Object catch (e) {
      debugPrint('AwatvNotifications: launch details failed: $e');
    }

    // Android: create the dedicated channel so we get sound + badge.
    try {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDesc,
          importance: Importance.high,
        ),
      );
    } on Object catch (e) {
      debugPrint('AwatvNotifications: channel create failed: $e');
    }

    _initialized = true;
  }

  /// Lazy permission request — only called the first time the user taps
  /// "Hatirlat". Returns `true` when the OS allows scheduling.
  Future<bool> ensurePermission() async {
    if (kIsWeb) return false;
    if (_permissionGranted) return true;
    await init();
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        final granted = await _plugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            await _plugin
                .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true);
        _permissionGranted = granted ?? false;
        return _permissionGranted;
      }
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        // Android 13+ runtime permission.
        final granted = await android?.requestNotificationsPermission();
        _permissionGranted = granted ?? true;
        // Exact-alarm permission is needed for `zonedSchedule` to fire
        // on time on Android 12+. Best-effort — failure here only means
        // the OS may delay the notification by a few minutes.
        try {
          await android?.requestExactAlarmsPermission();
        } on Object catch (e) {
          debugPrint('AwatvNotifications: exact alarms request: $e');
        }
        return _permissionGranted;
      }
    } on Object catch (e) {
      debugPrint('AwatvNotifications: ensurePermission failed: $e');
    }
    // Linux / desktop fall through — assume granted.
    _permissionGranted = true;
    return _permissionGranted;
  }

  @override
  Future<int> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    Map<String, String>? payload,
  }) async {
    if (kIsWeb) return id;
    await init();
    final ok = await ensurePermission();
    if (!ok) {
      throw const NotificationPermissionException(
        'Bildirim izni reddedildi',
      );
    }

    final tz.Location loc = _resolveLocalLocation();
    final tz.TZDateTime when = tz.TZDateTime.from(fireAt.toLocal(), loc);

    const AndroidNotificationDetails android = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDesc,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
      ticker: 'AWAtv',
    );
    const DarwinNotificationDetails darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails details = NotificationDetails(
      android: android,
      iOS: darwin,
      macOS: darwin,
    );

    try {
      await _plugin.zonedSchedule(
        id,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        payload: _encodePayload(payload),
      );
    } on Object catch (e) {
      debugPrint('AwatvNotifications: zonedSchedule failed: $e');
      // Fallback to inexact mode — at least the notification fires.
      try {
        await _plugin.zonedSchedule(
          id,
          title,
          body,
          when,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          payload: _encodePayload(payload),
        );
      } on Object catch (inner) {
        rethrow_or_warn(inner);
      }
    }
    return id;
  }

  @override
  Future<void> cancel(int id) async {
    if (kIsWeb) return;
    await init();
    try {
      await _plugin.cancel(id);
    } on Object catch (e) {
      debugPrint('AwatvNotifications: cancel($id) failed: $e');
    }
  }

  /// Resolve the IANA zone for the OS — falls back to UTC if the lookup
  /// fails. The fallback only really hurts at DST transitions, where
  /// off-by-an-hour beats not firing at all.
  tz.Location _resolveLocalLocation() {
    try {
      final name = DateTime.now().timeZoneName;
      // Many platforms expose abbreviations like "GMT+3" or "EET" —
      // those aren't IANA names. Try a direct lookup first.
      return tz.getLocation(name);
    } on Object {
      // Fall through to offset-based pick.
    }
    try {
      final offset = DateTime.now().timeZoneOffset;
      // Pick a sensible default close to the OS offset.
      final candidates = <String>{
        if (offset == const Duration(hours: 3)) 'Europe/Istanbul',
        if (offset == const Duration(hours: 0)) 'Etc/UTC',
        if (offset == const Duration(hours: 1)) 'Europe/London',
        if (offset == const Duration(hours: 2)) 'Europe/Bucharest',
        'Etc/UTC',
      };
      for (final name in candidates) {
        try {
          return tz.getLocation(name);
        } on Object {
          continue;
        }
      }
    } on Object {
      // Fall through.
    }
    return tz.getLocation('Etc/UTC');
  }

  String? _encodePayload(Map<String, String>? payload) {
    if (payload == null || payload.isEmpty) return null;
    final pairs = <String>[
      for (final e in payload.entries)
        '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}',
    ];
    return pairs.join('&');
  }

  Map<String, String> _decodePayload(String? raw) {
    if (raw == null || raw.isEmpty) return const <String, String>{};
    final out = <String, String>{};
    for (final pair in raw.split('&')) {
      final parts = pair.split('=');
      if (parts.length != 2) continue;
      try {
        out[Uri.decodeComponent(parts[0])] =
            Uri.decodeComponent(parts[1]);
      } on Object {
        continue;
      }
    }
    return out;
  }

  void _handleTap(NotificationResponse response) {
    final payload = _decodePayload(response.payload);
    _taps.add(NotificationTap(payload: payload));
  }

  /// Defensive helper used by the schedule fallback. Logs but never lets
  /// a notification scheduling exception bubble up far enough to crash
  /// the app — caller already wraps in try/catch.
  // ignore: non_constant_identifier_names
  void rethrow_or_warn(Object e) {
    debugPrint('AwatvNotifications: schedule fallback failed: $e');
  }
}

/// Payload struct emitted to [AwatvNotifications.tapsStream]. The router
/// listens for `kind=='reminder'` and pushes `/play` with the cached
/// channel, or `/reminders` if the channel id no longer resolves.
class NotificationTap {
  const NotificationTap({required this.payload});

  final Map<String, String> payload;

  String? get kind => payload['kind'];
  String? get channelId => payload['channelId'];
  bool get autoTuneIn =>
      (payload['autoTuneIn'] ?? 'false').toLowerCase() == 'true';
}

/// Thrown when the user denies notification permission. The "Hatirlat"
/// flow surfaces this as a toast that nudges the user to "Ayarlar"
/// (system settings).
class NotificationPermissionException implements Exception {
  const NotificationPermissionException(this.message);
  final String message;

  @override
  String toString() => 'NotificationPermissionException: $message';
}
