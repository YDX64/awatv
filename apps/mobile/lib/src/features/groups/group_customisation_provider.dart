import 'package:awatv_mobile/src/features/groups/group_customisation_service.dart';
import 'package:awatv_mobile/src/features/home/category_tree_provider.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Service singleton — wraps prefs IO for group customisations.
final groupCustomisationServiceProvider =
    Provider<GroupCustomisationService>((Ref ref) {
  final svc = GroupCustomisationService(
    storage: ref.watch(awatvStorageProvider),
  );
  ref.onDispose(svc.dispose);
  return svc;
});

/// Reactive snapshot of every customisation persisted by the user.
final groupCustomisationsProvider =
    StreamProvider<GroupCustomisations>((Ref ref) async* {
  final svc = ref.watch(groupCustomisationServiceProvider);
  yield* svc.watch();
});

/// Customised view of [categoryTreeProvider] — sidebar / home / chips
/// consume this so reorder / hide / rename takes effect everywhere.
final customisedCategoryTreeProvider =
    FutureProvider<CategoryTree>((Ref ref) async {
  final raw = await ref.watch(categoryTreeProvider.future);
  final custom = ref.watch(groupCustomisationsProvider).valueOrNull ??
      GroupCustomisations.empty;
  return GroupCustomisationService.applyTo(raw, custom);
});
