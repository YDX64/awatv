// Tiny smoke tests for the awatv_core utility classes — exceptions
// have their own dedicated suite; this file pulls in the rest of the
// public surface area not yet covered.

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AwatvLogger', () {
    test('constructs with a tag', () {
      // Logger doesn't expose much beyond the tag — confirm the
      // constructor and `info` / `warn` are non-throwing.
      final log = AwatvLogger(tag: 'test');
      expect(log, isNotNull);
      // These should not throw — they print via dart:developer when
      // enabled and are safe to call from tests.
      log.info('hello');
      log.warn('hello');
    });
  });

  group('CatchupProgramme', () {
    test('duration getter computes stop - start', () {
      final start = DateTime.utc(2026, 4, 27, 10);
      final stop = start.add(const Duration(hours: 1));
      final p = CatchupProgramme(
        streamId: 9001,
        start: start,
        stop: stop,
        title: 'News',
        hasArchive: true,
      );
      expect(p.title, 'News');
      expect(p.streamId, 9001);
      expect(p.duration, const Duration(hours: 1));
    });

    test('isPast / isFuture compare against the supplied now', () {
      final start = DateTime.utc(2026, 4, 27, 10);
      final stop = start.add(const Duration(hours: 1));
      final p = CatchupProgramme(
        streamId: 1,
        start: start,
        stop: stop,
        title: 'X',
        hasArchive: true,
      );
      // Now is before start → future, not past.
      final before = start.subtract(const Duration(hours: 1));
      expect(p.isFuture(before), isTrue);
      expect(p.isPast(before), isFalse);
      // Now is after stop → past.
      final after = stop.add(const Duration(hours: 1));
      expect(p.isPast(after), isTrue);
      expect(p.isFuture(after), isFalse);
    });

    test('value-equality compares the relevant fields', () {
      final s = DateTime.utc(2026, 4, 27, 10);
      final e = s.add(const Duration(hours: 1));
      final a = CatchupProgramme(
        streamId: 1,
        start: s,
        stop: e,
        title: 'A',
        hasArchive: true,
      );
      final b = CatchupProgramme(
        streamId: 1,
        start: s,
        stop: e,
        title: 'A',
        hasArchive: true,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SubtitleResult', () {
    test('round-trips through JSON', () {
      const r = SubtitleResult(
        fileId: 9001,
        language: 'tr',
        release: 'Movie.2024',
        downloadCount: 42,
        rating: 7.8,
        hi: false,
        fromTrusted: true,
        releaseGroup: 'XYZ',
      );
      final j = r.toJson();
      final back = SubtitleResult.fromJson(j);
      expect(back.fileId, 9001);
      expect(back.language, 'tr');
      expect(back.release, 'Movie.2024');
      expect(back.downloadCount, 42);
      expect(back.rating, 7.8);
      expect(back.hi, isFalse);
      expect(back.fromTrusted, isTrue);
      expect(back.releaseGroup, 'XYZ');
    });

    test('decodes missing optional fields with defaults', () {
      final back = SubtitleResult.fromJson(<String, dynamic>{
        'fileId': 1,
      });
      expect(back.language, '');
      expect(back.downloadCount, 0);
      expect(back.rating, 0.0);
      expect(back.hi, isFalse);
      expect(back.fromTrusted, isFalse);
      expect(back.releaseGroup, isNull);
    });
  });

  group('LogosFallback', () {
    test('returns empty list for empty input', () {
      expect(LogosFallback.candidatesFor(''), isEmpty);
    });

    test('returns at least one candidate for "TRT 1"', () {
      final list = LogosFallback.candidatesFor('TRT 1');
      expect(list, isNotEmpty);
      // Must be HTTPS GitHub raw URLs.
      for (final url in list) {
        expect(url, startsWith('https://'));
      }
    });

    test('strips quality suffix when slugifying', () {
      // Both "TRT 1 HD" and "TRT 1" should produce the same slug.
      final hd = LogosFallback.candidatesFor('TRT 1 HD');
      final base = LogosFallback.candidatesFor('TRT 1');
      expect(hd, equals(base));
    });
  });
}
