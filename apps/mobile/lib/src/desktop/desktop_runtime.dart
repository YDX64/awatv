import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'desktop_runtime.g.dart';

/// True when the current process is running on a desktop OS where we can
/// take over the OS window: macOS, Windows, or Linux.
///
/// `kIsWeb` is checked first because `Platform` from `dart:io` throws on
/// the web. Mobile (iOS / Android), Fuchsia and any unknown platform fall
/// through to `false`.
///
/// Kept `keepAlive` so the result is stable for the lifetime of the app —
/// we never expect form-factor to change at runtime on desktop.
@Riverpod(keepAlive: true)
bool isDesktopForm(Ref ref) {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}

/// Synchronous companion for non-widget code (boot path, plain Dart).
///
/// Use the provider above whenever a `Ref` is in scope; reach for this
/// only from `main()` or other places where Riverpod is not yet ready.
bool isDesktopRuntime() {
  if (kIsWeb) return false;
  return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
}
