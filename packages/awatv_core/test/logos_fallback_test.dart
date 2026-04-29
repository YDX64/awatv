import 'package:awatv_core/awatv_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogosFallback.slugify', () {
    test('drops HD/4K quality tokens', () {
      expect(LogosFallback.slugify('TRT 1 HD'), 'trt-1');
      expect(LogosFallback.slugify('Show TV 4K'), 'show-tv');
      expect(LogosFallback.slugify('BBC News FHD'), 'bbc-news');
    });

    test('lowercases and replaces whitespace with hyphens', () {
      expect(LogosFallback.slugify('Star TV'), 'star-tv');
      expect(LogosFallback.slugify('NTV  Spor'), 'ntv-spor');
    });

    test('strips punctuation', () {
      expect(LogosFallback.slugify('A Haber [HD]'), 'a-haber');
      expect(LogosFallback.slugify('Kanal D | Türkiye'), 'kanal-d-türkiye');
      expect(LogosFallback.slugify('CNN-Türk'), 'cnn-türk');
    });

    test('returns empty string for blank / pure-punctuation input', () {
      expect(LogosFallback.slugify(''), '');
      expect(LogosFallback.slugify('   '), '');
      expect(LogosFallback.slugify('|||'), '');
    });
  });

  group('LogosFallback.urlFor / candidatesFor', () {
    test('Turkey candidate is the first guess', () {
      expect(
        LogosFallback.urlFor('TRT 1 HD'),
        'https://raw.githubusercontent.com/tv-logo/tv-logos/main/countries/turkey/trt-1.png',
      );
    });

    test('world fallback is provided as the second guess', () {
      final list = LogosFallback.candidatesFor('BBC News HD');
      expect(list, hasLength(2));
      expect(list[0], contains('/countries/turkey/bbc-news.png'));
      expect(list[1], contains('/countries/world/bbc-news.png'));
    });

    test('empty input yields no candidates', () {
      expect(LogosFallback.candidatesFor(''), isEmpty);
      expect(LogosFallback.urlFor(''), isNull);
      expect(LogosFallback.worldUrlFor(''), isNull);
    });
  });
}
