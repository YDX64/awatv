import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProviderIntel.match', () {
    test('matches exact host', () {
      final fp = ProviderIntel.match('worldiptv.me');
      expect(fp.id, 'worldiptv');
      expect(fp.ipLockedToResidential, isTrue);
      expect(fp.needsRefererHeader, isTrue);
    });

    test('matches a subdomain via suffix rule', () {
      // `cdn-01.worldiptv.me` should still resolve to the worldiptv
      // fingerprint via the host.endsWith('.worldiptv.me') check.
      final fp = ProviderIntel.match('cdn-01.worldiptv.me');
      expect(fp.id, 'worldiptv');
    });

    test('host comparison is case-insensitive', () {
      final fp = ProviderIntel.match('SaNSat.TV');
      expect(fp.id, 'sansat-style');
    });

    test('falls back to generic for unknown host', () {
      final fp = ProviderIntel.match('unknown-host.example.com');
      expect(fp.id, 'generic-xtream');
    });

    test('empty/whitespace host returns generic', () {
      expect(ProviderIntel.match('').id, 'generic-xtream');
      expect(ProviderIntel.match('   ').id, 'generic-xtream');
    });

    test('matchUrl extracts host from URL', () {
      expect(
        ProviderIntel.matchUrl('http://cdn.worldiptv.me/live/u/p/1.m3u8').id,
        'worldiptv',
      );
      expect(
        ProviderIntel.matchUrl('http://random.example.com/live/u/p/1.ts').id,
        'generic-xtream',
      );
    });

    test('all fingerprints are exposed and ordered', () {
      final all = ProviderIntel.all;
      // The catch-all is always last so callers can rely on it as the
      // sentinel "matches everything" entry.
      expect(all.last.id, 'generic-xtream');
      // We promised at least 8 named fingerprints + the generic one.
      expect(all.length, greaterThanOrEqualTo(9));
    });
  });

  group('ProviderIntel.applyTo', () {
    test('produces ordered candidates with original URL first', () {
      final candidates = ProviderIntel.applyTo(
        'http://provider.tv/live/u1/p1/9001.ts',
      );
      expect(candidates, isNotEmpty);
      expect(candidates.first.url, 'http://provider.tv/live/u1/p1/9001.ts');
    });

    test('worldiptv recipe attaches VLC UA + Referer + /live/ prefix', () {
      final candidates = ProviderIntel.applyTo(
        'http://cdn.worldiptv.me/u1/p1/9001.ts',
      );
      // Headers come from the worldiptv fingerprint.
      final first = candidates.first;
      expect(first.userAgent, contains('VLC'));
      expect(first.referer, isNotNull);
      expect(first.referer, startsWith('http://cdn.worldiptv.me/'));
      expect(first.headers['User-Agent'], first.userAgent);
      expect(first.headers['Referer'], first.referer);

      // Recipe should expand to include the /live/ prefix variant and
      // an .m3u8 swap (worldiptv prefers m3u8 over ts).
      final urls = candidates.map((c) => c.url).toList();
      expect(
        urls,
        contains('http://cdn.worldiptv.me/live/u1/p1/9001.ts'),
      );
      expect(
        urls.any((u) => u.endsWith('.m3u8')),
        isTrue,
        reason: 'worldiptv recipe should produce an .m3u8 candidate',
      );
    });

    test('sansat recipe injects Referer but no /live/ prefix mandate', () {
      final candidates = ProviderIntel.applyTo(
        'http://stream.sansat.tv/live/u/p/42.m3u8',
      );
      expect(candidates.first.referer, 'http://stream.sansat.tv/');
      expect(candidates.first.headers['Referer'], 'http://stream.sansat.tv/');
    });

    test('generic fallback produces /live/ + ext-swap variants', () {
      // Unknown host → generic fingerprint. Should still produce both
      // shapes for the fallback chain.
      final candidates = ProviderIntel.applyTo(
        'http://unknown.example.com/u/p/1.ts',
      );
      final urls = candidates.map((c) => c.url).toList();
      expect(urls.first, 'http://unknown.example.com/u/p/1.ts');
      expect(urls, contains('http://unknown.example.com/live/u/p/1.ts'));
      expect(urls.any((u) => u.endsWith('.m3u8')), isTrue);
    });

    test('non-http URLs pass through verbatim', () {
      final candidates =
          ProviderIntel.applyTo('rtmp://stream.example.com/live/feed');
      expect(candidates, hasLength(1));
      expect(candidates.first.url, 'rtmp://stream.example.com/live/feed');
    });

    test('empty URL returns empty list', () {
      expect(ProviderIntel.applyTo(''), isEmpty);
      expect(ProviderIntel.applyTo('   '), isEmpty);
    });

    test('candidates are capped to a reasonable count', () {
      // The cap (6 today) keeps the player from spinning through 20
      // dead URLs. Exact value is implementation detail; we just
      // assert a sane upper bound.
      final candidates = ProviderIntel.applyTo(
        'http://provider.tv/u/p/1.ts',
      );
      expect(candidates.length, lessThanOrEqualTo(8));
    });

    test('candidate equality compares url + headers', () {
      const a = StreamCandidate(url: 'http://x/y', userAgent: 'VLC');
      const b = StreamCandidate(url: 'http://x/y', userAgent: 'VLC');
      const c = StreamCandidate(url: 'http://x/y', userAgent: 'Chrome');
      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });

  group('ProviderIntel.renderUrl', () {
    test('uses generic Xtream layout for unknown hosts', () {
      final url = ProviderIntel.renderUrl(
        host: 'random.example.com',
        kind: StreamKind.live,
        server: 'http://random.example.com:8080',
        user: 'u1',
        pass: 'p1',
        id: '9001',
        ext: 'ts',
      );
      expect(url, 'http://random.example.com:8080/u1/p1/9001.ts');
    });

    test('iptvmate uses /play/ rooted live template', () {
      final url = ProviderIntel.renderUrl(
        host: 'iptvmate.io',
        kind: StreamKind.live,
        server: 'http://iptvmate.io',
        user: 'u',
        pass: 'p',
        id: '7',
        ext: 'm3u8',
      );
      expect(url, 'http://iptvmate.io/play/live/u/p/7.m3u8');
    });

    test('tivustream uses /tv/ rooted series template', () {
      final url = ProviderIntel.renderUrl(
        host: 'tivustream.tv',
        kind: StreamKind.series,
        server: 'http://tivustream.tv',
        user: 'u',
        pass: 'p',
        id: '99',
        ext: 'mp4',
      );
      expect(url, 'http://tivustream.tv/tv/u/p/99.mp4');
    });

    test('worldiptv uses /live/ rooted live template', () {
      final url = ProviderIntel.renderUrl(
        host: 'worldiptv.me',
        kind: StreamKind.live,
        server: 'http://worldiptv.me',
        user: 'u',
        pass: 'p',
        id: '1',
        ext: 'm3u8',
      );
      expect(url, 'http://worldiptv.me/live/u/p/1.m3u8');
    });

    test('VOD uses /movie/ for generic and ott-iptv-stream', () {
      final generic = ProviderIntel.renderUrl(
        host: 'random.example.com',
        kind: StreamKind.vod,
        server: 'http://random.example.com',
        user: 'u',
        pass: 'p',
        id: '5',
        ext: 'mkv',
      );
      expect(generic, 'http://random.example.com/movie/u/p/5.mkv');

      final ott = ProviderIntel.renderUrl(
        host: 'ott.iptv-stream.tv',
        kind: StreamKind.vod,
        server: 'http://ott.iptv-stream.tv',
        user: 'u',
        pass: 'p',
        id: '5',
        ext: 'mp4',
      );
      expect(ott, 'http://ott.iptv-stream.tv/movie/u/p/5.mp4');
    });

    test('trailing slash on server is normalised', () {
      final url = ProviderIntel.renderUrl(
        host: 'random.example.com',
        kind: StreamKind.live,
        server: 'http://random.example.com:8080/',
        user: 'u',
        pass: 'p',
        id: '1',
        ext: 'ts',
      );
      expect(url, 'http://random.example.com:8080/u/p/1.ts');
    });
  });

  group('ProviderFingerprint.notes', () {
    test('every non-generic fingerprint has at least one note', () {
      // The notes are how we keep the rationale auditable; missing
      // notes mean the recipe is undocumented and dangerous.
      for (final fp in ProviderIntel.all) {
        if (fp.id == 'generic-xtream') continue;
        expect(
          fp.notes,
          isNotEmpty,
          reason: 'fingerprint ${fp.id} must document its WHY',
        );
      }
    });
  });
}
