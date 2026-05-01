import 'dart:async';
import 'dart:io' show Platform;

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/shared/updater/update_state.dart';
import 'package:awatv_mobile/src/shared/updater/updater_service.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Mounted once at the app root. On desktop platforms it kicks off a
/// silent update check 5 seconds after first frame, then chains:
///
///   UpdateAvailable      → auto-start download (no user click required)
///   UpdateDownloading    → silent (settings card shows progress)
///   UpdateReadyToInstall → snackbar with "Şimdi Kur" button
///   UpdateError          → snackbar with "Detaylar" button → Settings
///
/// The previous implementation only surfaced a "yeni sürüm var" snackbar
/// and required the user to navigate to Settings, click "İndir ve kur",
/// wait for the download, then click "Yeniden başlat". On a sandboxed
/// build (v0.5.0/v0.5.1) the download succeeded but the install silently
/// failed because `Process.run('ditto', ...)` is blocked inside the App
/// Sandbox — the user just saw a green "yeni sürüm" message and nothing
/// happened. v0.5.2+ ships with sandbox disabled (see Release.entitlements)
/// AND auto-chains the update steps so the failure is impossible to miss.
class UpdateBootCheck extends ConsumerStatefulWidget {
  const UpdateBootCheck({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<UpdateBootCheck> createState() => _UpdateBootCheckState();
}

class _UpdateBootCheckState extends ConsumerState<UpdateBootCheck> {
  bool _kickedOff = false;
  // Track which version we've already surfaced to the user so a state
  // bounce (Available → Downloading → ReadyToInstall) doesn't spam the
  // snackbar queue with three "yeni sürüm" toasts.
  String? _surfacedAvailable;
  String? _surfacedReady;
  String? _surfacedError;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) return;
    if (!isDesktopRuntime()) return;
    if (!Platform.isMacOS && !Platform.isWindows) return;
    _kickedOff = true;
    // Run *after* the first frame so the boot animation isn't slowed
    // down by even a single network hop. The 5-second wait gives
    // Hive / Supabase a head start on warming up their connections.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Future<void>.delayed(const Duration(seconds: 5));
      if (!mounted) return;
      if (kDebugMode) {
        debugPrint('[updater] boot check: starting silent checkForUpdates');
      }
      // Don't await — a slow uplink shouldn't block any other work.
      unawaited(
        ref.read(updaterServiceProvider.notifier).checkForUpdates(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_kickedOff) {
      // Listen rather than build-watch — we react to transitions, not
      // to every rebuild that happens to coincide with downloading state.
      ref.listen<UpdateState>(updaterServiceProvider, (previous, next) {
        if (kDebugMode) {
          debugPrint(
            '[updater] state: ${previous.runtimeType} -> ${next.runtimeType}',
          );
        }
        if (next is UpdateAvailable &&
            _surfacedAvailable != next.remoteVersion) {
          _surfacedAvailable = next.remoteVersion;
          _onAvailable(next);
          return;
        }
        if (next is UpdateReadyToInstall &&
            _surfacedReady != next.remoteVersion) {
          _surfacedReady = next.remoteVersion;
          _onReady(next);
          return;
        }
        if (next is UpdateError) {
          // Errors get a one-shot toast per error message so a transient
          // network blip doesn't spam, but the user always learns when
          // an install or download truly fails.
          if (_surfacedError != next.message) {
            _surfacedError = next.message;
            _onError(next);
          }
        }
      });
    }
    return widget.child;
  }

  /// New version detected → auto-start the download. Surface a snackbar
  /// so the user knows the app is doing something on their behalf, but
  /// do NOT block on user interaction. The download happens in the
  /// background; the next snackbar fires when it's ready to install.
  void _onAvailable(UpdateAvailable available) {
    if (kDebugMode) {
      debugPrint(
        '[updater] available: v${available.remoteVersion} '
        '(${(available.size / (1024 * 1024)).toStringAsFixed(1)} MB) '
        '- starting auto-download',
      );
    }
    _showSnackbar(
      'Yeni sürüm bulundu (${available.remoteVersion}) — indiriliyor…',
      durationSeconds: 5,
      actionLabel: 'AYARLAR',
      onAction: () => _gotoSettings(),
    );
    // Fire-and-forget — UpdaterService handles its own state machine.
    unawaited(ref.read(updaterServiceProvider.notifier).downloadUpdate());
  }

  /// Download finished + sha256 verified → surface a louder, longer
  /// snackbar with the "Şimdi Kur" button. The user can dismiss; the
  /// installer file stays in the cache so the Settings card can pick up
  /// where the snackbar left off.
  void _onReady(UpdateReadyToInstall ready) {
    if (kDebugMode) {
      debugPrint('[updater] ready to install: v${ready.remoteVersion}');
    }
    _showSnackbar(
      'Sürüm ${ready.remoteVersion} hazır — şimdi kurmak ister misin?',
      durationSeconds: 12,
      actionLabel: 'ŞİMDİ KUR',
      onAction: () =>
          ref.read(updaterServiceProvider.notifier).installUpdate(),
    );
  }

  /// Surface errors loudly — silent failures are exactly what bit
  /// v0.5.0/v0.5.1 (sandbox-blocked install with no UI feedback).
  void _onError(UpdateError error) {
    if (kDebugMode) {
      debugPrint('[updater] error: ${error.message}');
    }
    _showSnackbar(
      'Güncelleme alınamadı: ${error.message}',
      durationSeconds: 10,
      actionLabel: 'DETAY',
      onAction: () => _gotoSettings(),
    );
  }

  void _showSnackbar(
    String message, {
    required int durationSeconds,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      if (kDebugMode) {
        debugPrint('[updater] no ScaffoldMessenger — skipping snackbar');
      }
      return;
    }
    messenger.showSnackBar(
      SnackBar(
        duration: Duration(seconds: durationSeconds),
        content: Text(message),
        action: SnackBarAction(
          label: actionLabel,
          onPressed: onAction,
        ),
      ),
    );
  }

  void _gotoSettings() {
    try {
      GoRouter.of(context).push('/settings');
    } on Object {
      // Routing not ready — user can still tap Settings manually.
    }
  }
}
