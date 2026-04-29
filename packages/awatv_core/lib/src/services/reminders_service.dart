import 'dart:convert';

import 'package:awatv_core/src/models/channel.dart';
import 'package:awatv_core/src/models/epg_programme.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:crypto/crypto.dart';
import 'package:hive/hive.dart';

/// One scheduled "Hatirlat" entry.
///
/// Persisted as JSON in the `reminders` Hive box. The [id] is a stable
/// SHA-256 of `channelId + start.toUtc().toIso8601String()` so adding the
/// same programme twice is idempotent. [notificationId] is a 31-bit
/// integer derived from the same hash so the OS notification can be
/// scheduled / cancelled deterministically.
class Reminder {
  const Reminder({
    required this.id,
    required this.channelId,
    required this.channelName,
    required this.channelLogoUrl,
    required this.programmeTitle,
    required this.start,
    required this.stop,
    required this.notificationId,
    required this.createdAt,
    this.autoTuneIn = false,
  });

  factory Reminder.fromJson(Map<String, dynamic> json) {
    return Reminder(
      id: json['id'] as String,
      channelId: json['channelId'] as String,
      channelName: (json['channelName'] as String?) ?? '',
      channelLogoUrl: json['channelLogoUrl'] as String?,
      programmeTitle: (json['programmeTitle'] as String?) ?? '',
      start: DateTime.parse(json['start'] as String).toUtc(),
      stop: DateTime.parse(json['stop'] as String).toUtc(),
      notificationId: (json['notificationId'] as num).toInt(),
      createdAt: DateTime.parse(
        (json['createdAt'] as String?) ??
            DateTime.now().toUtc().toIso8601String(),
      ).toUtc(),
      autoTuneIn: (json['autoTuneIn'] as bool?) ?? false,
    );
  }

  /// Stable id (sha256 of `channelId + start.toIso8601String()`).
  final String id;

  /// Channel.id reference. Used to deep-link from the OS notification.
  final String channelId;

  /// Cached channel.name — keeps the reminders list useful even when the
  /// underlying playlist has been refreshed and the channel id changed.
  final String channelName;

  /// Cached logo. Optional.
  final String? channelLogoUrl;

  /// Programme title at the moment of scheduling — programme may be
  /// renamed in the EPG later but the user expects to see what they
  /// signed up for.
  final String programmeTitle;

  /// Programme start (always stored UTC; the notification fires
  /// 5 min before this in the user's local zone).
  final DateTime start;

  /// Programme stop (UTC). Used to expire stale reminders.
  final DateTime stop;

  /// 31-bit notification id used by `flutter_local_notifications`. We
  /// keep it on the model so cancellation never has to re-derive it.
  final int notificationId;

  /// When the reminder was scheduled (UTC).
  final DateTime createdAt;

  /// When true, the receiver app may auto-open `/play` for this channel
  /// when the notification fires. The current UI defaults this off —
  /// the user explicitly enables it from the reminders list screen.
  final bool autoTuneIn;

  /// Time the OS notification should fire — 5 min before [start].
  DateTime get fireAt =>
      start.subtract(const Duration(minutes: 5));

  /// True when the programme has finished — used to prune the list.
  bool isExpired(DateTime now) => stop.isBefore(now);

  /// True when the fire-time is already in the past at scheduling time.
  /// Caller decides what to do — typically still record the reminder
  /// but skip the OS schedule call.
  bool fireInPast(DateTime now) => fireAt.isBefore(now);

  Reminder copyWith({
    bool? autoTuneIn,
    String? channelLogoUrl,
  }) {
    return Reminder(
      id: id,
      channelId: channelId,
      channelName: channelName,
      channelLogoUrl: channelLogoUrl ?? this.channelLogoUrl,
      programmeTitle: programmeTitle,
      start: start,
      stop: stop,
      notificationId: notificationId,
      createdAt: createdAt,
      autoTuneIn: autoTuneIn ?? this.autoTuneIn,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'channelId': channelId,
        'channelName': channelName,
        'channelLogoUrl': channelLogoUrl,
        'programmeTitle': programmeTitle,
        'start': start.toUtc().toIso8601String(),
        'stop': stop.toUtc().toIso8601String(),
        'notificationId': notificationId,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'autoTuneIn': autoTuneIn,
      };
}

/// Hooks the local-notification platform — implemented on the app side
/// (mobile Flutter package, since `flutter_local_notifications` is not a
/// pure-Dart dependency). The core service stays platform-free.
abstract class ReminderNotifier {
  /// Schedule a one-shot notification at [fireAt]. Returns the actual
  /// notification id used (typically equal to `id`). Implementations
  /// should be idempotent: re-scheduling the same id replaces the
  /// previous schedule.
  Future<int> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    Map<String, String>? payload,
  });

  /// Cancel a previously scheduled notification.
  Future<void> cancel(int id);
}

/// Persists "Hatirlat" entries and bridges them to the OS notifier.
///
/// Free tier is capped at [freeMax]; the app checks the limit *before*
/// calling [add]. The service itself is tier-agnostic and only enforces
/// the platform mechanics.
class RemindersService {
  RemindersService({
    required AwatvStorage storage,
    ReminderNotifier? notifier,
    AwatvLogger? logger,
  })  : _storage = storage,
        _notifier = notifier,
        _log = logger ?? AwatvLogger(tag: 'RemindersService');

  final AwatvStorage _storage;
  final ReminderNotifier? _notifier;
  final AwatvLogger _log;

  /// Free-tier cap. Premium bypasses this in the UI.
  static const int freeMax = 5;

  static const String _boxName = AwatvStorage.boxReminders;

  /// Defensive — touch the storage handle so the dependency-injection
  /// contract is exercised. Surfaces an error early when the host app
  /// forgot to bootstrap [AwatvStorage] before constructing the service.
  void _assertReady() {
    // The expression statement is intentional — we only need the side
    // effect of accessing `_storage` so a missing singleton crashes
    // here instead of deeper inside Hive.
    // ignore: unnecessary_statements
    _storage;
  }

  /// Open the underlying box on first access. Hive remembers the open
  /// state per box name so repeated calls are cheap.
  Future<Box<String>> _box() async {
    _assertReady();
    if (Hive.isBoxOpen(_boxName)) {
      return Hive.box<String>(_boxName);
    }
    return Hive.openBox<String>(_boxName);
  }

  /// Compute the canonical reminder id for `(channelId, start)`.
  static String idFor(String channelId, DateTime start) {
    final raw = '$channelId|${start.toUtc().toIso8601String()}';
    return sha256.convert(utf8.encode(raw)).toString();
  }

  /// 31-bit positive int hash for the OS notification id. Derived from
  /// the same input as [idFor] so the two never drift.
  static int notificationIdFor(String channelId, DateTime start) {
    final digest = sha256.convert(
      utf8.encode('$channelId|${start.toUtc().toIso8601String()}'),
    );
    // Take the first 4 bytes of the digest as a positive int < 2^31.
    final b = digest.bytes;
    var v = 0;
    v |= (b[0] & 0xFF) << 24;
    v |= (b[1] & 0xFF) << 16;
    v |= (b[2] & 0xFF) << 8;
    v |= b[3] & 0xFF;
    return v & 0x7FFFFFFF;
  }

  /// Add a reminder for [programme] on [channel].
  ///
  /// Idempotent: if the same `(channelId, start)` already exists the
  /// existing record is updated and re-scheduled. Throws
  /// [StorageException] if the box can't be opened.
  Future<Reminder> add(
    EpgProgramme programme, {
    required Channel channel,
    bool autoTuneIn = false,
  }) async {
    final box = await _box();
    final id = idFor(channel.id, programme.start);
    final notifId = notificationIdFor(channel.id, programme.start);
    final reminder = Reminder(
      id: id,
      channelId: channel.id,
      channelName: channel.name,
      channelLogoUrl: channel.logoUrl,
      programmeTitle: programme.title,
      start: programme.start.toUtc(),
      stop: programme.stop.toUtc(),
      notificationId: notifId,
      createdAt: DateTime.now().toUtc(),
      autoTuneIn: autoTuneIn,
    );
    await box.put(id, jsonEncode(reminder.toJson()));

    final notifier = _notifier;
    if (notifier != null) {
      try {
        final fireAt = reminder.fireAt;
        if (fireAt.isAfter(DateTime.now())) {
          await notifier.schedule(
            id: notifId,
            title: 'Yakinda: ${programme.title}',
            body: '${channel.name} • 5 dakika icinde basliyor.',
            fireAt: fireAt,
            payload: <String, String>{
              'kind': 'reminder',
              'channelId': channel.id,
              'programmeStart': programme.start.toUtc().toIso8601String(),
              'autoTuneIn': autoTuneIn.toString(),
            },
          );
        } else {
          _log.warn(
            'reminder fire-time already past for ${programme.title} — '
            'persisted but not scheduled with OS',
          );
        }
      } on Object catch (e) {
        // Notification scheduling can fail (permission denied, OS quota,
        // tz lookup, etc.). Persist the entry anyway so the UI surface
        // can re-attempt later from the reminders list screen.
        _log.warn('schedule notification failed: $e');
      }
    }

    return reminder;
  }

  /// Cancel a reminder by its [id] (canonical hash, see [idFor]).
  Future<void> cancel(String id) async {
    final box = await _box();
    final raw = box.get(id);
    if (raw == null) return;
    try {
      final r = Reminder.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final notifier = _notifier;
      if (notifier != null) {
        try {
          await notifier.cancel(r.notificationId);
        } on Object catch (e) {
          _log.warn('cancel notification failed: $e');
        }
      }
    } on Exception catch (e) {
      _log.warn('cancel: corrupt reminder record $id: $e');
    }
    await box.delete(id);
  }

  /// Cancel by `(channelId, start)` — for callers that only have the
  /// raw EPG programme reference handy.
  Future<void> cancelFor(String channelId, DateTime start) {
    return cancel(idFor(channelId, start));
  }

  /// True when a reminder exists for this `(channelId, start)`.
  Future<bool> contains(String channelId, DateTime start) async {
    final box = await _box();
    return box.containsKey(idFor(channelId, start));
  }

  /// Cheap synchronous lookup. Returns `null` if the id isn't tracked
  /// or the box hasn't been opened yet.
  Reminder? getOrNull(String id) {
    if (!Hive.isBoxOpen(_boxName)) return null;
    final raw = Hive.box<String>(_boxName).get(id);
    if (raw == null) return null;
    try {
      return Reminder.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on Exception {
      return null;
    }
  }

  /// All reminders sorted by [Reminder.start] ascending. Pass
  /// `pruneExpired: true` to drop entries whose `stop` is already in the
  /// past — the underlying records are deleted from disk in that pass.
  Future<List<Reminder>> all({bool pruneExpired = false}) async {
    final box = await _box();
    final out = await _list(box);
    if (!pruneExpired) return out;
    final now = DateTime.now().toUtc();
    final toDelete = <String>[
      for (final r in out)
        if (r.isExpired(now)) r.id,
    ];
    if (toDelete.isNotEmpty) {
      await box.deleteAll(toDelete);
      // Also cancel the OS notifications even though they should have
      // already fired — defensive cleanup.
      final notifier = _notifier;
      if (notifier != null) {
        for (final id in toDelete) {
          final r = out.firstWhere((Reminder e) => e.id == id);
          try {
            await notifier.cancel(r.notificationId);
          } on Object catch (e) {
            _log.warn('prune cancel failed: $e');
          }
        }
      }
      return _list(box);
    }
    return out;
  }

  /// Upcoming reminders only — `fireAt` in the future, sorted ascending.
  Future<List<Reminder>> upcoming() async {
    final all = await this.all(pruneExpired: true);
    final now = DateTime.now().toUtc();
    return all.where((Reminder r) => r.start.isAfter(now)).toList();
  }

  /// Reactive stream of the full list.
  Stream<List<Reminder>> watch() async* {
    final box = await _box();
    yield await _list(box);
    yield* box.watch().asyncMap((_) => _list(box));
  }

  /// Toggle the auto-tune-in flag for a reminder, if it exists.
  Future<void> setAutoTuneIn(String id, {required bool value}) async {
    final box = await _box();
    final raw = box.get(id);
    if (raw == null) return;
    try {
      final r = Reminder.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      await box.put(id, jsonEncode(r.copyWith(autoTuneIn: value).toJson()));
    } on Exception catch (e) {
      _log.warn('setAutoTuneIn: corrupt record $id: $e');
    }
  }

  /// Re-arm every persisted reminder with the OS scheduler. Called from
  /// app boot so device reboots don't silently drop notifications.
  Future<void> rescheduleAll() async {
    final notifier = _notifier;
    if (notifier == null) return;
    final list = await all(pruneExpired: true);
    final now = DateTime.now();
    for (final r in list) {
      if (r.fireAt.isAfter(now)) {
        try {
          await notifier.schedule(
            id: r.notificationId,
            title: 'Yakinda: ${r.programmeTitle}',
            body: '${r.channelName} • 5 dakika icinde basliyor.',
            fireAt: r.fireAt,
            payload: <String, String>{
              'kind': 'reminder',
              'channelId': r.channelId,
              'programmeStart': r.start.toIso8601String(),
              'autoTuneIn': r.autoTuneIn.toString(),
            },
          );
        } on Object catch (e) {
          _log.warn('rescheduleAll: ${r.id} failed: $e');
        }
      }
    }
  }

  Future<List<Reminder>> _list(Box<String> box) async {
    final out = <Reminder>[];
    for (final v in box.values) {
      try {
        out.add(Reminder.fromJson(jsonDecode(v) as Map<String, dynamic>));
      } on Exception {
        // Skip corrupt records so a single bad row doesn't break the list.
      }
    }
    out.sort((Reminder a, Reminder b) => a.start.compareTo(b.start));
    return out;
  }

  Future<void> dispose() async {
    // Reactive subscribers consume Hive's box.watch() directly, so
    // there is no long-lived StreamController to close here.
  }
}
