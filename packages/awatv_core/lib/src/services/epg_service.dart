import 'package:awatv_core/src/clients/epg_client.dart';
import 'package:awatv_core/src/models/epg_programme.dart';
import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:awatv_core/src/utils/awatv_logger.dart';

/// Downloads and indexes XMLTV EPG. Programmes are stored in Hive keyed by
/// `tvg_id`.
class EpgService {
  EpgService({
    required EpgClient client,
    required AwatvStorage storage,
  })  : _client = client,
        _storage = storage;

  final EpgClient _client;
  final AwatvStorage _storage;

  static final AwatvLogger _log = AwatvLogger(tag: 'EpgService');

  /// Fetch a fresh XMLTV document and persist programmes per channel.
  Future<void> sync(String url) async {
    final all = await _client.downloadAndParse(url);
    if (all.isEmpty) {
      _log.warn('EPG sync produced 0 programmes');
      return;
    }
    final byChannel = <String, List<EpgProgramme>>{};
    for (final p in all) {
      byChannel.putIfAbsent(p.channelTvgId, () => []).add(p);
    }
    for (final entry in byChannel.entries) {
      entry.value.sort((a, b) => a.start.compareTo(b.start));
      await _storage.putEpg(entry.key, entry.value);
    }
    _log.info(
      'EPG sync: ${all.length} programmes across ${byChannel.length} channels',
    );
  }

  /// Programmes for one channel — defaulting to a +/- 12h window around
  /// [around] (or now if null).
  Future<List<EpgProgramme>> programmesFor(
    String tvgId, {
    DateTime? around,
  }) async {
    final all = await _storage.getEpg(tvgId);
    if (all.isEmpty || around == null) return all;
    final from = around.subtract(const Duration(hours: 12));
    final to = around.add(const Duration(hours: 12));
    return all.where((p) => p.stop.isAfter(from) && p.start.isBefore(to)).toList();
  }
}
