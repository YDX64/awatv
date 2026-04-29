// ignore_for_file: avoid_slow_async_io — fs probes in test setUp/tearDown are deliberate.
import 'dart:io';

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tmp;
  late AwatvStorage storage;
  late FavoritesService service;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('awatv_fav_');
    storage = AwatvStorage();
    await storage.init(subDir: tmp.path);
    service = FavoritesService(storage: storage);
  });

  tearDown(() async {
    await service.dispose();
    await storage.close();
    if (await tmp.exists()) {
      await tmp.delete(recursive: true);
    }
  });

  group('FavoritesService.toggle', () {
    test('adds the channel id when absent', () async {
      expect(await service.isFavorite('chan-1'), isFalse);
      await service.toggle('chan-1');
      expect(await service.isFavorite('chan-1'), isTrue);
      expect(await service.all(), {'chan-1'});
    });

    test('removes the channel id when present', () async {
      await service.toggle('chan-1');
      expect(await service.isFavorite('chan-1'), isTrue);
      await service.toggle('chan-1');
      expect(await service.isFavorite('chan-1'), isFalse);
      expect(await service.all(), isEmpty);
    });

    test('handles many distinct channel ids independently', () async {
      await service.toggle('a');
      await service.toggle('b');
      await service.toggle('c');
      expect(await service.all(), {'a', 'b', 'c'});
      await service.toggle('b');
      expect(await service.all(), {'a', 'c'});
    });
  });

  group('FavoritesService.watch', () {
    test('emits initial set, then updates after toggles', () async {
      // Pre-seed one favorite so the initial emission isn't trivially empty.
      await service.toggle('seed');

      final emissions = <Set<String>>[];
      final sub = service.watch().listen(emissions.add);

      // Allow initial emission.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(emissions, isNotEmpty);
      expect(emissions.first, {'seed'});

      // Add another favourite. Hive box.watch fires per put.
      await service.toggle('extra');
      await Future<void>.delayed(const Duration(milliseconds: 200));

      // Most-recent emission should contain both.
      expect(emissions.last, contains('seed'));
      expect(emissions.last, contains('extra'));

      // Remove.
      await service.toggle('seed');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(emissions.last, isNot(contains('seed')));
      expect(emissions.last, contains('extra'));

      await sub.cancel();
    });
  });
}
