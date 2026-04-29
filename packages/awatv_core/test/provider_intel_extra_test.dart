import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

/// Additional ProviderIntel coverage focused on the lesser-exercised
/// paths: HTTPS handling, port preservation, recipe stability, and
/// fingerprint registry invariants.
///
/// Complements `provider_intel_test.dart` which covers the canonical
/// match / applyTo / renderUrl flow.
void main() {
  group('ProviderIntel.match — extra cases', () {
    test('matches deep subdomain with multiple labels', () {
      final fp = ProviderIntel.match('a.b.c.worldiptv.me');
      expect(fp.id, 'worldiptv');
    });

    test('strips port before matching', () {
      // matchUrl is the public API that strips the port; match() takes
      // a host directly, so we expect the user to have stripped it.
      // The existing implementation forwards through Uri.host which
      // never carries the port — verify here as a regression guard.
      final fp = ProviderIntel.matchUrl('http://worldiptv.me:8080/x');
      expect(fp.id, 'worldiptv');
    });

    test('sansat-style matches naked host case-insensitively', () {
      final fp = ProviderIntel.match('SANSAT.tv');
      expect(fp.id, 'sansat-style');
    });

    test('non-ASCII host falls back to generic', () {
      final fp = ProviderIntel.match('ürün.example.com');
      expect(fp.id, 'generic-xtream');
    });

    test('matchUrl handles malformed URL gracefully', () {
      // Garbage URL — must not throw and must return generic.
      final fp = ProviderIntel.matchUrl('not a url at all');
      expect(fp.id, 'generic-xtream');
    });
  });

  group('ProviderIntel.applyTo — recipe stability', () {
    test('candidates are deterministic across calls', () {
      final a = ProviderIntel.applyTo('http://provider.tv/u/p/1.ts');
      final b = ProviderIntel.applyTo('http://provider.tv/u/p/1.ts');
      expect(a.length, b.length);
      for (var i = 0; i < a.length; i++) {
        expect(a[i].url, b[i].url);
        expect(a[i].userAgent, b[i].userAgent);
        expect(a[i].referer, b[i].referer);
      }
    });

    test('first candidate equals input URL', () {
      const original = 'http://random.example.com/a/b/c.ts';
      final candidates = ProviderIntel.applyTo(original);
      expect(candidates.first.url, original);
    });

    test('worldiptv recipe attaches non-empty headers map', () {
      final candidates =
          ProviderIntel.applyTo('http://worldiptv.me/u/p/1.ts');
      expect(candidates.first.headers, isNotEmpty);
      expect(candidates.first.headers, containsPair('User-Agent', isA<String>()));
    });

    test('https URLs are preserved in candidates', () {
      final candidates = ProviderIntel.applyTo(
        'https://secure.example.com/u/p/1.m3u8',
      );
      for (final c in candidates) {
        expect(c.url, startsWith('https://'));
      }
    });

    test('whitespace-only URL returns empty list', () {
      expect(ProviderIntel.applyTo('\t\n '), isEmpty);
    });
  });

  group('ProviderIntel.all', () {
    test('every fingerprint has a non-empty id', () {
      for (final fp in ProviderIntel.all) {
        expect(fp.id, isNotEmpty);
      }
    });

    test('fingerprint ids are unique', () {
      final ids = ProviderIntel.all.map((f) => f.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('ProviderIntel.renderUrl — extras', () {
    test('Accept VOD .mkv extension when caller asks for it', () {
      final url = ProviderIntel.renderUrl(
        host: 'random.example.com',
        kind: StreamKind.vod,
        server: 'http://random.example.com',
        user: 'u',
        pass: 'p',
        id: '1',
        ext: 'mkv',
      );
      expect(url, endsWith('.mkv'));
    });

    test('Series template includes /series/ for generic', () {
      final url = ProviderIntel.renderUrl(
        host: 'random.example.com',
        kind: StreamKind.series,
        server: 'http://random.example.com',
        user: 'u',
        pass: 'p',
        id: '5',
        ext: 'mp4',
      );
      expect(url, contains('/series/'));
    });

    test('Server URL with explicit port is preserved', () {
      final url = ProviderIntel.renderUrl(
        host: 'random.example.com',
        kind: StreamKind.live,
        server: 'http://random.example.com:9000',
        user: 'u',
        pass: 'p',
        id: '1',
        ext: 'ts',
      );
      expect(url, contains(':9000'));
    });
  });
}
