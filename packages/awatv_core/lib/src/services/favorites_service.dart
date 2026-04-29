import 'dart:async';
import 'dart:convert';

import 'package:awatv_core/src/storage/awatv_storage.dart';
import 'package:hive/hive.dart';

/// Per-channel favorites + grouped folder organization.
///
/// **Backwards compatibility note:** the channel-set side of this
/// service still uses the legacy `favorites` Hive box (a `Box<int>`
/// where the key is the channel id and the value is `1`). Existing
/// installs keep working without migration — folders are an additive
/// layer on top. The default folder ([kDefaultFolderId]) auto-shadows
/// the contents of the channel-set so a free-tier user (who never
/// touches folders) sees the exact same flat list.
class FavoritesService {
  FavoritesService({required AwatvStorage storage}) : _storage = storage {
    _ensureFoldersBox();
  }

  /// ID of the always-present default folder (`Tum favoriler`). Never
  /// shown in the rename/delete sheet, never deletable.
  static const String kDefaultFolderId = 'default';
  static const String _foldersBoxName = 'favorites_folders';

  final AwatvStorage _storage;
  final StreamController<Set<String>> _channelsCtrl =
      StreamController<Set<String>>.broadcast();
  final StreamController<List<FavoriteFolder>> _foldersCtrl =
      StreamController<List<FavoriteFolder>>.broadcast();

  Box<String>? _foldersBox;

  // ---------------------------------------------------------------------------
  // Channel-level favorites (legacy, unchanged)
  // ---------------------------------------------------------------------------

  Future<void> toggle(String channelId) async {
    final box = _storage.favoritesBox;
    if (box.containsKey(channelId)) {
      await box.delete(channelId);
      // Drop from every folder so the folder-count chips don't lie.
      await _removeChannelFromAllFolders(channelId);
    } else {
      await box.put(channelId, 1);
      // Auto-add to the default folder so the new favourite shows up
      // even when the user never opened the folders UI.
      await addChannelToFolder(kDefaultFolderId, channelId);
    }
    _channelsCtrl.add(_currentSet());
  }

  Future<bool> isFavorite(String channelId) async {
    return _storage.favoritesBox.containsKey(channelId);
  }

  Future<Set<String>> all() async => _currentSet();

  Stream<Set<String>> watch() async* {
    yield _currentSet();
    final box = _storage.favoritesBox;
    yield* box.watch().map((_) => _currentSet());
  }

  Set<String> _currentSet() {
    return _storage.favoritesBox.keys.cast<String>().toSet();
  }

  // ---------------------------------------------------------------------------
  // Folders
  // ---------------------------------------------------------------------------

  /// Returns every folder, including the always-present default. Sort
  /// order honours [FavoriteFolder.sortOrder]; ties broken alphabetically
  /// to keep the chip row stable across rebuilds.
  Future<List<FavoriteFolder>> listFolders() async {
    await _ensureDefaultFolder();
    return _readAllFolders();
  }

  /// Reactive folders list. Combines the folders Hive box and the
  /// channel-set stream so the channel-count badge on each chip
  /// updates whenever the user toggles a favourite from a different
  /// surface (the channel grid context sheet, the long-press menu, …).
  Stream<List<FavoriteFolder>> watchFolders() async* {
    await _ensureDefaultFolder();
    yield _readAllFolders();
    final box = _foldersBox;
    if (box == null) return;
    yield* box.watch().map((_) => _readAllFolders());
  }

  Future<FavoriteFolder> createFolder({
    required String name,
    int? color,
  }) async {
    await _ensureFoldersBox();
    final id = _generateFolderId();
    final folders = _readAllFolders();
    final next = FavoriteFolder(
      id: id,
      name: name.trim().isEmpty ? 'Yeni klasor' : name.trim(),
      color: color,
      sortOrder: folders.length,
      channelIds: const <String>[],
    );
    await _foldersBox!.put(id, jsonEncode(next.toJson()));
    _foldersCtrl.add(_readAllFolders());
    return next;
  }

  Future<void> renameFolder(String folderId, String newName) async {
    final box = _foldersBox;
    if (box == null) return;
    if (folderId == kDefaultFolderId) return;
    final raw = box.get(folderId);
    if (raw == null) return;
    try {
      final folder = FavoriteFolder.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      final clean = newName.trim();
      if (clean.isEmpty) return;
      final next = folder.copyWith(name: clean);
      await box.put(folderId, jsonEncode(next.toJson()));
      _foldersCtrl.add(_readAllFolders());
    } on Object {
      // Skip — corrupt folder records are rare; surfacing a stack
      // trace would do nothing for the user.
    }
  }

  Future<void> deleteFolder(String folderId) async {
    if (folderId == kDefaultFolderId) return;
    final box = _foldersBox;
    if (box == null) return;
    await box.delete(folderId);
    _foldersCtrl.add(_readAllFolders());
  }

  Future<void> reorderFolders(List<String> orderedIds) async {
    final box = _foldersBox;
    if (box == null) return;
    for (var i = 0; i < orderedIds.length; i++) {
      final id = orderedIds[i];
      final raw = box.get(id);
      if (raw == null) continue;
      try {
        final folder = FavoriteFolder.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        await box.put(id, jsonEncode(folder.copyWith(sortOrder: i).toJson()));
      } on Object {
        continue;
      }
    }
    _foldersCtrl.add(_readAllFolders());
  }

  Future<void> addChannelToFolder(String folderId, String channelId) async {
    final box = _foldersBox;
    if (box == null) return;
    final raw = box.get(folderId);
    if (raw == null) return;
    try {
      final folder = FavoriteFolder.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (folder.channelIds.contains(channelId)) return;
      final next = folder.copyWith(
        channelIds: <String>[...folder.channelIds, channelId],
      );
      await box.put(folderId, jsonEncode(next.toJson()));
      _foldersCtrl.add(_readAllFolders());
    } on Object {
      return;
    }
  }

  Future<void> removeChannelFromFolder(String folderId, String channelId) async {
    final box = _foldersBox;
    if (box == null) return;
    final raw = box.get(folderId);
    if (raw == null) return;
    try {
      final folder = FavoriteFolder.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (!folder.channelIds.contains(channelId)) return;
      final next = folder.copyWith(
        channelIds: <String>[
          for (final id in folder.channelIds)
            if (id != channelId) id,
        ],
      );
      await box.put(folderId, jsonEncode(next.toJson()));
      _foldersCtrl.add(_readAllFolders());
    } on Object {
      return;
    }
  }

  /// Moves [channelId] out of [fromFolderId] and into [toFolderId] in
  /// a single atomic burst (well, two writes — Hive boxes don't expose
  /// a transaction, but the burst is small enough that consumers will
  /// still see a coherent state).
  Future<void> moveChannelBetweenFolders({
    required String channelId,
    required String fromFolderId,
    required String toFolderId,
  }) async {
    if (fromFolderId == toFolderId) return;
    await removeChannelFromFolder(fromFolderId, channelId);
    await addChannelToFolder(toFolderId, channelId);
  }

  /// Returns every folder that contains [channelId]. Used by the
  /// "klasor degistir" sheet to highlight existing memberships.
  Future<List<String>> foldersForChannel(String channelId) async {
    final folders = _readAllFolders();
    return <String>[
      for (final f in folders)
        if (f.channelIds.contains(channelId)) f.id,
    ];
  }

  Future<void> _removeChannelFromAllFolders(String channelId) async {
    final box = _foldersBox;
    if (box == null) return;
    final folders = _readAllFolders();
    for (final f in folders) {
      if (!f.channelIds.contains(channelId)) continue;
      await removeChannelFromFolder(f.id, channelId);
    }
  }

  // ---------------------------------------------------------------------------
  // Internal hive box management
  // ---------------------------------------------------------------------------

  Future<void> _ensureFoldersBox() async {
    if (_foldersBox != null && _foldersBox!.isOpen) return;
    if (Hive.isBoxOpen(_foldersBoxName)) {
      _foldersBox = Hive.box<String>(_foldersBoxName);
      return;
    }
    try {
      _foldersBox = await Hive.openBox<String>(_foldersBoxName);
    } on Object {
      _foldersBox = null;
    }
  }

  Future<void> _ensureDefaultFolder() async {
    await _ensureFoldersBox();
    final box = _foldersBox;
    if (box == null) return;
    if (box.containsKey(kDefaultFolderId)) {
      // Refresh the channel-id list against the live channel-set so the
      // count chip stays correct after a free-tier user toggles a
      // favourite from elsewhere in the app.
      try {
        final raw = box.get(kDefaultFolderId)!;
        final folder = FavoriteFolder.fromJson(
          jsonDecode(raw) as Map<String, dynamic>,
        );
        final live = _currentSet();
        // Default folder always shadows the full set so the flat
        // back-compat view stays accurate.
        final patched = folder.copyWith(channelIds: live.toList());
        if (!_listEqUnordered(folder.channelIds, patched.channelIds)) {
          await box.put(kDefaultFolderId, jsonEncode(patched.toJson()));
        }
      } on Object {
        // Skip refresh on parse error.
      }
      return;
    }
    final defaults = FavoriteFolder(
      id: kDefaultFolderId,
      name: 'Tum favoriler',
      sortOrder: 0,
      channelIds: _currentSet().toList(),
    );
    await box.put(kDefaultFolderId, jsonEncode(defaults.toJson()));
  }

  List<FavoriteFolder> _readAllFolders() {
    final box = _foldersBox;
    if (box == null) return const <FavoriteFolder>[];
    final out = <FavoriteFolder>[];
    for (final raw in box.values) {
      try {
        out.add(
          FavoriteFolder.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      } on Object {
        continue;
      }
    }
    out.sort((FavoriteFolder a, FavoriteFolder b) {
      final order = a.sortOrder.compareTo(b.sortOrder);
      if (order != 0) return order;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  String _generateFolderId() {
    final ms = DateTime.now().toUtc().millisecondsSinceEpoch;
    return 'fav_${ms.toRadixString(36)}';
  }

  bool _listEqUnordered(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final aSet = a.toSet();
    for (final v in b) {
      if (!aSet.contains(v)) return false;
    }
    return true;
  }

  Future<void> dispose() async {
    if (!_channelsCtrl.isClosed) await _channelsCtrl.close();
    if (!_foldersCtrl.isClosed) await _foldersCtrl.close();
    final box = _foldersBox;
    if (box != null && box.isOpen) {
      try {
        await box.close();
      } on Object {
        // Best-effort — never block disposal.
      }
    }
    _foldersBox = null;
  }
}

/// One folder as persisted in the `favorites_folders` box.
class FavoriteFolder {
  const FavoriteFolder({
    required this.id,
    required this.name,
    required this.channelIds,
    required this.sortOrder,
    this.color,
  });

  /// Stable id — `default` for the always-present root folder, or
  /// `fav_<base36-time>` for user-created folders.
  final String id;

  /// Display name shown on the chip and the section header.
  final String name;

  /// Optional ARGB tint stored as int. Null falls back to the brand
  /// gradient on the chip.
  final int? color;

  /// Position in the chip row. Lower = leftmost. Default folder is
  /// always 0 unless the user explicitly reorders.
  final int sortOrder;

  /// Channel ids inside this folder, in user-defined order.
  final List<String> channelIds;

  bool get isDefault => id == FavoritesService.kDefaultFolderId;

  FavoriteFolder copyWith({
    String? name,
    int? color,
    int? sortOrder,
    List<String>? channelIds,
  }) {
    return FavoriteFolder(
      id: id,
      name: name ?? this.name,
      color: color ?? this.color,
      sortOrder: sortOrder ?? this.sortOrder,
      channelIds: channelIds ?? this.channelIds,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        if (color != null) 'color': color,
        'sortOrder': sortOrder,
        'channelIds': channelIds,
      };

  static FavoriteFolder fromJson(Map<String, dynamic> json) {
    return FavoriteFolder(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? 'Klasor',
      color: json['color'] is num ? (json['color'] as num).toInt() : null,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      channelIds: <String>[
        for (final raw in (json['channelIds'] as List? ?? const <dynamic>[]))
          if (raw is String) raw,
      ],
    );
  }
}
