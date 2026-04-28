import 'dart:async';
import 'dart:io' show Platform;

import 'package:awatv_mobile/src/shared/discovery/discovered_iptv_server.dart';
import 'package:bonsoir/bonsoir.dart';
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'local_iptv_discovery.g.dart';

/// Bonjour service types we sweep for. Order matters: we surface results
/// from earlier types preferentially in the UI (Xtream first because its
/// presence is the strongest signal of an IPTV-aware host).
const List<String> _kBonjourTypes = <String>[
  '_xtream._tcp',
  '_iptv._tcp',
];

/// Streams a live, deduplicated list of IPTV-ish services discovered via
/// mDNS / Bonjour on the local network.
///
/// Behaviour by platform:
///   * iOS / macOS  — uses NSNetServiceBrowser via Bonsoir. `Info.plist`
///                    must list each `_xtream._tcp` / `_iptv._tcp` type
///                    inside `NSBonjourServices` AND grant
///                    `NSLocalNetworkUsageDescription`. Without these the
///                    discovery succeeds silently with zero results.
///   * Android      — uses NsdManager via Bonsoir. Requires
///                    `CHANGE_WIFI_MULTICAST_STATE` and (Android 12+)
///                    `NEARBY_WIFI_DEVICES`. Without permission the
///                    underlying call throws and we fall back to an empty
///                    stream — never blocks the screen.
///   * Web / Linux  — Bonsoir does not run; emits an empty list and stops.
///   * Windows / Desktop — Bonsoir 5.x supports Windows; if the platform
///                    isn't supported we emit a single empty value.
///
/// The provider is keepAlive so swapping between Add-Playlist tabs doesn't
/// retear down the discovery socket — that produced flicker in earlier
/// builds.
@Riverpod(keepAlive: true)
class LocalIptvDiscovery extends _$LocalIptvDiscovery {
  // Active per-type Bonsoir handles, indexed so we can clean up cleanly
  // even if the stream terminates abnormally.
  final List<BonsoirDiscovery> _active = <BonsoirDiscovery>[];

  // Live result table keyed by [DiscoveredIptvServer.key]. Insertions
  // happen on `serviceResolved`; removals on `serviceLost`.
  final Map<String, DiscoveredIptvServer> _found =
      <String, DiscoveredIptvServer>{};

  // Single broadcast controller so widgets (the add-playlist sheet) and
  // imperative callers (the search-screen long-press) can share the same
  // discovery socket without duplicating sockets.
  StreamController<List<DiscoveredIptvServer>>? _controller;

  @override
  Stream<List<DiscoveredIptvServer>> build() {
    if (!_supportsBonsoir()) {
      // Web / Linux / TV web build: never light up. Emit empty once and
      // stop. Consumers render a "scan unavailable on this platform"
      // placeholder upstream.
      return Stream<List<DiscoveredIptvServer>>.value(
        const <DiscoveredIptvServer>[],
      );
    }

    // Already running? Hand the existing controller's stream back.
    final existing = _controller;
    if (existing != null && !existing.isClosed) {
      return existing.stream;
    }

    final controller =
        StreamController<List<DiscoveredIptvServer>>.broadcast();
    _controller = controller;

    // Immediate seed value — many UIs expand the section as soon as
    // anything is delivered, even an empty list. Without this, the
    // expandable header stays in its loading shimmer forever when
    // discovery happens to find nothing.
    controller.add(<DiscoveredIptvServer>[]);

    // Fire-and-forget: errors in the kick-off propagate via the stream.
    unawaited(_startAll(controller));

    ref.onDispose(() async {
      await _stopAll();
      if (!controller.isClosed) {
        await controller.close();
      }
      _controller = null;
    });

    return controller.stream;
  }

  bool _supportsBonsoir() {
    if (kIsWeb) return false;
    try {
      // Bonsoir 5.x supports macOS / iOS / Android / Windows. Linux is a
      // no-op shim that throws on `start`.
      return Platform.isAndroid ||
          Platform.isIOS ||
          Platform.isMacOS ||
          Platform.isWindows;
    } on Object {
      // Platform check itself failed (extremely unlikely but harmless).
      return false;
    }
  }

  Future<void> _startAll(
    StreamController<List<DiscoveredIptvServer>> controller,
  ) async {
    for (final type in _kBonjourTypes) {
      try {
        final disc = BonsoirDiscovery(type: type);
        await disc.ready;
        await disc.start();
        _active.add(disc);

        // Each type runs its own subscription. We let them all funnel
        // into the shared controller; dedup is by full key so two types
        // advertising the same host:port don't collide.
        unawaited(_drain(disc, controller));
      } on Object catch (e, st) {
        debugPrint('[LocalIptvDiscovery] failed to start $type: $e\n$st');
        // Other types may still succeed; do not abort the whole loop.
      }
    }
  }

  Future<void> _drain(
    BonsoirDiscovery disc,
    StreamController<List<DiscoveredIptvServer>> controller,
  ) async {
    final eventStream = disc.eventStream;
    if (eventStream == null) return;

    try {
      await for (final ev in eventStream) {
        if (controller.isClosed) break;
        final svc = ev.service;

        switch (ev.type) {
          case BonsoirDiscoveryEventType.discoveryServiceFound:
            // Resolution is async on most platforms. Triggering it
            // synchronously means a later "resolved" event delivers the
            // full host/port we need.
            try {
              await svc?.resolve(disc.serviceResolver);
            } on Object {
              // Resolution failures are common when the device is busy
              // (e.g. Apple TV doing Cast). Skip silently.
            }
          case BonsoirDiscoveryEventType.discoveryServiceResolved:
            final resolved = svc;
            if (resolved is ResolvedBonsoirService) {
              final entry = DiscoveredIptvServer(
                name: resolved.name,
                host: resolved.host ?? '',
                port: resolved.port,
                type: resolved.type,
                attributes: Map<String, String>.from(resolved.attributes),
              );
              if (entry.host.isEmpty) break;
              _found[entry.key] = entry;
              controller.add(_snapshot());
            }
          case BonsoirDiscoveryEventType.discoveryServiceLost:
            if (svc != null) {
              final removed = _found.remove(
                '${svc.type}|${svc.name}|',
              );
              if (removed != null) {
                controller.add(_snapshot());
              } else {
                // Lost events arrive without a host; remove anything
                // matching the name+type tuple as a fallback.
                _found.removeWhere(
                  (String key, DiscoveredIptvServer v) =>
                      v.name == svc.name && v.type == svc.type,
                );
                controller.add(_snapshot());
              }
            }
          case BonsoirDiscoveryEventType.discoveryServiceResolveFailed:
          // ResolveFailed is logged by the platform code; we already
          // skip the result because no `host` ever arrives. Treat it as
          // a no-op for the result table.
          case BonsoirDiscoveryEventType.discoveryStarted:
          case BonsoirDiscoveryEventType.discoveryStopped:
          case BonsoirDiscoveryEventType.unknown:
            break;
        }
      }
    } on Object catch (e, st) {
      debugPrint('[LocalIptvDiscovery] drain error: $e\n$st');
      if (!controller.isClosed) {
        // Don't propagate as error — UI just keeps showing whatever it
        // already has. Discovery glitches are not user-actionable.
      }
    }
  }

  List<DiscoveredIptvServer> _snapshot() {
    final out = _found.values.toList(growable: false)
      ..sort((DiscoveredIptvServer a, DiscoveredIptvServer b) {
        // Xtream first (more useful), then alphabetical.
        if (a.type != b.type) {
          if (a.type.contains('xtream')) return -1;
          if (b.type.contains('xtream')) return 1;
        }
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    return out;
  }

  Future<void> _stopAll() async {
    for (final d in _active) {
      try {
        await d.stop();
      } on Object {
        // best-effort
      }
    }
    _active.clear();
    _found.clear();
  }
}
