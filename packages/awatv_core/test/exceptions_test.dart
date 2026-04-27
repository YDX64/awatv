import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AwatvException hierarchy', () {
    test('PlaylistParseException carries message and is an AwatvException', () {
      const ex = PlaylistParseException('bad m3u');
      expect(ex, isA<AwatvException>());
      expect(ex, isA<Exception>());
      expect(ex.message, 'bad m3u');
      expect(ex.line, isNull);
      expect(ex.toString(), 'PlaylistParseException: bad m3u');
    });

    test('PlaylistParseException with line includes line in toString()', () {
      const ex = PlaylistParseException('bad EXTINF', line: 42);
      expect(ex.line, 42);
      expect(ex.toString(), 'PlaylistParseException(line 42): bad EXTINF');
    });

    test('XtreamAuthException is AwatvException + Exception', () {
      const ex = XtreamAuthException('credentials rejected');
      expect(ex, isA<AwatvException>());
      expect(ex, isA<Exception>());
      expect(ex.message, 'credentials rejected');
      expect(ex.toString(), contains('credentials rejected'));
      expect(ex.toString(), contains('XtreamAuthException'));
    });

    test('NetworkException defaults: no statusCode, retryable=false', () {
      const ex = NetworkException('timeout');
      expect(ex.statusCode, isNull);
      expect(ex.retryable, isFalse);
      expect(ex.toString(), 'NetworkException: timeout');
    });

    test('NetworkException with statusCode formats it inside brackets', () {
      const ex = NetworkException(
        'service unavailable',
        statusCode: 503,
        retryable: true,
      );
      expect(ex.statusCode, 503);
      expect(ex.retryable, isTrue);
      expect(ex.toString(), 'NetworkException [503]: service unavailable');
    });

    test('MetadataNotFoundException records query and message', () {
      const ex = MetadataNotFoundException('Inception');
      expect(ex, isA<AwatvException>());
      expect(ex.query, 'Inception');
      expect(ex.message, 'No metadata match for query');
      expect(ex.toString(), contains('Inception'));
      expect(ex.toString(), contains('No metadata match for query'));
    });

    test('StorageException is an AwatvException', () {
      const ex = StorageException('hive box closed');
      expect(ex, isA<AwatvException>());
      expect(ex.message, 'hive box closed');
      expect(ex.toString(), 'StorageException: hive box closed');
    });

    test('All concrete exceptions can be caught as AwatvException', () {
      final exceptions = <AwatvException>[
        const PlaylistParseException('a'),
        const XtreamAuthException('b'),
        const NetworkException('c'),
        const MetadataNotFoundException('d'),
        const StorageException('e'),
      ];
      for (final e in exceptions) {
        expect(e, isA<AwatvException>());
        expect(e, isA<Exception>());
        // The runtimeType must surface in toString().
        expect(e.toString(), contains(e.runtimeType.toString()));
      }
    });

    test('subclass disambiguation via is checks works as expected', () {
      const Object a = NetworkException('x', statusCode: 500);
      expect(a is NetworkException, isTrue);
      expect(a is PlaylistParseException, isFalse);
      expect(a is StorageException, isFalse);
    });
  });
}
