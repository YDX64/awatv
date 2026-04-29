import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'recordings_providers.g.dart';

/// Reactive view onto every persisted recording (running, scheduled,
/// completed, failed). The screen splits these into tabs.
@Riverpod(keepAlive: true)
Stream<List<RecordingTask>> recordings(Ref ref) {
  final svc = ref.watch(recordingServiceProvider);
  return svc.watch();
}
