import 'dart:io' show Platform;

import 'package:app_settings/app_settings.dart' as ext;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Which OS settings page to deep-link into.
///
/// Web / desktop have no equivalent screens — we hide the rows in the UI
/// before reaching this enum, and [openOsSettings] returns false silently
/// if called anyway.
enum OsSettingsPage {
  /// Top-level app settings (default; useful when permissions denied).
  app,

  /// Notification preferences.
  notifications,

  /// Wi-Fi list. Useful from "no internet" empty states.
  wifi,

  /// Battery / power optimization. Only meaningful on Android, where
  /// background-restricted AWAtv loses cloud sync.
  battery,

  /// Mobile data / cellular.
  cellular,

  /// Location services. Required for SSID detection on Android 13+.
  location,
}

/// Maps our internal enum onto `app_settings`'s vendor enum. Centralised
/// so the rest of the codebase doesn't import the plugin directly — that
/// keeps replacing the plugin a one-file change.
ext.AppSettingsType _mapType(OsSettingsPage kind) {
  switch (kind) {
    case OsSettingsPage.app:
      return ext.AppSettingsType.settings;
    case OsSettingsPage.notifications:
      return ext.AppSettingsType.notification;
    case OsSettingsPage.wifi:
      return ext.AppSettingsType.wifi;
    case OsSettingsPage.battery:
      return ext.AppSettingsType.batteryOptimization;
    case OsSettingsPage.cellular:
      return ext.AppSettingsType.dataRoaming;
    case OsSettingsPage.location:
      return ext.AppSettingsType.location;
  }
}

/// Open the OS-level settings screen identified by [kind].
///
/// Returns `true` when the deep link was dispatched, `false` when the
/// platform doesn't support deep-linking (web / Linux / Windows for most
/// pages). All exceptions are swallowed and surfaced to the caller via
/// the boolean — callers should branch on the return for fallback UI.
Future<bool> openOsSettings({
  required OsSettingsPage kind,
  bool asAnotherTask = false,
}) async {
  if (kIsWeb) return false;
  try {
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      // Linux / Windows: app_settings has only partial support and
      // typically only `settings` works. Return false for richer pages.
      if (kind != OsSettingsPage.app) return false;
    }
    await ext.AppSettings.openAppSettings(
      type: _mapType(kind),
      asAnotherTask: asAnotherTask,
    );
    return true;
  } on Object catch (e) {
    debugPrint('[AppSettingsHelper] openOsSettings failed: $e');
    return false;
  }
}

/// Convenience: surface a snackbar when the deep link is unavailable.
/// Callers wire this onto their tap handler so users on unsupported
/// platforms see something instead of a no-op.
Future<void> openOsSettingsOrToast(
  BuildContext context, {
  required OsSettingsPage kind,
  String? unavailableMessage,
}) async {
  final ok = await openOsSettings(kind: kind);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          unavailableMessage ?? 'Bu platformda sistem ayarlari acilamiyor.',
        ),
      ),
    );
  }
}
