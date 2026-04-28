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
    return all
        .where((p) => p.stop.isAfter(from) && p.start.isBefore(to))
        .toList();
  }

  /// Batched lookup for the EPG grid.
  ///
  /// Returns a map keyed by `tvgId` containing the programmes whose
  /// `[start, stop]` interval overlaps `[around - window, around + window]`.
  /// Each entry's list is sorted by `start` ascending.
  ///
  /// Channels with an empty/null `tvgId` and channels that have no cached
  /// programmes both yield an empty list — callers can rely on every
  /// requested id being present in the result map so they don't need to
  /// special-case missing keys.
  ///
  /// Compared to calling `programmesFor` once per channel this avoids the
  /// per-call assert + JSON-decode round-trip of the underlying Hive box,
  /// which matters when the grid is asked to render 100+ rows at once.
  Future<Map<String, List<EpgProgramme>>> programmesAroundForChannels({
    required List<String> tvgIds,
    DateTime? around,
    Duration window = const Duration(hours: 12),
  }) async {
    final out = <String, List<EpgProgramme>>{};
    if (tvgIds.isEmpty) return out;

    final clock = around ?? DateTime.now();
    final from = clock.subtract(window);
    final to = clock.add(window);

    // Dedupe before hitting storage — a playlist can legitimately reference
    // the same tvg-id from multiple channel rows (e.g. SD + HD variants).
    final seen = <String>{};
    for (final raw in tvgIds) {
      final id = raw.trim();
      if (id.isEmpty || !seen.add(id)) continue;
      final all = await _storage.getEpg(id);
      if (all.isEmpty) {
        out[id] = const <EpgProgramme>[];
        continue;
      }
      final filtered = all
          .where((p) => p.stop.isAfter(from) && p.start.isBefore(to))
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
      out[id] = List<EpgProgramme>.unmodifiable(filtered);
    }

    // Re-key duplicates so the caller can look up by any of their input ids.
    for (final raw in tvgIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      out.putIfAbsent(id, () => const <EpgProgramme>[]);
    }
    return out;
  }
}
