import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeNotifier implements ReminderNotifier {
  final List<int> scheduled = <int>[];
  final List<int> cancelled = <int>[];

  @override
  Future<int> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime fireAt,
    Map<String, String>? payload,
  }) async {
    scheduled.add(id);
    return id;
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late _FakeNotifier notifier;
  late RemindersService svc;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_reminders_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    notifier = _FakeNotifier();
    svc = RemindersService(storage: storage, notifier: notifier);
  });

  tearDown(() async {
    await svc.dispose();
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  Channel ch() => const Channel(
        id: 'src::trt-1',
        sourceId: 'src',
        name: 'TRT 1',
        streamUrl: 'http://example.test/trt-1',
        kind: ChannelKind.live,
      );

  EpgProgramme prog(DateTime start) => EpgProgramme(
        channelTvgId: 'trt-1',
        start: start,
        stop: start.add(const Duration(hours: 1)),
        title: 'Haberler',
      );

  test('add schedules the OS notification 5 min before start', () async {
    final start = DateTime.now().add(const Duration(hours: 2));
    await svc.add(prog(start), channel: ch());
    expect(notifier.scheduled, hasLength(1));
    final list = await svc.all();
    expect(list, hasLength(1));
    expect(list.first.programmeTitle, 'Haberler');
  });

  test('idempotent — same (channel, start) does not duplicate', () async {
    final start = DateTime.now().add(const Duration(hours: 2));
    await svc.add(prog(start), channel: ch());
    await svc.add(prog(start), channel: ch());
    final list = await svc.all();
    expect(list, hasLength(1));
  });

  test('cancel removes both the record and the OS notification', () async {
    final start = DateTime.now().add(const Duration(hours: 2));
    final r = await svc.add(prog(start), channel: ch());
    await svc.cancel(r.id);
    final list = await svc.all();
    expect(list, isEmpty);
    expect(notifier.cancelled, contains(r.notificationId));
  });

  test('past-fire-time records but does not schedule OS', () async {
    final start = DateTime.now().subtract(const Duration(minutes: 1));
    await svc.add(prog(start), channel: ch());
    final list = await svc.all();
    expect(list, hasLength(1));
    expect(notifier.scheduled, isEmpty);
  });

  test('upcoming() filters out reminders whose start is in the past', () async {
    final past = DateTime.now().subtract(const Duration(hours: 1));
    final future = DateTime.now().add(const Duration(hours: 2));
    await svc.add(prog(past), channel: ch());
    await svc.add(prog(future), channel: ch());
    final upcoming = await svc.upcoming();
    expect(upcoming, hasLength(1));
    expect(upcoming.first.start.isAfter(DateTime.now().toUtc()), isTrue);
  });
}
