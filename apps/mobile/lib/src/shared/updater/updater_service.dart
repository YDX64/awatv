import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:awatv_mobile/src/desktop/desktop_runtime.dart';
import 'package:awatv_mobile/src/shared/updater/update_manifest.dart';
import 'package:awatv_mobile/src/shared/updater/update_state.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'updater_service.g.dart';

/// Stable URL — GitHub redirects this to whatever the latest published
/// release's `latest.json` asset is. Doesn't need an API token, doesn't
/// count against the unauthenticated REST rate limit.
const String _kManifestUrl =
    'https://github.com/YDX64/awatv/releases/latest/download/latest.json';

/// Network deadline for the manifest probe. Long enough to ride out a
/// flaky uplink; short enough that a silent boot-time check never blocks
/// any visible app surface.
const Duration _kManifestTimeout = Duration(seconds: 10);

/// Owner of the auto-update lifecycle for desktop builds.
///
/// All state transitions happen through the four public methods:
/// [checkForUpdates], [downloadUpdate], [installUpdate], [reset].
/// The notifier is `keepAlive` so the in-flight download keeps streaming
/// even if the settings screen is popped mid-progress.
@Riverpod(keepAlive: true)
class UpdaterService extends _$UpdaterService {
  Dio? _dio;
  CancelToken? _downloadCancel;

  @override
  UpdateState build() {
    ref.onDispose(() {
      try {
        _downloadCancel?.cancel('disposed');
      } on Object {
        // ignore
      }
      _dio?.close(force: true);
    });
    return const UpdateIdle();
  }

  /// Reach out to GitHub, decide if a newer version is on offer.
  ///
  /// `silent: true` means a no-update outcome leaves the state machine
  /// at [UpdateUpToDate] (or [UpdateIdle] on platforms that aren't
  /// supported). Errors during a silent check resolve to [UpdateIdle]
  /// instead of [UpdateError] so a transient outage doesn't pollute the
  /// settings UI on next boot.
  Future<void> checkForUpdates({bool silent = true}) async {
    if (kIsWeb) return;
    if (!_isSupportedDesktop) return;

    // Don't trample an in-flight download or install.
    final current = state;
    if (current is UpdateChecking ||
        current is UpdateDownloading ||
        current is UpdateInstalling) {
      return;
    }

    state = const UpdateChecking();

    try {
      final info = await PackageInfo.fromPlatform();
      final currentVersion = info.version;

      final dio = _ensureDio();
      final response = await dio
          .get<String>(
            _kManifestUrl,
            options: Options(
              responseType: ResponseType.plain,
              followRedirects: true,
              receiveTimeout: _kManifestTimeout,
              sendTimeout: _kManifestTimeout,
              headers: const <String, String>{
                'Accept': 'application/json',
              },
            ),
          )
          .timeout(_kManifestTimeout);

      final body = response.data;
      if (body == null || body.isEmpty) {
        throw const FormatException('Manifest body is empty');
      }
      final manifest = UpdateManifest.fromJson(body);
      final delta = compareVersions(manifest.version, currentVersion);
      if (delta <= 0) {
        state = UpdateUpToDate(
          currentVersion: currentVersion,
          checkedAt: DateTime.now(),
        );
        return;
      }

      final assetKey = _assetKeyForCurrentPlatform(manifest);
      final asset = assetKey == null ? null : manifest.assets[assetKey];
      if (asset == null) {
        // Manifest advertises a newer version but doesn't include an
        // asset we know how to install. Treat as "up to date" silently
        // so the user isn't pestered with an undeliverable update.
        state = UpdateUpToDate(
          currentVersion: currentVersion,
          checkedAt: DateTime.now(),
        );
        return;
      }

      final force =
          compareVersions(manifest.minimumVersion, currentVersion) > 0;

      state = UpdateAvailable(
        remoteVersion: manifest.version,
        notes: manifest.notes,
        downloadUrl: asset.url,
        sha256: asset.sha256,
        size: asset.size,
        assetFileName: _basenameFromUrl(asset.url),
        releasedAt: manifest.releasedAt,
        forceUpdate: force,
      );
    } on Object catch (error) {
      if (silent) {
        // A boot-time check that fails should not paint anything red in
        // the user's face. Drop quietly back to idle and try again on
        // next boot.
        if (kDebugMode) debugPrint('[updater] silent check failed: $error');
        state = const UpdateIdle();
        return;
      }
      state = UpdateError(message: _formatError(error));
    }
  }

  /// Stream-download the asset attached to the current
  /// [UpdateAvailable] state, verify its SHA-256, and move into
  /// [UpdateReadyToInstall]. No-ops on every other state.
  Future<void> downloadUpdate() async {
    final available = state;
    if (available is! UpdateAvailable) return;

    try {
      final cacheDir = await _resolveUpdateCacheDir();
      final destFile =
          File('${cacheDir.path}${Platform.pathSeparator}${available.assetFileName}');
      // If a previous attempt left a partial file behind, nuke it.
      if (destFile.existsSync()) {
        try {
          destFile.deleteSync();
        } on Object {
          // best effort
        }
      }

      _downloadCancel = CancelToken();
      state = UpdateDownloading(
        remoteVersion: available.remoteVersion,
        progress: 0,
        bytesReceived: 0,
        totalBytes: available.size,
      );

      final dio = _ensureDio();
      final declaredSize = available.size;
      await dio.download(
        available.downloadUrl,
        destFile.path,
        cancelToken: _downloadCancel,
        options: Options(
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 30),
        ),
        onReceiveProgress: (received, total) {
          // GitHub usually does send Content-Length, but we still fall
          // back to the manifest's declared size when it's missing.
          final divisor = total > 0 ? total : declaredSize;
          final pct = divisor > 0
              ? (received / divisor).clamp(0.0, 1.0)
              : 0.0;
          state = UpdateDownloading(
            remoteVersion: available.remoteVersion,
            progress: pct,
            bytesReceived: received,
            totalBytes: divisor,
          );
        },
      );

      // Stream-hash the freshly written file. Crypto's `sha256.bind`
      // pulls the entire file through chunk-by-chunk so even a 200 MB
      // installer never lands all-at-once in memory.
      final digest = await sha256.bind(destFile.openRead()).single;
      final got = digest.toString().toLowerCase();
      final want = available.sha256.toLowerCase();
      if (got != want) {
        try {
          destFile.deleteSync();
        } on Object {
          // best effort
        }
        state = UpdateError(
          message: 'İndirilen paket bütünlük doğrulamasını geçemedi.',
          previous: available,
        );
        return;
      }

      state = UpdateReadyToInstall(
        remoteVersion: available.remoteVersion,
        installerPath: destFile.path,
      );
    } on Object catch (error) {
      state = UpdateError(
        message: _formatError(error),
        previous: available,
      );
    }
  }

  /// Hand the verified payload to the OS installer and exit the running
  /// process. macOS does the swap in-place with `ditto`; Windows defers
  /// to the Inno Setup `awatv-setup.exe`.
  Future<void> installUpdate() async {
    final ready = state;
    if (ready is! UpdateReadyToInstall) return;

    state = UpdateInstalling(remoteVersion: ready.remoteVersion);

    try {
      if (Platform.isMacOS) {
        await _installMacos(ready.installerPath);
      } else if (Platform.isWindows) {
        await _installWindows(ready.installerPath);
      } else {
        // Linux desktop and any future surface fall through to a manual
        // open; the user finishes the install themselves.
        await _openExternally(ready.installerPath);
      }
      // Flutter's `exit(0)` is the cleanest way to drop the running
      // process so the freshly-installed copy can claim the focus.
      // Wrapped so a CI smoke-test that never replaces the binary
      // doesn't kill the test runner.
      if (!kDebugMode) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        exit(0);
      }
    } on Object catch (error) {
      state = UpdateError(
        message: _formatError(error),
        previous: ready,
      );
    }
  }

  /// Reset the lifecycle to [UpdateIdle]. Cancels any in-flight
  /// download. Called by the settings UI when the user dismisses an
  /// update card or after a failed install attempt.
  void reset() {
    try {
      _downloadCancel?.cancel('user-reset');
    } on Object {
      // ignore
    }
    state = const UpdateIdle();
  }

  // ---------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------

  bool get _isSupportedDesktop {
    if (kIsWeb) return false;
    if (!isDesktopRuntime()) return false;
    return Platform.isMacOS || Platform.isWindows;
  }

  Dio _ensureDio() {
    return _dio ??= Dio(
      BaseOptions(
        connectTimeout: _kManifestTimeout,
        receiveTimeout: const Duration(minutes: 30),
        headers: const <String, String>{
          'User-Agent': 'AWAtv-Updater/1.0',
        },
      ),
    );
  }

  /// Cache root for downloaded installers.
  ///
  /// macOS: `~/Library/Caches/AWAtv/updates`
  /// Windows: `%LOCALAPPDATA%\AWAtv\updates` (resolved via the platform
  /// path_provider — Flutter's `getApplicationSupportDirectory` already
  /// points at the right place under `%LOCALAPPDATA%`).
  Future<Directory> _resolveUpdateCacheDir() async {
    Directory base;
    if (Platform.isMacOS) {
      try {
        base = await getApplicationCacheDirectory();
      } on Object {
        base = await getApplicationSupportDirectory();
      }
    } else {
      base = await getApplicationSupportDirectory();
    }
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}updates',
    );
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Pick the asset that matches the running platform. Prefers .zip on
  /// macOS (scriptable in-place install) and the Inno installer on
  /// Windows (auto-elevated install).
  String? _assetKeyForCurrentPlatform(UpdateManifest manifest) {
    if (Platform.isMacOS) {
      if (manifest.assets.containsKey(UpdateAssetKey.macosZip)) {
        return UpdateAssetKey.macosZip;
      }
      if (manifest.assets.containsKey(UpdateAssetKey.macosDmg)) {
        return UpdateAssetKey.macosDmg;
      }
      return null;
    }
    if (Platform.isWindows) {
      if (manifest.assets.containsKey(UpdateAssetKey.windowsInstaller)) {
        return UpdateAssetKey.windowsInstaller;
      }
      if (manifest.assets.containsKey(UpdateAssetKey.windowsZip)) {
        return UpdateAssetKey.windowsZip;
      }
      return null;
    }
    return null;
  }

  String _basenameFromUrl(String url) {
    try {
      final segments = Uri.parse(url).pathSegments;
      if (segments.isEmpty) return 'awatv-update';
      final last = segments.last;
      return last.isEmpty ? 'awatv-update' : last;
    } on Object {
      return 'awatv-update';
    }
  }

  /// macOS install — ditto-extract the .zip straight into /Applications,
  /// strip the quarantine bit, and re-launch from the new location. If
  /// the user downloaded the .dmg instead we fall back to opening it in
  /// Finder (manual drag-to-Applications dance).
  Future<void> _installMacos(String pkgPath) async {
    final lower = pkgPath.toLowerCase();
    if (lower.endsWith('.zip')) {
      // ditto preserves resource forks / signing metadata that a plain
      // `unzip` would corrupt.
      final ditto = await Process.run(
        'ditto',
        <String>['-x', '-k', pkgPath, '/Applications/'],
      );
      if (ditto.exitCode != 0) {
        throw ProcessException(
          'ditto',
          <String>['-x', '-k', pkgPath, '/Applications/'],
          (ditto.stderr ?? '').toString(),
          ditto.exitCode,
        );
      }
      // Resolve the freshly-installed bundle so we can drop quarantine
      // and relaunch it. We don't hardcode the bundle name because
      // `flutter build macos` derives it from `pubspec.yaml`'s `name:`.
      final installed = await _findInstalledMacosApp();
      if (installed != null) {
        await Process.run('xattr', <String>['-dr', 'com.apple.quarantine', installed]);
        // v0.5.2/v0.5.3 race fix — `Process.run('open', ['-n', installed])`
        // followed immediately by `exit(0)` sometimes lost the relaunched
        // app to a Launch Services race (the parent process died before
        // `open` had handed the launch request off, so LS aborted the
        // child).
        //
        //   * `-n` — force a fresh instance even if a stale AWAtv is
        //     already running (otherwise we'd just refocus the old copy).
        //   * `-W` — make `open` *wait* for the new app to register
        //     itself with LS before returning. Without this the parent
        //     could exit while LS was still resolving the bundle.
        //   * `ProcessStartMode.detached` — let `open` (and the new app
        //     it launches) survive the parent's `exit(0)` further down
        //     in `installUpdate`. Without `detached` macOS would tear
        //     the relaunch process down with the rest of the parent's
        //     process group.
        await Process.start(
          'open',
          <String>['-n', '-W', installed],
          mode: ProcessStartMode.detached,
        );
      }
      return;
    }
    // .dmg or anything else — let the OS handle it. The user will see
    // the mounted volume and drag the app over manually.
    await _openExternally(pkgPath);
  }

  /// Windows install — fire the Inno Setup installer in /SILENT mode so
  /// the user doesn't have to click Next-Next-Finish, then exit. The
  /// installer's `[Run]` step is configured to relaunch the new build.
  Future<void> _installWindows(String installerPath) async {
    final lower = installerPath.toLowerCase();
    if (lower.endsWith('.exe')) {
      // /SILENT shows progress; /VERYSILENT hides it. We keep /SILENT so
      // a stuck install is still visible to the user.
      // ignore: discarded_futures
      unawaited(Process.start(
        installerPath,
        <String>['/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART'],
        mode: ProcessStartMode.detached,
      ));
      return;
    }
    // Portable .zip path — open Explorer at the file so the user can
    // unpack manually. Auto-extracting into Program Files would need
    // elevation we don't have.
    await _openExternally(installerPath);
  }

  Future<void> _openExternally(String path) async {
    if (Platform.isMacOS) {
      await Process.run('open', <String>[path]);
    } else if (Platform.isWindows) {
      // `start` is a cmd builtin, not a standalone exe.
      await Process.run('cmd', <String>['/c', 'start', '', path]);
    } else {
      await Process.run('xdg-open', <String>[path]);
    }
  }

  /// Walks /Applications looking for a freshly-installed AWAtv bundle.
  /// We match on Info.plist's CFBundleIdentifier rather than a hardcoded
  /// app name so a future bundle rename doesn't break the relaunch.
  Future<String?> _findInstalledMacosApp() async {
    try {
      final apps = Directory('/Applications');
      if (!apps.existsSync()) return null;
      for (final entry in apps.listSync(followLinks: false)) {
        if (entry is! Directory) continue;
        if (!entry.path.toLowerCase().endsWith('.app')) continue;
        final plist = File('${entry.path}/Contents/Info.plist');
        if (!plist.existsSync()) continue;
        final raw = plist.readAsStringSync();
        if (raw.contains('com.awastats.awatv') ||
            raw.contains('awatv_mobile') ||
            entry.path.toLowerCase().contains('awatv')) {
          return entry.path;
        }
      }
    } on Object {
      // best effort
    }
    return null;
  }

  String _formatError(Object error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return 'Bağlantı zaman aşımına uğradı.';
        case DioExceptionType.connectionError:
          return 'İnternet bağlantısı kurulamadı.';
        case DioExceptionType.badResponse:
          final code = error.response?.statusCode ?? 0;
          if (code == 404) {
            return 'Güncelleme manifesti bulunamadı.';
          }
          return 'Sunucu hatası ($code).';
        case DioExceptionType.cancel:
          return 'Güncelleme iptal edildi.';
        case DioExceptionType.badCertificate:
          return 'Güvenli bağlantı kurulamadı.';
        case DioExceptionType.unknown:
          return 'Güncelleme alınamadı: ${error.message ?? error.error}';
      }
    }
    if (error is FormatException) {
      return 'Güncelleme bilgisi okunamadı.';
    }
    if (error is FileSystemException) {
      return 'Disk hatası: ${error.message}';
    }
    return 'Beklenmeyen hata: $error';
  }
}

/// Small helper provider so non-async code (the boot-time launcher)
/// can read the current version without awaiting `package_info_plus`.
@Riverpod(keepAlive: true)
Future<String> currentAppVersion(Ref ref) async {
  if (kIsWeb) return '0.0.0';
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } on Object {
    return '0.0.0';
  }
}

/// Encodable view of the manifest endpoint — exposed for tests/diagnostics.
@visibleForTesting
String debugManifestUrl() => _kManifestUrl;

/// Convenience for tests — re-export jsonEncode so we never import dart:convert
/// from the test file just for a one-liner.
@visibleForTesting
String debugJsonEncode(Object value) => jsonEncode(value);
