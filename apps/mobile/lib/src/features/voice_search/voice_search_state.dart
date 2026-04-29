import 'package:flutter/foundation.dart';

/// Sealed lifecycle of a voice-search session.
///
/// The mic button reads the runtime [VoiceSearchState] to pick the
/// right glyph (idle / listening / error) and to decide whether a tap
/// should start, stop, or surface a permission help sheet.
@immutable
sealed class VoiceSearchState {
  const VoiceSearchState();
}

/// Engine has not been initialised yet (or it has been reset).
/// Pressing the mic in this state runs the bootstrap probe and may
/// surface the OS permission prompt.
class VoiceSearchIdle extends VoiceSearchState {
  const VoiceSearchIdle();
}

/// Engine is currently capturing audio. The associated [partial]
/// transcript is the latest hypothesis from the recogniser; the bar
/// reflects this so the user sees the words appear as they speak.
class VoiceSearchListening extends VoiceSearchState {
  const VoiceSearchListening({required this.partial});

  /// Latest hypothesis from the recogniser. Empty until the user
  /// actually starts speaking (~ first ~200 ms of silence).
  final String partial;

  VoiceSearchListening copyWith({String? partial}) {
    return VoiceSearchListening(partial: partial ?? this.partial);
  }
}

/// User-driven stop has fired and the engine is finishing up. The
/// final transcript is delivered separately via the controller's
/// `recognisedTextStream` so the UI can fan out to "trigger search"
/// once the engine commits.
class VoiceSearchProcessing extends VoiceSearchState {
  const VoiceSearchProcessing({this.partial = ''});

  /// Last known partial text, kept around so the search bar doesn't
  /// briefly clear before the final transcript lands.
  final String partial;
}

/// Permission prompt was either denied (one-shot) or denied "forever"
/// (the user has tapped "do not ask again"). The bar surfaces a
/// snackbar with a deep link into OS settings.
class VoiceSearchPermissionDenied extends VoiceSearchState {
  const VoiceSearchPermissionDenied({this.permanent = false});

  /// True iff the OS reported a "denied forever" — the prompt is
  /// non-recoverable in-app and the user must visit Settings.
  final bool permanent;
}

/// Speech recognition is unavailable on this platform / build (e.g.
/// Safari on the web). The mic button hides itself when this state
/// is observed.
class VoiceSearchUnsupported extends VoiceSearchState {
  const VoiceSearchUnsupported({this.reason});

  /// Optional human-readable reason, surfaced as a tooltip / snackbar
  /// when the user taps the placeholder mic icon for any reason.
  final String? reason;
}

/// Generic engine error — network failure, recogniser crash, etc.
/// Carries the platform error message so the UI can surface a useful
/// toast instead of "something went wrong".
class VoiceSearchError extends VoiceSearchState {
  const VoiceSearchError({required this.message});

  final String message;
}
