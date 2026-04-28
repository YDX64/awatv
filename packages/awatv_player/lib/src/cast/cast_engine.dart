import 'dart:async';

import 'package:awatv_player/src/cast/cast_media.dart';
import 'package:awatv_player/src/cast/cast_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Backend-agnostic surface for sending media to an external receiver
/// (Chromecast / AirPlay / DLNA).
///
/// Concrete implementations are picked up via [CastEngine.platform] —
/// callers should never instantiate a subclass directly. The factory
/// returns:
///
/// - [ChromecastEngine] on Android — drives Google Cast Framework via a
///   method/event-channel pair. The native plugin side lives in
///   `android/` and is intentionally out of scope for this Dart layer.
/// - [AirPlayEngine] on iOS — bridges to AVRoutePickerView and the
///   active AVAudioSession over a method/event channel.
/// - [NoOpCastEngine] on web / desktop / any other platform — emits
///   [CastIdle] permanently and rejects every attempted action with
///   [CastUnsupportedException]. The host UI is expected to hide its
///   cast affordances on these platforms.
///
/// Stream contract: [sessions] is a broadcast stream that always re-emits
/// the latest state to fresh subscribers. Implementations must guarantee
/// that the very first event seen by a new listener is the current state
/// (idle, discovering, devices-available, connected, …) so consumers
/// don't need a primer event.
abstract class CastEngine {
  CastEngine();

  /// Returns the right implementation for the running platform.
  ///
  /// The factory is cheap — implementations only spin up the underlying
  /// native plugin on first use (typically [startDiscovery]).
  factory CastEngine.platform() {
    if (kIsWeb) return NoOpCastEngine._('Cast desteği tarayıcıda kullanılamıyor.');
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return ChromecastEngine();
      case TargetPlatform.iOS:
        return AirPlayEngine();
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
      case TargetPlatform.linux:
      case TargetPlatform.fuchsia:
        return NoOpCastEngine._(
          'Cast desteği bu platformda mevcut değil.',
        );
    }
  }

  /// Live session-state stream. See class doc for the replay contract.
  Stream<CastSession> sessions();

  /// Returns the latest session snapshot synchronously. Useful for
  /// initial paints where the stream hasn't yet flushed its first event.
  CastSession get currentSession;

  /// Begins device discovery. Idempotent — calling twice is a no-op when
  /// discovery is already running.
  Future<void> startDiscovery();

  /// Stops device discovery. Implementations also stop publishing
  /// [CastDevicesAvailable] events; the last known list is discarded.
  Future<void> stopDiscovery();

  /// Connects to [device]. Resolves once the receiver-side session is
  /// fully attached. Listeners observe [CastConnecting] then
  /// [CastConnected] (or [CastError]).
  Future<void> connect(CastDevice device);

  /// Tears down the active session. Resolves once the receiver has been
  /// notified and the local state has reset to idle.
  Future<void> disconnect();

  /// Tells the receiver to load [media] and begin playback.
  ///
  /// Throws [CastNotConnectedException] when no session is active. The
  /// receiver-state stream surfaces decoding errors.
  Future<void> loadMedia(CastMedia media);

  /// Starts (or resumes) playback on the receiver.
  Future<void> play();

  /// Pauses playback on the receiver.
  Future<void> pause();

  /// Seeks to [to] on the receiver. No-op for live streams.
  Future<void> seek(Duration to);

  /// Sets receiver-side volume on a 0..1 scale. Implementations clamp
  /// out-of-range values silently.
  Future<void> setVolume(double volume);

  /// Releases native resources. Safe to call twice.
  Future<void> dispose();
}

/// Thrown when callers ask the engine to do something that requires an
/// active session (e.g. [CastEngine.loadMedia]) before [CastEngine.connect]
/// has resolved.
class CastNotConnectedException implements Exception {
  const CastNotConnectedException([this.message = 'Hiçbir cihaza bağlı değilsin.']);

  final String message;

  @override
  String toString() => 'CastNotConnectedException: $message';
}

/// Thrown by the no-op engine when the host is web / desktop. UI layers
/// can catch this and explain to the user why the action didn't take.
class CastUnsupportedException implements Exception {
  const CastUnsupportedException(this.message);

  final String message;

  @override
  String toString() => 'CastUnsupportedException: $message';
}

/// Shared scaffolding for engines that drive a real native receiver.
///
/// Owns the broadcast stream, snapshot caching, error-to-state mapping,
/// and the latest-known-device book-keeping. Subclasses override only
/// the platform-specific entry points: [doStartDiscovery],
/// [doStopDiscovery], [doConnect], [doDisconnect], [doLoadMedia],
/// [doPlay], [doPause], [doSeek], [doSetVolume].
@visibleForTesting
abstract class BaseCastEngine extends CastEngine {
  BaseCastEngine();

  final StreamController<CastSession> _sessionsCtrl =
      StreamController<CastSession>.broadcast();

  CastSession _state = const CastIdle();
  bool _disposed = false;

  @override
  CastSession get currentSession => _state;

  @override
  Stream<CastSession> sessions() async* {
    yield _state;
    yield* _sessionsCtrl.stream;
  }

  /// Pushes [next] to the stream and caches it. Skips identical
  /// consecutive states to avoid spamming the picker UI.
  @protected
  void emit(CastSession next) {
    if (_disposed) return;
    if (_isSameSession(_state, next)) return;
    _state = next;
    _sessionsCtrl.add(next);
  }

  /// Updates the state by passing the existing session through [mapper],
  /// useful for emitting device lists / playback updates without losing
  /// the current variant.
  @protected
  void update(CastSession Function(CastSession current) mapper) {
    emit(mapper(_state));
  }

  // --- Subclass extension points ----------------------------------------

  @protected
  Future<void> doStartDiscovery();
  @protected
  Future<void> doStopDiscovery();
  @protected
  Future<void> doConnect(CastDevice device);
  @protected
  Future<void> doDisconnect();
  @protected
  Future<void> doLoadMedia(CastMedia media);
  @protected
  Future<void> doPlay();
  @protected
  Future<void> doPause();
  @protected
  Future<void> doSeek(Duration to);
  @protected
  Future<void> doSetVolume(double volume);
  @protected
  Future<void> doDispose();

  // --- Public API: forwards to do* with state bookkeeping ----------------

  @override
  Future<void> startDiscovery() async {
    _ensureAlive();
    if (_state is CastConnected || _state is CastConnecting) return;
    if (_state is CastDiscovering || _state is CastDevicesAvailable) return;
    emit(const CastDiscovering());
    try {
      await doStartDiscovery();
    } on Object catch (e) {
      emit(CastError('Cihaz keşfi başlatılamadı: $e'));
      rethrow;
    }
  }

  @override
  Future<void> stopDiscovery() async {
    _ensureAlive();
    try {
      await doStopDiscovery();
    } on Object {
      // Best-effort.
    }
    if (_state is CastDiscovering || _state is CastDevicesAvailable) {
      emit(const CastIdle());
    }
  }

  @override
  Future<void> connect(CastDevice device) async {
    _ensureAlive();
    emit(CastConnecting(device));
    try {
      await doConnect(device);
      emit(CastConnected(device, CastPlaybackState.idle));
    } on Object catch (e) {
      emit(CastError('Cihaza bağlanılamadı: $e'));
      rethrow;
    }
  }

  @override
  Future<void> disconnect() async {
    _ensureAlive();
    try {
      await doDisconnect();
    } on Object {
      // Best-effort — we always reset state below.
    }
    emit(const CastIdle());
  }

  @override
  Future<void> loadMedia(CastMedia media) async {
    _ensureAlive();
    final s = _state;
    if (s is! CastConnected) {
      throw const CastNotConnectedException();
    }
    try {
      await doLoadMedia(media);
      emit(s.withState(s.state.copyWith(
        currentTitle: media.title,
        clearTitle: media.title == null,
        playing: true,
        position: media.startPosition,
      )));
    } on Object catch (e) {
      emit(CastError('Medya gönderilemedi: $e'));
      rethrow;
    }
  }

  @override
  Future<void> play() async {
    _ensureAlive();
    final s = _state;
    if (s is! CastConnected) throw const CastNotConnectedException();
    await doPlay();
    emit(s.withState(s.state.copyWith(playing: true)));
  }

  @override
  Future<void> pause() async {
    _ensureAlive();
    final s = _state;
    if (s is! CastConnected) throw const CastNotConnectedException();
    await doPause();
    emit(s.withState(s.state.copyWith(playing: false)));
  }

  @override
  Future<void> seek(Duration to) async {
    _ensureAlive();
    final s = _state;
    if (s is! CastConnected) throw const CastNotConnectedException();
    await doSeek(to);
    emit(s.withState(s.state.copyWith(position: to)));
  }

  @override
  Future<void> setVolume(double volume) async {
    _ensureAlive();
    final s = _state;
    if (s is! CastConnected) throw const CastNotConnectedException();
    final clamped = volume.clamp(0.0, 1.0);
    await doSetVolume(clamped);
    emit(s.withState(s.state.copyWith(volume: clamped)));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await doDispose();
    } on Object {
      // Best-effort.
    }
    if (!_sessionsCtrl.isClosed) {
      await _sessionsCtrl.close();
    }
  }

  void _ensureAlive() {
    if (_disposed) {
      throw StateError('CastEngine has been disposed.');
    }
  }

  bool _isSameSession(CastSession a, CastSession b) {
    if (a.runtimeType != b.runtimeType) return false;
    return switch (a) {
      CastIdle() => true,
      CastDiscovering() => true,
      CastDevicesAvailable(devices: final ad) =>
        b is CastDevicesAvailable && _listEquals(ad, b.devices),
      CastConnecting(target: final at) =>
        b is CastConnecting && b.target == at,
      CastConnected(target: final ct, state: final cs) =>
        b is CastConnected &&
            b.target == ct &&
            _statesEqual(cs, b.state),
      CastError(message: final m) => b is CastError && b.message == m,
    };
  }

  bool _listEquals(List<CastDevice> a, List<CastDevice> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _statesEqual(CastPlaybackState a, CastPlaybackState b) {
    return a.position == b.position &&
        a.total == b.total &&
        a.playing == b.playing &&
        a.volume == b.volume &&
        a.currentTitle == b.currentTitle;
  }
}

// ---------------------------------------------------------------------------
// ChromecastEngine — Android, Google Cast Framework via method/event channels.
// ---------------------------------------------------------------------------

/// Android-side engine that delegates to a native plugin over a pair of
/// `MethodChannel` + `EventChannel` interfaces.
///
/// The native plugin (lives under `android/` in this app, NOT in this
/// package) is expected to expose a method channel named
/// `awatv/cast` and an event channel `awatv/cast/events`. The protocol
/// is intentionally narrow:
///
/// Method calls (Dart -> native):
///   - `startDiscovery` / `stopDiscovery`
///   - `connect` { id }
///   - `disconnect`
///   - `loadMedia` { url, title, subtitle, artworkUrl, headers,
///                   contentType, streamType, startPositionMs }
///   - `play` / `pause`
///   - `seek` { positionMs }
///   - `setVolume` { volume }
///
/// Events (native -> Dart):
///   - `{ kind: 'devices', devices: [{ id, name, manufacturer, kind }] }`
///   - `{ kind: 'connecting', deviceId }`
///   - `{ kind: 'connected', deviceId }`
///   - `{ kind: 'disconnected' }`
///   - `{ kind: 'state', positionMs, totalMs?, playing, volume, title? }`
///   - `{ kind: 'error', message }`
///
/// When the plugin is missing at runtime (e.g. on a build that hasn't
/// been wired up yet) the method calls return `MissingPluginException`,
/// which we surface as a [CastError] so the user sees a Turkish copy
/// instead of a stack trace.
class ChromecastEngine extends BaseCastEngine {
  ChromecastEngine() {
    _eventSub = _events.receiveBroadcastStream().listen(
          _onNativeEvent,
          onError: (Object e, StackTrace _) {
            emit(CastError(_describePlatformError(e)));
          },
        );
  }

  static const MethodChannel _methods = MethodChannel('awatv/cast');
  static const EventChannel _events = EventChannel('awatv/cast/events');

  StreamSubscription<dynamic>? _eventSub;
  final Map<String, CastDevice> _knownDevices = <String, CastDevice>{};

  void _onNativeEvent(Object? raw) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final kind = map['kind'] as String?;
    switch (kind) {
      case 'devices':
        final list = (map['devices'] as List?) ?? const <Object?>[];
        final devices = <CastDevice>[];
        for (final entry in list) {
          if (entry is! Map) continue;
          final m = Map<String, dynamic>.from(entry);
          final id = m['id'] as String?;
          final name = m['name'] as String?;
          if (id == null || name == null) continue;
          final dev = CastDevice(
            id: id,
            name: name,
            manufacturer: m['manufacturer'] as String?,
            kind: _parseKind(m['kind'] as String?) ??
                CastDeviceKind.chromecast,
          );
          _knownDevices[id] = dev;
          devices.add(dev);
        }
        if (currentSession is CastIdle ||
            currentSession is CastDiscovering ||
            currentSession is CastDevicesAvailable) {
          emit(CastDevicesAvailable(List<CastDevice>.unmodifiable(devices)));
        }
      case 'connecting':
        final id = map['deviceId'] as String?;
        final dev = id == null ? null : _knownDevices[id];
        if (dev != null) emit(CastConnecting(dev));
      case 'connected':
        final id = map['deviceId'] as String?;
        final dev = id == null ? null : _knownDevices[id];
        if (dev != null) {
          emit(CastConnected(dev, CastPlaybackState.idle));
        }
      case 'disconnected':
        emit(const CastIdle());
      case 'state':
        final s = currentSession;
        if (s is! CastConnected) return;
        final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
        final totalMs = (map['totalMs'] as num?)?.toInt();
        final playing = (map['playing'] as bool?) ?? false;
        final volume = (map['volume'] as num?)?.toDouble() ?? s.state.volume;
        final title = map['title'] as String?;
        emit(s.withState(s.state.copyWith(
          position: Duration(milliseconds: positionMs),
          total: totalMs == null ? null : Duration(milliseconds: totalMs),
          clearTotal: totalMs == null,
          playing: playing,
          volume: volume,
          currentTitle: title,
          clearTitle: title == null,
        )));
      case 'error':
        final message = map['message'] as String? ?? 'Bilinmeyen hata';
        emit(CastError(message));
    }
  }

  CastDeviceKind? _parseKind(String? raw) {
    return switch (raw) {
      'chromecast' || 'cast' => CastDeviceKind.chromecast,
      'airplay' => CastDeviceKind.airplay,
      'dlna' => CastDeviceKind.dlna,
      _ => null,
    };
  }

  String _describePlatformError(Object e) {
    if (e is MissingPluginException) {
      return 'Chromecast eklentisi bu derlemede yüklü değil.';
    }
    return e.toString();
  }

  // --- BaseCastEngine -----------------------------------------------------

  @override
  Future<void> doStartDiscovery() async {
    try {
      await _methods.invokeMethod<void>('startDiscovery');
    } on MissingPluginException catch (_) {
      throw const CastUnsupportedException(
        'Chromecast eklentisi bu derlemede yüklü değil.',
      );
    }
  }

  @override
  Future<void> doStopDiscovery() async {
    try {
      await _methods.invokeMethod<void>('stopDiscovery');
    } on MissingPluginException {
      // Tolerated — nothing to stop if the plugin never started.
    }
  }

  @override
  Future<void> doConnect(CastDevice device) async {
    await _methods
        .invokeMethod<void>('connect', <String, Object?>{'id': device.id});
  }

  @override
  Future<void> doDisconnect() async {
    await _methods.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> doLoadMedia(CastMedia media) async {
    await _methods.invokeMethod<void>('loadMedia', media.toChannelMap());
  }

  @override
  Future<void> doPlay() async {
    await _methods.invokeMethod<void>('play');
  }

  @override
  Future<void> doPause() async {
    await _methods.invokeMethod<void>('pause');
  }

  @override
  Future<void> doSeek(Duration to) async {
    await _methods.invokeMethod<void>(
      'seek',
      <String, Object?>{'positionMs': to.inMilliseconds},
    );
  }

  @override
  Future<void> doSetVolume(double volume) async {
    await _methods
        .invokeMethod<void>('setVolume', <String, Object?>{'volume': volume});
  }

  @override
  Future<void> doDispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _methods.invokeMethod<void>('dispose');
    } on Object {
      // Best-effort.
    }
  }
}

// ---------------------------------------------------------------------------
// AirPlayEngine — iOS, AVRoutePicker + AVAudioSession via method channel.
// ---------------------------------------------------------------------------

/// iOS-side engine that bridges to AVFoundation's AirPlay APIs.
///
/// AirPlay 2 is intentionally lighter than Chromecast: the OS handles
/// routing transparently once the user picks a route from the system
/// picker presented by `AVRoutePickerView`. The engine therefore exposes
/// a "show picker" affordance via [showRoutePicker] in addition to the
/// generic [CastEngine] surface, and treats most playback commands as a
/// no-op for AirPlay (the local AVPlayer keeps decoding — the OS just
/// mirrors the audio/video out).
///
/// The native plugin is expected to expose method channel
/// `awatv/airplay` and event channel `awatv/airplay/events`. Method
/// calls supported:
///   - `startDiscovery`/`stopDiscovery` — toggle MPVolumeView observation
///   - `showRoutePicker` — programmatically surface AVRoutePickerView
///   - `connect` { id } — best-effort, AirPlay routing is OS-driven
///   - `disconnect` — sets active route back to the local speaker
///   - `loadMedia` — sets the now-playing center metadata
///   - `setVolume` — adjusts session volume
///
/// Events match the Chromecast schema so the UI layer can be uniform.
class AirPlayEngine extends BaseCastEngine {
  AirPlayEngine() {
    _eventSub = _events.receiveBroadcastStream().listen(
          _onNativeEvent,
          onError: (Object e, StackTrace _) {
            emit(CastError(_describePlatformError(e)));
          },
        );
  }

  static const MethodChannel _methods = MethodChannel('awatv/airplay');
  static const EventChannel _events = EventChannel('awatv/airplay/events');

  StreamSubscription<dynamic>? _eventSub;
  final Map<String, CastDevice> _knownDevices = <String, CastDevice>{};

  /// Shows the system-native AirPlay route picker. Preferred entry point
  /// over [connect] on iOS — Apple doesn't expose a public "connect to
  /// route X" API, so the picker is the only sanctioned UX.
  Future<void> showRoutePicker() async {
    try {
      await _methods.invokeMethod<void>('showRoutePicker');
    } on MissingPluginException {
      throw const CastUnsupportedException(
        'AirPlay yöneticisi bu derlemede yüklü değil.',
      );
    }
  }

  void _onNativeEvent(Object? raw) {
    if (raw is! Map) return;
    final map = Map<String, dynamic>.from(raw);
    final kind = map['kind'] as String?;
    switch (kind) {
      case 'devices':
        final list = (map['devices'] as List?) ?? const <Object?>[];
        final devices = <CastDevice>[];
        for (final entry in list) {
          if (entry is! Map) continue;
          final m = Map<String, dynamic>.from(entry);
          final id = m['id'] as String?;
          final name = m['name'] as String?;
          if (id == null || name == null) continue;
          final dev = CastDevice(
            id: id,
            name: name,
            manufacturer: m['manufacturer'] as String? ?? 'Apple',
            kind: CastDeviceKind.airplay,
          );
          _knownDevices[id] = dev;
          devices.add(dev);
        }
        if (currentSession is CastIdle ||
            currentSession is CastDiscovering ||
            currentSession is CastDevicesAvailable) {
          emit(CastDevicesAvailable(List<CastDevice>.unmodifiable(devices)));
        }
      case 'connected':
        final id = map['deviceId'] as String?;
        final dev = id == null ? null : _knownDevices[id];
        if (dev != null) {
          emit(CastConnected(dev, CastPlaybackState.idle));
        }
      case 'disconnected':
        emit(const CastIdle());
      case 'state':
        final s = currentSession;
        if (s is! CastConnected) return;
        final positionMs = (map['positionMs'] as num?)?.toInt() ?? 0;
        final totalMs = (map['totalMs'] as num?)?.toInt();
        final playing = (map['playing'] as bool?) ?? false;
        final volume = (map['volume'] as num?)?.toDouble() ?? s.state.volume;
        final title = map['title'] as String?;
        emit(s.withState(s.state.copyWith(
          position: Duration(milliseconds: positionMs),
          total: totalMs == null ? null : Duration(milliseconds: totalMs),
          clearTotal: totalMs == null,
          playing: playing,
          volume: volume,
          currentTitle: title,
          clearTitle: title == null,
        )));
      case 'error':
        final message = map['message'] as String? ?? 'Bilinmeyen hata';
        emit(CastError(message));
    }
  }

  String _describePlatformError(Object e) {
    if (e is MissingPluginException) {
      return 'AirPlay eklentisi bu derlemede yüklü değil.';
    }
    return e.toString();
  }

  // --- BaseCastEngine -----------------------------------------------------

  @override
  Future<void> doStartDiscovery() async {
    try {
      await _methods.invokeMethod<void>('startDiscovery');
    } on MissingPluginException {
      throw const CastUnsupportedException(
        'AirPlay yöneticisi bu derlemede yüklü değil.',
      );
    }
  }

  @override
  Future<void> doStopDiscovery() async {
    try {
      await _methods.invokeMethod<void>('stopDiscovery');
    } on MissingPluginException {
      // Tolerated.
    }
  }

  @override
  Future<void> doConnect(CastDevice device) async {
    // Apple does not expose a programmatic "connect to route" API; the
    // sanctioned flow is to surface AVRoutePickerView and let the user
    // pick. We still call the channel — the native side may try a
    // best-effort routing change for AirPlay 2 receivers it knows about.
    await _methods.invokeMethod<void>(
      'connect',
      <String, Object?>{'id': device.id},
    );
  }

  @override
  Future<void> doDisconnect() async {
    await _methods.invokeMethod<void>('disconnect');
  }

  @override
  Future<void> doLoadMedia(CastMedia media) async {
    await _methods.invokeMethod<void>('loadMedia', media.toChannelMap());
  }

  @override
  Future<void> doPlay() async {
    // AirPlay routes the local AVPlayer's audio/video to the receiver —
    // the local player's `play()` is what drives playback. We still
    // forward in case the native side is keeping its own MPNowPlayingInfo
    // state in sync.
    try {
      await _methods.invokeMethod<void>('play');
    } on MissingPluginException {
      // Harmless on AirPlay; local player will keep playing.
    }
  }

  @override
  Future<void> doPause() async {
    try {
      await _methods.invokeMethod<void>('pause');
    } on MissingPluginException {
      // Harmless on AirPlay.
    }
  }

  @override
  Future<void> doSeek(Duration to) async {
    try {
      await _methods.invokeMethod<void>(
        'seek',
        <String, Object?>{'positionMs': to.inMilliseconds},
      );
    } on MissingPluginException {
      // Harmless on AirPlay.
    }
  }

  @override
  Future<void> doSetVolume(double volume) async {
    try {
      await _methods.invokeMethod<void>(
        'setVolume',
        <String, Object?>{'volume': volume},
      );
    } on MissingPluginException {
      // Harmless on AirPlay.
    }
  }

  @override
  Future<void> doDispose() async {
    await _eventSub?.cancel();
    _eventSub = null;
    try {
      await _methods.invokeMethod<void>('dispose');
    } on Object {
      // Best-effort.
    }
  }
}

// ---------------------------------------------------------------------------
// NoOpCastEngine — web / desktop / unsupported platforms.
// ---------------------------------------------------------------------------

/// Inert engine for platforms with no native cast implementation.
///
/// Sticks to [CastIdle] forever, refuses [connect] / [loadMedia] /
/// `AirPlayEngine.showRoutePicker` with [CastUnsupportedException], and
/// tolerates [startDiscovery] / [stopDiscovery] as no-ops so callers
/// don't have to branch on platform.
///
/// [unsupportedReason] is surfaced verbatim in errors so the host UI can
/// explain to the user why the cast affordance is missing.
class NoOpCastEngine extends CastEngine {
  NoOpCastEngine._(this.unsupportedReason);

  /// Test seam — lets unit tests construct a NoOp engine without
  /// going through the platform factory. Production code should use
  /// [CastEngine.platform] which returns a NoOp on unsupported
  /// platforms automatically.
  @visibleForTesting
  factory NoOpCastEngine.fromReason(String reason) =>
      NoOpCastEngine._(reason);

  final String unsupportedReason;

  final StreamController<CastSession> _sessionsCtrl =
      StreamController<CastSession>.broadcast();

  bool _disposed = false;

  @override
  CastSession get currentSession => const CastIdle();

  @override
  Stream<CastSession> sessions() async* {
    yield const CastIdle();
    yield* _sessionsCtrl.stream;
  }

  @override
  Future<void> startDiscovery() async {
    // No-op — keeps consumers branchless.
  }

  @override
  Future<void> stopDiscovery() async {
    // No-op.
  }

  @override
  Future<void> connect(CastDevice device) async {
    throw CastUnsupportedException(unsupportedReason);
  }

  @override
  Future<void> disconnect() async {
    // No-op — there's no session to tear down.
  }

  @override
  Future<void> loadMedia(CastMedia media) async {
    throw CastUnsupportedException(unsupportedReason);
  }

  @override
  Future<void> play() async {
    throw CastUnsupportedException(unsupportedReason);
  }

  @override
  Future<void> pause() async {
    throw CastUnsupportedException(unsupportedReason);
  }

  @override
  Future<void> seek(Duration to) async {
    throw CastUnsupportedException(unsupportedReason);
  }

  @override
  Future<void> setVolume(double volume) async {
    throw CastUnsupportedException(unsupportedReason);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    if (!_sessionsCtrl.isClosed) await _sessionsCtrl.close();
  }
}
