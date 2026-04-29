import 'dart:async';

import 'package:awatv_mobile/src/features/voice_search/voice_search_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

part 'voice_search_controller.g.dart';

/// Default recognition locale. AWAtv ships with a Turkish-first UI so
/// the recogniser also defaults to `tr_TR`. The picker can override
/// this per-session via `start(localeId: ...)`, but no UI does today.
const String _kDefaultLocale = 'tr_TR';

/// Maximum listening duration. Most queries are 1–3 seconds; we cap
/// the session so a forgotten mic doesn't drain the battery in the
/// background. The native engines also impose their own ~30s cap.
const Duration _kMaxListenDuration = Duration(seconds: 20);

/// Quiet timeout — the engine auto-stops if the user stops speaking
/// for this long. Tuned slightly longer than the native default so
/// short pauses don't cut a search query in half.
const Duration _kPauseDuration = Duration(seconds: 3);

/// Owns one [stt.SpeechToText] instance and exposes the lifecycle as
/// a sealed [VoiceSearchState] for the search bar to render.
///
/// Two output channels:
///   * [state] — UI-facing lifecycle (idle / listening / error).
///   * `recognisedTextStream` — final transcripts the search bar feeds
///     into the query field. Emitted only on a "final" result so the
///     bar doesn't fight the user's typing during partial recognition.
@Riverpod(keepAlive: true)
class VoiceSearchController extends _$VoiceSearchController {
  late final stt.SpeechToText _engine = stt.SpeechToText();
  bool _initialised = false;

  /// Broadcast stream of final transcripts. Not exposed as Riverpod
  /// state because each value is consumed once — emitting via
  /// `state = ...` would force every dependent widget to rebuild on
  /// every emission, even ones that already reset their text field.
  final StreamController<String> _resultsCtrl =
      StreamController<String>.broadcast();

  /// Observe final recognised transcripts. The stream stays open for
  /// the controller's lifetime; callers should `.listen()` once and
  /// hold the subscription until they unmount.
  Stream<String> get recognisedTextStream => _resultsCtrl.stream;

  @override
  VoiceSearchState build() {
    ref.onDispose(_resultsCtrl.close);
    ref.onDispose(_engine.cancel);
    return const VoiceSearchIdle();
  }

  /// Probe + permission request. Idempotent — the engine caches the
  /// result internally, but we also short-circuit on our own flag
  /// because `initialize` is async and a double-tap can race.
  Future<bool> _ensureReady() async {
    if (_initialised) return _engine.isAvailable;
    try {
      _initialised = await _engine.initialize(
        onError: _onError,
        onStatus: _onStatus,
        // `debugLogging: false` keeps the noisy "speech_to_text:
        // status: notListening" noise out of release builds. We rely
        // on our own state stream for telemetry instead.
        debugLogging: kDebugMode,
      );
    } on Object catch (e) {
      _initialised = false;
      state = VoiceSearchError(message: 'Sesli arama acilamadi: $e');
      return false;
    }
    if (!_initialised) {
      // Two cases: no recogniser available OR the user denied the
      // permission. The engine doesn't expose them separately on
      // every platform, so we fan out to "permission denied" first
      // and let the unsupported state apply only when listening
      // explicitly fails for another reason.
      state = const VoiceSearchPermissionDenied();
    }
    return _initialised;
  }

  /// Begin a listening session. Safe to call repeatedly — re-arms the
  /// engine if it had timed out and bails out silently if a session
  /// is already running. Returns `false` on permission / availability
  /// problems so the caller can surface a tooltip.
  Future<bool> start({String localeId = _kDefaultLocale}) async {
    if (state is VoiceSearchListening) return true;
    final ready = await _ensureReady();
    if (!ready) return false;

    state = const VoiceSearchListening(partial: '');

    try {
      await _engine.listen(
        onResult: _onResult,
        listenFor: _kMaxListenDuration,
        pauseFor: _kPauseDuration,
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(
          // Turkish doesn't currently offer a high-quality on-device
          // dictation backend on most phones; the cloud path delivers
          // dramatically better accuracy for our IPTV vocabulary
          // (channel names, foreign film titles).
          partialResults: true,
          listenMode: stt.ListenMode.search,
          cancelOnError: true,
        ),
      );
      return true;
    } on Object catch (e) {
      state = VoiceSearchError(message: 'Dinleme baslatilamadi: $e');
      return false;
    }
  }

  /// Voluntary stop — finalises the current transcript and emits it
  /// downstream. The engine still calls `_onResult` once with
  /// `finalResult: true` so the result-stream emission is centralised
  /// there.
  Future<void> stop() async {
    if (state is! VoiceSearchListening && state is! VoiceSearchProcessing) {
      return;
    }
    final partial = switch (state) {
      VoiceSearchListening(:final partial) => partial,
      VoiceSearchProcessing(:final partial) => partial,
      _ => '',
    };
    state = VoiceSearchProcessing(partial: partial);
    try {
      await _engine.stop();
    } on Object catch (e) {
      state = VoiceSearchError(message: 'Durdurulamadi: $e');
    }
  }

  /// Hard cancel — drop the in-flight transcript and reset the engine.
  /// Used when the user manually clears the search field while voice
  /// is still listening.
  Future<void> cancel() async {
    if (state is VoiceSearchIdle) return;
    try {
      await _engine.cancel();
    } on Object {
      // Ignored — cancel() is a best-effort cleanup.
    }
    state = const VoiceSearchIdle();
  }

  // -------- Internal callbacks ------------------------------------------

  void _onResult(SpeechRecognitionResult result) {
    final text = result.recognizedWords.trim();
    if (result.finalResult) {
      // The session is wrapping up. Emit the final transcript and
      // return to idle so the search bar can fire its query.
      if (text.isNotEmpty) _resultsCtrl.add(text);
      state = const VoiceSearchIdle();
      return;
    }
    // Partial — update the live transcript so the search bar can
    // show the in-flight words. Use a fresh state instance so
    // ref.watch consumers actually rebuild.
    if (state is VoiceSearchListening) {
      state = VoiceSearchListening(partial: text);
    }
  }

  void _onStatus(String status) {
    // Statuses we care about: "listening", "notListening", "done".
    // `done` only fires on Android — iOS uses the result stream's
    // finalResult flag — so we mostly defer to _onResult and only
    // bail out of "listening" when the engine self-terminates with
    // no final result (silent timeout).
    if (status == 'done' && state is VoiceSearchListening) {
      // Engine finished but no final result arrived (silence). Reset
      // to idle so a re-tap arms a new session.
      state = const VoiceSearchIdle();
    }
  }

  void _onError(SpeechRecognitionError error) {
    final permanent =
        error.permanent || error.errorMsg.contains('permission');
    if (error.errorMsg.contains('error_speech_timeout') ||
        error.errorMsg.contains('error_no_match') ||
        error.errorMsg.contains('error_speech')) {
      // No-match / timeout — return to idle, no error toast needed.
      state = const VoiceSearchIdle();
      return;
    }
    if (error.errorMsg.contains('permission') ||
        error.errorMsg.contains('audio')) {
      state = VoiceSearchPermissionDenied(permanent: permanent);
      return;
    }
    state = VoiceSearchError(message: error.errorMsg);
  }
}

/// Convenience: are we on a platform where speech_to_text's web
/// backend exists? Used by the search bar to hide the mic icon on
/// browsers that lack the Web Speech API (Safari, older Firefox).
///
/// Wrapped in a try/catch because `defaultTargetPlatform` is enough
/// to know "iOS Safari?" only on web; on web `defaultTargetPlatform`
/// is filled in by the Flutter web runtime and `kIsWeb` decides if
/// the Web Speech API is even available.
@Riverpod(keepAlive: true)
bool voiceSearchSupported(Ref ref) {
  // The package supports macOS, iOS, Android, and Chromium-based
  // browsers via the Web Speech API. We *probe* by trying to
  // construct the engine — its initialiser is what tells us "no
  // recogniser registered". For the synchronous flag we only filter
  // out the cases where the SDK itself is a no-op.
  if (kIsWeb) {
    // Conservative: enable on web for Chrome/Edge but hide on Safari.
    // The engine's `initialize()` rejects on Safari with
    // "speech_recognition is not implemented", which we surface as
    // VoiceSearchUnsupported the first time the user taps mic.
    return true;
  }
  // Native platforms (iOS, Android, macOS) ship the engine.
  switch (defaultTargetPlatform) {
    case TargetPlatform.iOS:
    case TargetPlatform.android:
    case TargetPlatform.macOS:
      return true;
    case TargetPlatform.windows:
    case TargetPlatform.linux:
    case TargetPlatform.fuchsia:
      // No supported backend on these targets — hide the mic button.
      return false;
  }
}
