import 'dart:io' show Platform;

import 'package:awatv_core/awatv_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// Production marketing landing page. Used by `shareApp` and as the deep
/// link target for `shareChannel` / `sharePlaylist` so a recipient
/// without AWAtv installed lands somewhere useful.
const String _kAppLanding = 'https://awa-tv.awastats.com';

/// Centralised share helpers.
///
/// Three entry points:
///   * `sharePlaylist` — share a playlist source URL to another AWAtv user.
///                       Strips Xtream credentials before sending.
///   * `shareChannel`  — share a deep link that opens a channel in AWAtv.
///   * `shareApp`      — share the marketing site + a one-line pitch.
///
/// All three are wrapped in try/catch — `share_plus` throws on web when
/// the user dismisses the picker, and on Linux when xdg-open is missing,
/// neither of which should crash the calling screen.
class ShareHelper {
  const ShareHelper._();

  /// Build the deep link the recipient can open inside their AWAtv. We
  /// route through the marketing site (which knows how to redirect into
  /// the installed app via the universal-link / app-link configuration)
  /// so users without AWAtv land on a "get the app" page instead of a
  /// dead `awatv://` scheme.
  static String channelDeepLink(String channelId) {
    return '$_kAppLanding/#/channel/${Uri.encodeComponent(channelId)}';
  }

  /// Strip Xtream creds. The persisted `PlaylistSource` carries username
  /// + password fields, but we never want those leaving the device via a
  /// share sheet — recipients can request their own credentials from the
  /// provider.
  static String sanitisedPlaylistUrl(PlaylistSource src) {
    final raw = src.url.trim();
    if (raw.isEmpty) return raw;
    try {
      final uri = Uri.parse(raw);
      // Strip query-embedded credentials (`?username=…&password=…`) too —
      // some Xtream panels ship the URL that way.
      final cleanQuery = <String, String>{};
      uri.queryParameters.forEach((String k, String v) {
        final lk = k.toLowerCase();
        if (lk == 'username' ||
            lk == 'password' ||
            lk == 'user' ||
            lk == 'pass') {
          return;
        }
        cleanQuery[k] = v;
      });
      final scrubbed = uri.replace(
        userInfo: '',
        queryParameters: cleanQuery.isEmpty ? null : cleanQuery,
      );
      return scrubbed.toString();
    } on Object {
      // Malformed URL: best we can do is return it untouched. The user
      // configured it themselves.
      return raw;
    }
  }

  /// Share a playlist source. Xtream credentials are scrubbed.
  static Future<void> sharePlaylist(
    BuildContext context,
    PlaylistSource src,
  ) async {
    final body = StringBuffer()
      ..writeln('AWAtv ile bu listeye bak: ${src.name}')
      ..writeln(sanitisedPlaylistUrl(src))
      ..writeln()
      ..writeln('AWAtv: $_kAppLanding');
    await _share(
      context,
      text: body.toString(),
      subject: '${src.name} - AWAtv',
    );
  }

  /// Share a single channel as a deep link. The recipient with AWAtv
  /// installed lands on the channel detail screen; without AWAtv, the
  /// landing page invites them to install it.
  static Future<void> shareChannel(
    BuildContext context,
    Channel channel,
  ) async {
    final link = channelDeepLink(channel.id);
    final body = StringBuffer()
      ..writeln('AWAtv ile bu kanali izle: ${channel.name}')
      ..writeln(link);
    await _share(
      context,
      text: body.toString(),
      subject: '${channel.name} - AWAtv',
    );
  }

  /// Share AWAtv itself with a small marketing pitch.
  static Future<void> shareApp(BuildContext context) async {
    const message =
        'AWAtv ile butun listelerini, EPG, film ve dizilerini tek '
        'uygulamada topla. Indir: $_kAppLanding';
    await _share(
      context,
      text: message,
      subject: 'AWAtv - Tek uygulamada IPTV',
    );
  }

  /// Internal: share helper with platform-aware origin rect for iPad
  /// popover anchoring (iPadOS requires it; phones ignore it).
  static Future<void> _share(
    BuildContext context, {
    required String text,
    String? subject,
  }) async {
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box != null && box.hasSize
          ? box.localToGlobal(Offset.zero) & box.size
          : null;
      await Share.share(
        text,
        subject: subject,
        sharePositionOrigin: origin,
      );
    } on Object catch (e) {
      debugPrint('[ShareHelper] share failed: $e');
      // Surface a snackbar only if the context is still alive — the
      // failure path is most often "user dismissed the picker", which is
      // not actually an error worth shouting about.
      if (context.mounted &&
          !kIsWeb &&
          (Platform.isLinux || Platform.isFuchsia)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu platformda paylasim desteklenmiyor.'),
          ),
        );
      }
    }
  }
}
