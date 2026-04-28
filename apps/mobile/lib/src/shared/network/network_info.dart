import 'dart:async';
import 'dart:io' show Platform;

import 'package:awatv_mobile/src/shared/service_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:network_info_plus/network_info_plus.dart' as nip;
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'network_info.g.dart';

/// What kind of physical network we're on. The badge surfaces a tiny
/// glyph for each.
enum ConnectivityKind {
  none,
  wifi,
  cellular,
  ethernet,
  unknown,
}

/// One-shot snapshot of the current network state.
///
/// `ssid` / `bssid` / `ipv4` are best-effort: on iOS they require
/// `NSLocalNetworkUsageDescription` plus location-when-in-use entitlement
/// and only return values when granted; on Android 13+ they need fine
/// location access AND the user must have toggled the SSID consent flag
/// in onboarding (`prefs:network.ssidConsent`). On any platform a denied
/// permission produces null, never an exception.
@immutable
class NetworkSnapshot {
  const NetworkSnapshot({
    required this.kind,
    this.ssid,
    this.bssid,
    this.ipv4,
  });

  static const NetworkSnapshot offline = NetworkSnapshot(
    kind: ConnectivityKind.none,
  );

  final ConnectivityKind kind;
  final String? ssid;
  final String? bssid;
  final String? ipv4;

  bool get isOnline => kind != ConnectivityKind.none;

  /// True when the badge has enough data to render a meaningful chip.
  /// Onboarding hides the chip entirely when this is false to avoid an
  /// empty grey pill.
  bool get hasDisplayableInfo =>
      isOnline &&
      (kind == ConnectivityKind.cellular ||
          kind == ConnectivityKind.ethernet ||
          (ssid != null && ssid!.isNotEmpty));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NetworkSnapshot &&
          other.kind == kind &&
          other.ssid == ssid &&
          other.bssid == bssid &&
          other.ipv4 == ipv4;

  @override
  int get hashCode => Object.hash(kind, ssid, bssid, ipv4);
}

/// SSID consent storage. Stored in the global Hive `prefs` box under
/// `network.ssidConsent` (single boolean; absence = not yet asked).
@Riverpod(keepAlive: true)
class NetworkSsidConsent extends _$NetworkSsidConsent {
  static const String _key = 'network.ssidConsent';
  static const String _askedKey = 'network.ssidConsentAsked';

  @override
  bool build() {
    try {
      final prefs = ref.watch(awatvStorageProvider).prefsBox;
      return prefs.get(_key) == true;
    } on Object {
      return false;
    }
  }

  /// True iff onboarding has already shown the prompt at least once.
  /// We don't re-prompt automatically so we don't badger the user.
  bool get hasAsked {
    try {
      final prefs = ref.read(awatvStorageProvider).prefsBox;
      return prefs.get(_askedKey) == true;
    } on Object {
      return false;
    }
  }

  Future<void> grant() async {
    state = true;
    try {
      final prefs = ref.read(awatvStorageProvider).prefsBox;
      await prefs.put(_key, true);
      await prefs.put(_askedKey, true);
    } on Object {
      // Hive write failure is non-fatal — state still flipped in memory.
    }
  }

  Future<void> deny() async {
    state = false;
    try {
      final prefs = ref.read(awatvStorageProvider).prefsBox;
      await prefs.put(_key, false);
      await prefs.put(_askedKey, true);
    } on Object {
      // ignore: see grant().
    }
  }

  /// Reset for testing / re-prompt in settings.
  Future<void> reset() async {
    state = false;
    try {
      final prefs = ref.read(awatvStorageProvider).prefsBox;
      await prefs.delete(_key);
      await prefs.delete(_askedKey);
    } on Object {
      // ignore.
    }
  }
}

/// Continuously polls the network state. We cannot use platform
/// connectivity event streams on every supported platform (web, Linux),
/// so a 8s polling loop is the lowest-common-denominator that still
/// updates the badge promptly when Wi-Fi flips.
///
/// This stream is `keepAlive: true` because the home-screen header
/// subscribes to it; tearing it down between routes would produce
/// flicker.
@Riverpod(keepAlive: true)
class NetworkInfo extends _$NetworkInfo {
  static const Duration _interval = Duration(seconds: 8);

  // The package class is also called NetworkInfo; we alias it as `nip`
  // and only use `nip.NetworkInfo` from there.
  late final nip.NetworkInfo _native;
  bool _hasNative = false;

  @override
  Stream<NetworkSnapshot> build() async* {
    if (kIsWeb) {
      // Browsers can't tell us the SSID; render an "unknown / online"
      // placeholder so the chip stays sane.
      yield const NetworkSnapshot(kind: ConnectivityKind.unknown);
      return;
    }

    try {
      _native = nip.NetworkInfo();
      _hasNative = true;
    } on Object {
      _hasNative = false;
      yield NetworkSnapshot.offline;
      return;
    }

    final consent = ref.watch(networkSsidConsentProvider);
    var cancelled = false;
    ref.onDispose(() => cancelled = true);

    NetworkSnapshot? last;
    while (!cancelled) {
      final next = await _probe(consent: consent);
      if (next != last) {
        last = next;
        yield next;
      }
      await Future<void>.delayed(_interval);
    }
  }

  Future<NetworkSnapshot> _probe({required bool consent}) async {
    if (!_hasNative) return NetworkSnapshot.offline;
    try {
      // A non-null Wi-Fi IP indicates a routable interface. macOS /
      // Linux desktops typically return ethernet IPs through the same
      // call, so we promote those to ethernet.
      final ipv4 = await _safeAsync<String?>(_native.getWifiIP);
      final ConnectivityKind kind;
      if (ipv4 != null) {
        kind = (Platform.isMacOS || Platform.isLinux || Platform.isWindows)
            ? ConnectivityKind.ethernet
            : ConnectivityKind.wifi;
      } else if (Platform.isIOS || Platform.isAndroid) {
        // Mobile + no Wi-Fi IP means we're either offline or on cellular.
        // The package can't distinguish — assume cellular (the badge
        // simply renders a tower glyph; no functional impact).
        kind = ConnectivityKind.cellular;
      } else {
        kind = ConnectivityKind.none;
      }

      String? ssid;
      String? bssid;
      if (kind == ConnectivityKind.wifi && consent) {
        ssid = await _safeAsync<String?>(_native.getWifiName);
        bssid = await _safeAsync<String?>(_native.getWifiBSSID);
        // network_info_plus on iOS returns a quote-wrapped SSID — strip
        // the surrounding quotes so the chip text is clean.
        if (ssid != null && ssid.length >= 2) {
          if (ssid.startsWith('"') && ssid.endsWith('"')) {
            ssid = ssid.substring(1, ssid.length - 1);
          }
        }
        if (ssid == '<unknown ssid>' || ssid == '0x') ssid = null;
      }

      return NetworkSnapshot(
        kind: kind,
        ssid: ssid,
        bssid: bssid,
        ipv4: ipv4,
      );
    } on Object catch (e) {
      debugPrint('[NetworkInfo] probe failed: $e');
      return NetworkSnapshot.offline;
    }
  }

  Future<T?> _safeAsync<T>(Future<T?> Function() f) async {
    try {
      return await f();
    } on Object {
      return null;
    }
  }
}

/// Synchronous helper used in widgets that don't want the AsyncValue
/// machinery — falls back to offline when the stream hasn't emitted yet.
NetworkSnapshot networkSnapshotOrOffline(WidgetRef ref) {
  return ref.watch(networkInfoProvider).maybeWhen(
        data: (NetworkSnapshot s) => s,
        orElse: () => NetworkSnapshot.offline,
      );
}
