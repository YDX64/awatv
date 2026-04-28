import 'package:flutter/foundation.dart';

/// Receiver kind for a [CastDevice].
///
/// Surfaced in the device-picker tile's subtitle so the user can tell at
/// a glance whether they're about to send to an Apple TV (AirPlay), a
/// Google Cast device (Chromecast / Google TV), or a generic DLNA
/// renderer found via SSDP.
enum CastDeviceKind { chromecast, airplay, dlna }

/// Human-readable label for a [CastDeviceKind] used in the picker.
extension CastDeviceKindLabel on CastDeviceKind {
  String get displayName => switch (this) {
        CastDeviceKind.chromecast => 'Chromecast',
        CastDeviceKind.airplay => 'AirPlay',
        CastDeviceKind.dlna => 'DLNA',
      };
}

/// A discoverable receiver on the local network.
///
/// We deliberately keep the model small — the underlying native SDKs
/// (Google Cast Framework, AVFoundation, MediaRouter) all use richer
/// device descriptors but every consumer in the AWAtv UI only needs
/// these four fields.
@immutable
class CastDevice {
  /// Builds a device descriptor.
  ///
  /// [id] must be stable across discovery cycles for the same physical
  /// receiver — the picker UI keys list tiles by this so reconnects don't
  /// shift positions while devices come and go.
  const CastDevice({
    required this.id,
    required this.name,
    required this.kind,
    this.manufacturer,
  });

  /// Stable unique id (e.g. Cast device unique-id, AirPlay route uid).
  final String id;

  /// Human-readable name as broadcast by the receiver itself.
  final String name;

  /// Optional manufacturer string ("Google", "Apple", "LG", …).
  final String? manufacturer;

  /// Which protocol this receiver speaks. Drives picker icon + label.
  final CastDeviceKind kind;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CastDevice &&
          other.id == id &&
          other.name == name &&
          other.manufacturer == manufacturer &&
          other.kind == kind;

  @override
  int get hashCode => Object.hash(id, name, manufacturer, kind);

  @override
  String toString() =>
      'CastDevice($kind, $name${manufacturer == null ? '' : ' [$manufacturer]'})';
}

/// Snapshot of the receiver-side playback state, mirrored to the local UI.
///
/// `position` / `total` follow the same semantics as the local
/// `PlayerState` family — `total == null` means a live stream where no
/// scrub bar makes sense. `currentTitle` matches the title we sent in
/// `CastMedia.title`, echoed back so a fresh subscriber can re-render
/// the now-playing label without holding extra state.
@immutable
class CastPlaybackState {
  const CastPlaybackState({
    this.position = Duration.zero,
    this.total,
    this.playing = false,
    this.volume = 1,
    this.currentTitle,
  });

  /// Idle / unknown — used while a freshly-connected session waits for
  /// its first state message.
  static const CastPlaybackState idle = CastPlaybackState();

  /// Receiver-reported position. Defaults to zero before the first
  /// status message arrives.
  final Duration position;

  /// Receiver-reported total duration; `null` for live streams.
  final Duration? total;

  /// True when the receiver is actively playing.
  final bool playing;

  /// 0..1, mirrors `CastEngine.setVolume`.
  final double volume;

  /// Title currently displayed on the TV.
  final String? currentTitle;

  /// Returns a copy with the named fields overridden. Pass
  /// `clearTotal: true` to explicitly null `total` (e.g. when switching
  /// from VOD to live).
  CastPlaybackState copyWith({
    Duration? position,
    Duration? total,
    bool clearTotal = false,
    bool? playing,
    double? volume,
    String? currentTitle,
    bool clearTitle = false,
  }) {
    return CastPlaybackState(
      position: position ?? this.position,
      total: clearTotal ? null : (total ?? this.total),
      playing: playing ?? this.playing,
      volume: volume ?? this.volume,
      currentTitle: clearTitle ? null : (currentTitle ?? this.currentTitle),
    );
  }
}

/// Sealed cast-session state surface emitted by `CastEngine.sessions`.
///
/// The picker UI switch-cases on this to render shimmer / device list /
/// connection spinner / connected badge without inspecting any other
/// engine state.
sealed class CastSession {
  const CastSession();
}

/// No discovery is running and no session is active.
final class CastIdle extends CastSession {
  const CastIdle();
}

/// Discovery is running but the SDK has not surfaced any devices yet.
final class CastDiscovering extends CastSession {
  const CastDiscovering();
}

/// Discovery returned at least one receiver. The list is the live snapshot;
/// new emissions arrive whenever devices appear or disappear.
final class CastDevicesAvailable extends CastSession {
  const CastDevicesAvailable(this.devices);

  final List<CastDevice> devices;
}

/// A connection attempt to [target] is in flight. The session transitions
/// to [CastConnected] on success or [CastError] on failure.
final class CastConnecting extends CastSession {
  const CastConnecting(this.target);

  final CastDevice target;
}

/// Active session — the receiver is playing (or paused) media we sent.
///
/// The [state] field updates in place via fresh emissions; subscribers
/// always receive the latest snapshot.
final class CastConnected extends CastSession {
  const CastConnected(this.target, this.state);

  final CastDevice target;
  final CastPlaybackState state;

  CastConnected withState(CastPlaybackState next) =>
      CastConnected(target, next);
}

/// The session reported a hard error. The engine resets back to
/// [CastIdle] after surfacing this so the picker can re-discover.
final class CastError extends CastSession {
  const CastError(this.message);

  final String message;
}
