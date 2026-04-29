import 'dart:convert';

import 'package:crypto/crypto.dart';

/// One user-defined keyword-driven EPG alert.
///
/// Persisted in the shared `prefs` Hive box under
/// [SmartAlertsService.prefsKey] as a JSON list. Each entry has a stable
/// id derived from the keyword + the optional channel filter so the
/// "Yeni uyari" sheet can rebuild the same row without producing
/// duplicates.
///
/// Matching strategy: [keyword] is a case-insensitive substring; if
/// [channelTvgIds] is null/empty the alert fires on any *favourite*
/// channel that airs a programme matching the keyword. When a list of
/// tvg ids is supplied the alert only fires when the programme's
/// channel is in that subset (and still favourite — the favourite
/// gate is the privacy ceiling).
class KeywordAlert {
  const KeywordAlert({
    required this.id,
    required this.keyword,
    this.channelTvgIds,
    this.active = true,
    DateTime? createdAt,
  }) : _createdAt = createdAt;

  factory KeywordAlert.create({
    required String keyword,
    List<String>? channelTvgIds,
    bool active = true,
  }) {
    final clean = keyword.trim();
    final ids = (channelTvgIds == null || channelTvgIds.isEmpty)
        ? null
        : <String>[
            for (final raw in channelTvgIds)
              if (raw.trim().isNotEmpty) raw.trim(),
          ];
    return KeywordAlert(
      id: idFor(keyword: clean, channelTvgIds: ids),
      keyword: clean,
      channelTvgIds: ids,
      active: active,
      createdAt: DateTime.now().toUtc(),
    );
  }

  factory KeywordAlert.fromJson(Map<String, dynamic> json) {
    final raw = (json['channelTvgIds'] as List?)
        ?.whereType<String>()
        .where((String s) => s.isNotEmpty)
        .toList();
    return KeywordAlert(
      id: json['id'] as String,
      keyword: (json['keyword'] as String?) ?? '',
      channelTvgIds: (raw == null || raw.isEmpty) ? null : raw,
      active: (json['active'] as bool?) ?? true,
      createdAt: json['createdAt'] is String
          ? DateTime.tryParse(json['createdAt'] as String)?.toUtc()
          : null,
    );
  }

  /// Stable id for the (keyword, channelTvgIds?) tuple.
  static String idFor({
    required String keyword,
    List<String>? channelTvgIds,
  }) {
    final lower = keyword.trim().toLowerCase();
    final ids = (channelTvgIds == null || channelTvgIds.isEmpty)
        ? '*'
        : (List<String>.of(channelTvgIds)..sort()).join(',');
    final raw = 'kw|$lower|$ids';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
  }

  final String id;

  /// Case-insensitive substring matched against
  /// `programme.title` and `programme.description`.
  final String keyword;

  /// Restrict matching to these tvg ids. Null/empty = any favourite.
  final List<String>? channelTvgIds;

  /// Inactive alerts are kept around so the user can reactivate them
  /// without re-typing the keyword.
  final bool active;

  /// When the alert was first created — surfaced in the list as a
  /// secondary line ("Eklendi 12 Nis").
  DateTime? get createdAt => _createdAt;
  final DateTime? _createdAt;

  KeywordAlert copyWith({
    String? keyword,
    List<String>? channelTvgIds,
    bool? active,
    bool clearChannels = false,
  }) {
    final nextChannels = clearChannels
        ? null
        : (channelTvgIds ?? this.channelTvgIds);
    final nextKeyword = keyword ?? this.keyword;
    return KeywordAlert(
      id: idFor(keyword: nextKeyword, channelTvgIds: nextChannels),
      keyword: nextKeyword,
      channelTvgIds: nextChannels,
      active: active ?? this.active,
      createdAt: _createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    final created = _createdAt;
    return <String, dynamic>{
      'id': id,
      'keyword': keyword,
      if (channelTvgIds != null) 'channelTvgIds': channelTvgIds,
      'active': active,
      if (created != null) 'createdAt': created.toUtc().toIso8601String(),
    };
  }
}
