import 'package:awatv_core/awatv_core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockDio extends Mock implements Dio {}

void main() {
  setUpAll(() {
    registerFallbackValue(Uri());
    registerFallbackValue(Options());
  });

  group('StalkerClient', () {
    late _MockDio dio;
    late StalkerClient client;

    setUp(() {
      dio = _MockDio();
      client = StalkerClient(
        portalUrl: 'http://portal.example.tv:8080',
        macAddress: '00:1A:79:11:22:33',
        dio: dio,
      );
    });

    Response<dynamic> ok(dynamic body) => Response<dynamic>(
          requestOptions: RequestOptions(path: '/'),
          statusCode: 200,
          data: body,
        );

    test('isValidMac accepts canonical and dashed forms', () {
      expect(StalkerClient.isValidMac('00:1A:79:11:22:33'), isTrue);
      expect(StalkerClient.isValidMac('00-1A-79-11-22-33'), isTrue);
      expect(StalkerClient.isValidMac('001A.7911.2233'), isTrue);
      expect(StalkerClient.isValidMac('001A79112233'), isTrue);
      expect(StalkerClient.isValidMac('not-a-mac'), isFalse);
      expect(StalkerClient.isValidMac('00:1A:79:11:22'), isFalse);
      expect(StalkerClient.isValidMac('GG:1A:79:11:22:33'), isFalse);
    });

    test('normaliseMac uppercases and inserts colons', () {
      expect(
        StalkerClient.normaliseMac('00-1a-79-11-22-33'),
        '00:1A:79:11:22:33',
      );
      expect(
        StalkerClient.normaliseMac('001A79112233'),
        '00:1A:79:11:22:33',
      );
    });

    test('constructor throws StalkerAuthException on bad MAC', () {
      expect(
        () => StalkerClient(
          portalUrl: 'http://portal.example.tv',
          macAddress: 'oops',
          dio: dio,
        ),
        throwsA(isA<StalkerAuthException>()),
      );
    });

    test('handshake stores token and sends Cookie header', () async {
      when(() => dio.getUri<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer((Invocation inv) async {
        final opts = inv.namedArguments[#options] as Options?;
        expect(opts?.headers?['Cookie'], contains('mac=00%3A1A%3A79%3A11%3A22%3A33'));
        return ok({
          'js': {'token': 'abcd1234'},
        });
      });
      final ok2 = await client.handshake();
      expect(ok2, isTrue);
    });

    test('handshake throws on missing token', () async {
      when(() => dio.getUri<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer((_) async => ok(<String, dynamic>{
                'js': <String, dynamic>{},
              }));
      expect(
        client.handshake,
        throwsA(isA<StalkerAuthException>()),
      );
    });

    test('liveChannels parses get_all_channels rows', () async {
      // 1) handshake -> 2) get_profile (best-effort) ->
      // 3) get_genres -> 4) get_all_channels
      var call = 0;
      when(() => dio.getUri<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer((Invocation inv) async {
        call++;
        switch (call) {
          case 1:
            return ok(<String, dynamic>{
              'js': <String, dynamic>{'token': 'tok1'},
            });
          case 2:
            // get_profile best-effort response, ignored by client.
            return ok(<String, dynamic>{
              'js': <String, dynamic>{'id': 'profile-1'},
            });
          case 3:
            return ok(<String, dynamic>{
              'js': <Map<String, dynamic>>[
                <String, dynamic>{'id': '5', 'title': 'Spor'},
              ],
            });
          case 4:
            return ok(<String, dynamic>{
              'js': <String, dynamic>{
                'data': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 101,
                    'name': 'Channel One',
                    'cmd': 'ffmpeg http://stream.example/live/101.ts',
                    'logo': 'http://logo/1.png',
                    'tv_genre_id': '5',
                    'xmltv_id': 'channel.one',
                  },
                ],
              },
            });
          default:
            return ok(<String, dynamic>{
              'js': <String, dynamic>{'data': <dynamic>[]},
            });
        }
      });

      final channels = await client.liveChannels();
      expect(channels, hasLength(1));
      final c0 = channels.first;
      expect(c0.name, 'Channel One');
      expect(c0.tvgId, 'channel.one');
      expect(c0.logoUrl, 'http://logo/1.png');
      expect(c0.streamUrl, 'http://stream.example/live/101.ts');
      expect(c0.groups, ['Spor']);
      expect(c0.extras['stalker.cmd'], contains('ffmpeg'));
      expect(c0.id, contains('::live::101'));
    });

    test('streamUrlFromCmd strips player tag and absolutises', () {
      expect(
        client.streamUrlFromCmd(
          'ffmpeg http://other/live.ts',
          channelId: '1',
        ),
        'http://other/live.ts',
      );
      expect(
        client.streamUrlFromCmd(
          '/play/cmd?id=42',
          channelId: '42',
        ),
        'http://portal.example.tv:8080/play/cmd?id=42',
      );
      expect(
        client.streamUrlFromCmd(
          '',
          channelId: '99',
        ),
        'http://portal.example.tv:8080/play/live/99',
      );
      expect(
        client.streamUrlFromCmd(
          'auto https://abc.tv/x.m3u8',
          channelId: 'x',
        ),
        'https://abc.tv/x.m3u8',
      );
    });

    test('vodItems handles empty categories with wildcard fallback', () async {
      // 1) handshake, 2) get_profile, 3) get_categories (empty),
      // 4) get_ordered_list category=*
      var call = 0;
      when(() => dio.getUri<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer((_) async {
        call++;
        switch (call) {
          case 1:
            return ok(<String, dynamic>{
              'js': <String, dynamic>{'token': 'tok1'},
            });
          case 2:
            return ok(<String, dynamic>{
              'js': <String, dynamic>{'id': 'profile-1'},
            });
          case 3:
            return ok(<String, dynamic>{'js': <dynamic>[]});
          case 4:
            return ok(<String, dynamic>{
              'js': <String, dynamic>{
                'data': <Map<String, dynamic>>[
                  <String, dynamic>{
                    'id': 200,
                    'name': 'Inception',
                    'year': '2010',
                    'rating_imdb': '8.8',
                    'cmd': 'ffmpeg http://vod.example/200.mp4',
                    'screenshot_uri': 'http://poster/200.jpg',
                    'description': 'Dreams within dreams.',
                  },
                ],
              },
            });
          default:
            return ok(<String, dynamic>{
              'js': <String, dynamic>{'data': <dynamic>[]},
            });
        }
      });

      final vod = await client.vodItems();
      expect(vod, hasLength(1));
      final v = vod.first;
      expect(v.title, 'Inception');
      expect(v.year, 2010);
      expect(v.rating, closeTo(8.8, 0.001));
      expect(v.streamUrl, 'http://vod.example/200.mp4');
      expect(v.posterUrl, 'http://poster/200.jpg');
    });

    test('handshake propagates 401 as StalkerAuthException', () async {
      when(() => dio.getUri<dynamic>(any(), options: any(named: 'options')))
          .thenAnswer((_) async => Response<dynamic>(
                requestOptions: RequestOptions(path: '/'),
                statusCode: 401,
              ));
      expect(
        client.handshake,
        throwsA(isA<StalkerAuthException>()),
      );
    });
  });
}
