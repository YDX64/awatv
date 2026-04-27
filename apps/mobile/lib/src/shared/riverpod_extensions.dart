import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Convenience helpers around `Ref` / `WidgetRef` that the AWAtv app uses
/// in many places. Centralised here to avoid copy-pasting.
extension AwatvRefX on Ref {
  /// Wrap an async function so any thrown exception is captured into an
  /// `AsyncError` instead of escaping. Returns `null` on failure — useful
  /// for one-shot actions where we already surface a SnackBar.
  Future<T?> guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object {
      return null;
    }
  }
}

extension AwatvWidgetRefX on WidgetRef {
  /// Same as [AwatvRefX.guard] but for `WidgetRef` (consumer widgets).
  Future<T?> guard<T>(Future<T> Function() body) async {
    try {
      return await body();
    } on Object {
      return null;
    }
  }
}
