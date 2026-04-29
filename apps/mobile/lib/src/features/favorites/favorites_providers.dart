import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/channels/channels_providers.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Currently-selected folder id on the `/favorites` screen. Persisted
/// in Riverpod state only — switching folders should be lightweight
/// and survive only as long as the screen is mounted.
final selectedFavoriteFolderProvider = StateProvider<String>(
  (Ref ref) => FavoritesService.kDefaultFolderId,
);

/// Reactive folders list — re-emits every time the user creates,
/// renames, deletes a folder or moves a channel between folders.
final favoriteFoldersStreamProvider =
    StreamProvider<List<FavoriteFolder>>((Ref ref) {
  final svc = ref.watch(favoritesServiceProvider);
  return svc.watchFolders();
});

/// Channels that belong to the [selectedFavoriteFolderProvider]. Joins
/// the folder's channel-id list against the live channel pool so the
/// list stays in sync with playlist refreshes.
final folderChannelsProvider = FutureProvider.family<List<Channel>, String>(
    (Ref ref, String folderId) async {
  final folders = await ref.watch(favoriteFoldersStreamProvider.future);
  final channels = await ref.watch(liveChannelsProvider.future);
  final folder = folders.firstWhere(
    (FavoriteFolder f) => f.id == folderId,
    orElse: () => FavoriteFolder(
      id: folderId,
      name: 'Klasor',
      sortOrder: 0,
      channelIds: const <String>[],
    ),
  );
  final byId = <String, Channel>{
    for (final c in channels) c.id: c,
  };
  return <Channel>[
    for (final id in folder.channelIds)
      if (byId[id] != null) byId[id]!,
  ];
});
