import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'downloads_providers.g.dart';

/// Reactive view onto every persisted download — running, paused,
/// completed, failed, cancelled. The screen splits these into tabs.
@Riverpod(keepAlive: true)
Stream<List<DownloadTask>> downloads(Ref ref) {
  final svc = ref.watch(downloadsServiceProvider);
  return svc.watch();
}

/// Convenience: the local on-disk path for a downloaded VOD or `null`
/// when the download is missing / partial.
@Riverpod()
Future<String?> downloadedLocalPath(Ref ref, String vodId) async {
  final svc = ref.watch(downloadsServiceProvider);
  return svc.localPathFor(vodId);
}
