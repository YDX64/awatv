import 'dart:async';
import 'dart:io' show Platform;

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/shared/updater/update_state.dart';
import 'package:awatv_mobile/src/shared/updater/updater_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Mounted once at the app root. On desktop platforms it kicks off a
/// silent update check 5 seconds after first frame, then surfaces a
/// snackbar when an update is on offer so the user can jump to
/// /settings to install it.
///
/// Why a widget instead of `addPostFrameCallback` from `main.dart`?
/// We don't have a global `NavigatorKey`; the app root manages two
/// routers (TV vs phone). Living inside the widget tree means we can
/// pull a `BuildContext` for `ScaffoldMessenger` and `go_router` from
/// the very root of the app shell without any plumbing.
class UpdateBootCheck extends ConsumerStatefulWidget {
  const UpdateBootCheck({required this.child, super.key});
  final Widget child;

  @override
  ConsumerState<UpdateBootCheck> createState() => _UpdateBootCheckState();
}

class _UpdateBootCheckState extends ConsumerState<UpdateBootCheck> {
  bool _kickedOff = false;
  String? _surfacedVersion;

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
      // Don't await — a slow uplink shouldn't block any other work.
      unawaited(
        ref.read(updaterServiceProvider.notifier).checkForUpdates(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_kickedOff) {
      // Surface a one-time snackbar when the silent check resolves to
      // UpdateAvailable. We listen rather than build-watch so subsequent
      // state churn (download → ready) doesn't re-trigger the toast.
      ref.listen<UpdateState>(updaterServiceProvider, (previous, next) {
        if (next is UpdateAvailable && _surfacedVersion != next.remoteVersion) {
          _surfacedVersion = next.remoteVersion;
          _maybeSurfaceSnackbar(next);
        }
      });
    }
    return widget.child;
  }

  void _maybeSurfaceSnackbar(UpdateAvailable available) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text(
          "Yeni sürüm var (${available.remoteVersion}). Detaylar Ayarlar > Hakkında'da.",
        ),
        action: SnackBarAction(
          label: 'AÇ',
          onPressed: () {
            try {
              GoRouter.of(context).push('/settings');
            } on Object {
              // Routing not ready — user can still tap Settings manually.
            }
          },
        ),
      ),
    );
  }
}
