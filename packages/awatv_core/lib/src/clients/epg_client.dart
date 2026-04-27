import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:awatv_core/src/models/epg_programme.dart';
import 'package:awatv_core/src/parsers/xmltv_parser.dart';
import 'package:awatv_core/src/utils/awatv_exceptions.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';
import 'package:dio/dio.dart';

/// Downloads and parses XMLTV EPG documents.
///
/// Auto-detects gzip via:
/// - URL suffix `.gz` / `.gzip`
/// - HTTP `Content-Encoding: gzip` header
/// - HTTP `Content-Type: application/gzip`
/// - Magic bytes `0x1F 0x8B`
class EpgClient {
  EpgClient({Dio? dio}) : _dio = dio ?? _defaultDio();

  final Dio _dio;

  static final AwatvLogger _log = AwatvLogger(tag: 'EpgClient');

  static Dio _defaultDio() => Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(minutes: 2),
          responseType: ResponseType.bytes,
        ),
      );

  Future<List<EpgProgramme>> downloadAndParse(String url, {Dio? dio}) async {
    final client = dio ?? _dio;
    final Response<List<int>> resp;
    try {
      resp = await client.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
    } on DioException catch (e) {
      _log.warn('EPG download failed: ${e.message}');
      throw NetworkException(
        e.message ?? 'EPG download failed',
        statusCode: e.response?.statusCode,
        retryable: e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            e.type == DioExceptionType.receiveTimeout,
      );
    }

    final code = resp.statusCode;
    if (code == null || code < 200 || code >= 300) {
      throw NetworkException(
        'EPG download returned status',
        statusCode: code,
        retryable: (code ?? 0) >= 500,
      );
    }

    final raw = Uint8List.fromList(resp.data ?? const <int>[]);
    final headers = resp.headers;
    final contentEncoding =
        headers.value('content-encoding')?.toLowerCase() ?? '';
    final contentType = headers.value('content-type')?.toLowerCase() ?? '';

    final isGz = url.toLowerCase().endsWith('.gz') ||
        url.toLowerCase().endsWith('.gzip') ||
        contentEncoding.contains('gzip') ||
        contentType.contains('gzip') ||
        contentType.contains('x-gzip') ||
        _hasGzipMagic(raw);

    final bodyBytes = isGz ? _gunzip(raw) : raw;
    final xml = utf8.decode(bodyBytes, allowMalformed: true);
    return XmltvParser.parse(xml);
  }

  static bool _hasGzipMagic(List<int> bytes) {
    return bytes.length >= 2 && bytes[0] == 0x1F && bytes[1] == 0x8B;
  }

  static List<int> _gunzip(List<int> bytes) {
    try {
      return const GZipDecoder().decodeBytes(bytes);
    } on Exception catch (e) {
      throw NetworkException('Failed to gunzip EPG: $e');
    }
  }
}
