import 'package:awatv_mobile/src/shared/breakpoints/breakpoints.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'device_class_provider.g.dart';

/// Riverpod-shaped wrapper around [deviceClassFor].
///
/// Most widgets resolve the device class via `MediaQuery.sizeOf(context)`
/// during `build`, but for non-widget code (route guards, providers that
/// branch on form factor) the provider gives a single observable source.
///
/// The provider is **not** keepAlive — re-evaluated whenever a consumer
/// mounts so it always reflects the current MediaQuery.
@riverpod
DeviceClass deviceClass(Ref ref, BuildContext context) {
  return deviceClassFor(context);
}

/// `InheritedWidget`-style helper. Stick this near the top of the tree
/// when you want every descendant to read the device class without
/// re-resolving from MediaQuery on each rebuild.
///
/// Currently unused in the shell — kept for future surfaces (player,
/// settings) that want the value without a context-tree of their own.
class DeviceClassScope extends InheritedWidget {
  const DeviceClassScope({
    required this.deviceClass,
    required super.child,
    super.key,
  });

  final DeviceClass deviceClass;

  static DeviceClass of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<DeviceClassScope>();
    if (scope != null) return scope.deviceClass;
    return deviceClassFor(context);
  }

  @override
  bool updateShouldNotify(DeviceClassScope oldWidget) =>
      oldWidget.deviceClass != deviceClass;
}
