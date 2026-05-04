import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
// `url_launcher` is resolved transitively via other plugins
// (verified in pubspec.lock). It is not yet listed in
// apps/mobile/pubspec.yaml; that addition is tracked outside this
// scope. Direct import is intentional here.
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';

/// Set of external IPTV/media players AWAtv knows how to deep-link into.
///
/// The values mirror the four PlayerType variants the Streas RN app
/// supports — see `docs/streas-port/player-spec.md` § 1.2 — minus the
/// `internal` engine, which is handled by the in-app player controller
/// directly and therefore is not part of this enum.
enum ExternalPlayer {
  /// VLC for mobile (VideoLAN). Cross-platform: iOS uses the
  /// `vlc-x-callback://` scheme, Android uses the package-targeted
  /// `intent:` URI for `org.videolan.vlc`.
  vlc,

  /// MX Player (J2 Interactive). Android-only — the iOS App Store
  /// build does not exist. We launch the Pro build first and fall
  /// back to the ad-supported Free build automatically.
  mxPlayer,

  /// nPlayer (Newin Inc.). iOS-only — the Android equivalent ships
  /// without a stable URL scheme so we do not advertise it.
  nPlayer,
}

/// Opens an [ExternalPlayer] with a stream URI.
///
/// The launcher mirrors the URI builders documented in
/// `docs/streas-port/player-spec.md` § 1.2, which in turn mirrors the
/// schemes the upstream RN app uses. Each player has its own platform
/// expectations:
///
/// * VLC iOS uses the `vlc-x-callback://` x-callback-url scheme so we
///   can pass the source URL via the `url` query parameter.
/// * VLC Android uses Android's `intent:` URI to target the
///   `org.videolan.vlc` package directly so the chooser dialog never
///   appears even if a system handler is registered for the URL.
/// * MX Player Pro / Free Android use the same intent shape but target
///   the package-id of each store build.
/// * nPlayer iOS uses the bespoke `nplayer-` scheme — the URL is
///   appended verbatim, not query-encoded, per the published doc.
///
/// On unsupported platforms (e.g. nPlayer on Android), the launcher
/// returns `false` immediately without attempting a launch.
class ExternalPlayerLauncher {
  /// Constructs a launcher with sensible defaults.
  const ExternalPlayerLauncher();

  /// Tries to open [streamUri] inside [player].
  ///
  /// Returns `true` when the OS confirmed it could route the URI to a
  /// handler app; `false` when the player is not installed, the
  /// platform does not support that player, or url_launcher refused
  /// the URI.
  ///
  /// [headers] is currently best-effort. VLC iOS does not surface a
  /// header pass-through in its x-callback-url contract, and Android
  /// intents accept only a constrained set of `Bundle` extras. We
  /// stash known-good keys (`User-Agent`, `Referer`) on Android via
  /// the `S.referer` / `S.user-agent` extras, which both VLC Android
  /// and MX Player parse.
  Future<bool> launch(
    ExternalPlayer player,
    Uri streamUri, {
    Map<String, String>? headers,
  }) async {
    if (kIsWeb) return false;

    final targetUri = _buildLaunchUri(player, streamUri, headers);
    if (targetUri == null) return false;

    try {
      // url_launcher returns false when no handler is registered for
      // the scheme. Wrap externally so a thrown PlatformException (no
      // suitable activity, sandbox refusal, etc.) is treated identically.
      final launched = await launchUrl(
        targetUri,
        mode: LaunchMode.externalApplication,
      );
      return launched;
    } on Object {
      return false;
    }
  }

  /// Returns the App Store / Play Store URI a caller should open when
  /// [launch] returns `false`. Lets the UI surface a one-tap "install"
  /// shortcut alongside the error toast. Returns `null` on platforms
  /// where the player is not advertised at all.
  Uri? storeUri(ExternalPlayer player) {
    if (kIsWeb) return null;
    final isIOS = !kIsWeb && Platform.isIOS;
    final isAndroid = !kIsWeb && Platform.isAndroid;

    switch (player) {
      case ExternalPlayer.vlc:
        if (isIOS) {
          return Uri.parse(
            'https://apps.apple.com/app/vlc-for-mobile/id650377962',
          );
        }
        if (isAndroid) {
          return Uri.parse(
            'https://play.google.com/store/apps/details?id=org.videolan.vlc',
          );
        }
        return null;
      case ExternalPlayer.mxPlayer:
        if (isAndroid) {
          return Uri.parse(
            'https://play.google.com/store/apps/details?id=com.mxtech.videoplayer.pro',
          );
        }
        return null;
      case ExternalPlayer.nPlayer:
        if (isIOS) {
          return Uri.parse('https://apps.apple.com/app/nplayer/id1116905928');
        }
        return null;
    }
  }

  /// Returns `true` when [player] is advertised on the running
  /// platform. Used by the picker sheet to hide rows the user has no
  /// chance of using (nPlayer on Android, MX Player on iOS, …).
  bool isPlatformSupported(ExternalPlayer player) {
    if (kIsWeb) return false;
    final isIOS = !kIsWeb && Platform.isIOS;
    final isAndroid = !kIsWeb && Platform.isAndroid;
    switch (player) {
      case ExternalPlayer.vlc:
        return isIOS || isAndroid;
      case ExternalPlayer.mxPlayer:
        return isAndroid;
      case ExternalPlayer.nPlayer:
        return isIOS;
    }
  }

  // --- URI builders -------------------------------------------------------

  Uri? _buildLaunchUri(
    ExternalPlayer player,
    Uri streamUri,
    Map<String, String>? headers,
  ) {
    if (kIsWeb) return null;
    final isIOS = Platform.isIOS;
    final isAndroid = Platform.isAndroid;

    switch (player) {
      case ExternalPlayer.vlc:
        if (isIOS) return _vlcIosUri(streamUri);
        if (isAndroid) return _vlcAndroidUri(streamUri, headers);
        return null;
      case ExternalPlayer.mxPlayer:
        if (isAndroid) return _mxPlayerAndroidUri(streamUri, headers);
        return null;
      case ExternalPlayer.nPlayer:
        if (isIOS) return _nPlayerIosUri(streamUri);
        return null;
    }
  }

  /// VLC iOS — `vlc-x-callback://x-callback-url/stream?url=<encoded>`.
  ///
  /// VLC's x-callback-url contract requires the source URL to be
  /// percent-encoded inside the `url` query parameter; the rest of the
  /// URI is fixed.
  Uri _vlcIosUri(Uri streamUri) {
    return Uri(
      scheme: 'vlc-x-callback',
      host: 'x-callback-url',
      path: '/stream',
      queryParameters: <String, String>{'url': streamUri.toString()},
    );
  }

  /// VLC Android — `intent:<encoded>#Intent;package=...;type=video/*;end`.
  ///
  /// Android intents accept the source URL as the URI body (must be
  /// percent-encoded). `package=` pins the resolution to VLC so the
  /// system never shows a chooser dialog.
  Uri _vlcAndroidUri(Uri streamUri, Map<String, String>? headers) {
    return _androidIntent(
      streamUri: streamUri,
      packageName: 'org.videolan.vlc',
      headers: headers,
    );
  }

  /// MX Player Android — Pro build. The Free build is launched as a
  /// fallback at call-site (see picker sheet) when the Pro intent
  /// resolves to "no handler".
  Uri _mxPlayerAndroidUri(Uri streamUri, Map<String, String>? headers) {
    return _androidIntent(
      streamUri: streamUri,
      packageName: 'com.mxtech.videoplayer.pro',
      headers: headers,
    );
  }

  /// nPlayer iOS — `nplayer-<encoded>` custom scheme. The URL is
  /// appended raw to the `nplayer-` prefix, with the original scheme
  /// preserved (e.g. `nplayer-https://...`).
  Uri _nPlayerIosUri(Uri streamUri) {
    return Uri.parse('nplayer-$streamUri');
  }

  /// Builds an Android `intent:` URI of the form documented in
  /// https://developer.chrome.com/docs/android/intents.
  ///
  /// Stashes the known-good HTTP override extras (`Referer`,
  /// `User-Agent`) so VLC / MX Player can replay header-gated streams.
  Uri _androidIntent({
    required Uri streamUri,
    required String packageName,
    Map<String, String>? headers,
  }) {
    final sb = StringBuffer('intent:')
      ..write(streamUri.toString())
      ..write('#Intent;')
      ..write('package=$packageName;')
      ..write('type=video/*;');

    if (headers != null && headers.isNotEmpty) {
      // Both VLC Android and MX Player look at these well-known extras.
      // Keys are not standardised so we send the most common shape;
      // unsupported keys are silently ignored by both apps.
      final ua = headers['User-Agent'] ?? headers['user-agent'];
      final referer = headers['Referer'] ?? headers['referer'];
      if (ua != null && ua.isNotEmpty) {
        sb.write('S.User-Agent=${Uri.encodeComponent(ua)};');
      }
      if (referer != null && referer.isNotEmpty) {
        sb.write('S.Referer=${Uri.encodeComponent(referer)};');
      }
    }

    sb.write('end');
    return Uri.parse(sb.toString());
  }
}

/// Display-side metadata for a player. Kept inside the launcher file so
/// the picker sheet has a single source of truth without having to
/// switch on the enum twice.
extension ExternalPlayerDisplay on ExternalPlayer {
  /// Public-facing label.
  String get displayName {
    switch (this) {
      case ExternalPlayer.vlc:
        return 'VLC';
      case ExternalPlayer.mxPlayer:
        return 'MX Player';
      case ExternalPlayer.nPlayer:
        return 'nPlayer';
    }
  }

  /// Human-friendly subtitle: which platform / variant we will reach.
  String get tagline {
    switch (this) {
      case ExternalPlayer.vlc:
        return 'VideoLAN — iOS ve Android';
      case ExternalPlayer.mxPlayer:
        return 'J2 Interactive — Android';
      case ExternalPlayer.nPlayer:
        return 'Newin — iOS';
    }
  }
}
