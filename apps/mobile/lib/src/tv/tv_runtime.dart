import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'tv_runtime.g.dart';

/// Heuristic-based form-factor detection.
///
/// We deliberately keep this in pure Dart (no method channels) so the same
/// detection works on every platform. The thresholds match Android TV's
/// "10-foot UI" envelope:
///   - shortest side >= 960dp (a 1080p TV is ~960dp shortest in Flutter
///     units; phones in landscape rarely cross this).
///   - aspect ratio strongly landscape (>1.4) — TVs are 16:9 (1.78), phones
///     in landscape are typically 1.7+ but their shortest side stays small.
///
/// We can later upgrade this with a method channel that reads
/// `UI_MODE_TYPE_TELEVISION` from `UiModeManager` for an authoritative
/// answer on Android. Until then size-based detection is good enough and
/// keeps the same APK working on tablets-as-TVs and TV-emulators alike.
class TvRuntime {
  const TvRuntime._();

  /// Read the boot-time form factor from the platform dispatcher *before*
  /// any widget tree exists. Used to set the `isTvFormProvider` override
  /// inside `main`.
  ///
  /// Falls back to `false` (phone) on web, desktop and any platform where
  /// the metric is missing, so we never opt a non-TV device into the TV UI.
  static bool detectFromPlatform() {
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return false;
    final view = views.first;
    final dpr = view.devicePixelRatio == 0 ? 1.0 : view.devicePixelRatio;
    final size = view.physicalSize / dpr;
    if (size.width <= 0 || size.height <= 0) return false;
    return _matches(size.width, size.height);
  }

  /// Per-frame check for code that already has a `BuildContext` in hand —
  /// useful when responding to runtime configuration changes (e.g. the
  /// user docks an Android phone into a Samsung DeX TV mode).
  static bool isTv(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return false;
    final size = media.size;
    return _matches(size.width, size.height);
  }

  static bool _matches(double width, double height) {
    final shortest = width < height ? width : height;
    final longest = width < height ? height : width;
    if (shortest < 960) return false;
    final aspect = longest / shortest;
    return aspect > 1.4;
  }
}

/// Riverpod-exposed flag for the current form factor.
///
/// Default value is `false`; the real value is plumbed in via a
/// `ProviderScope` override in `main.dart` so the detection happens once at
/// boot. Hot-reload-safe — toggling the override in tests or in dev
/// rebuilds the entire app tree under the new shell.
@Riverpod(keepAlive: true)
bool isTvForm(Ref ref) => false;
