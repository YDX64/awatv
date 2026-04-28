/// Sealed lifecycle of the desktop auto-updater.
///
/// The full happy path flows:
///   [UpdateIdle] → [UpdateChecking] → [UpdateAvailable] → [UpdateDownloading]
///   → [UpdateReadyToInstall] → [UpdateInstalling] → process exits.
///
/// The settings UI in `settings_screen.dart` switches over the runtime type
/// of the current state to render the right CTA. Anything that isn't on
/// the happy path (no network, manifest 404, sha mismatch, install failed)
/// resolves to either [UpdateUpToDate] (when the user-facing meaning is
/// "you're current") or [UpdateError] (anything else).
sealed class UpdateState {
  const UpdateState();
}

/// Initial state before any check has run. Also the resting state after a
/// failed install attempt where we want to let the user try again.
class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

/// A `checkForUpdates` round-trip is in flight. UI shows a spinner.
class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

/// Manifest fetched, current version >= manifest version. The
/// `checkedAt` timestamp drives the "Son kontrol: …" subtitle.
class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate({required this.currentVersion, required this.checkedAt});
  final String currentVersion;
  final DateTime checkedAt;
}

/// Manifest fetched, a newer version is available for the current
/// platform. The fields below are everything the download step needs —
/// no second manifest fetch required.
class UpdateAvailable extends UpdateState {
  const UpdateAvailable({
    required this.remoteVersion,
    required this.notes,
    required this.downloadUrl,
    required this.sha256,
    required this.size,
    required this.assetFileName,
    required this.releasedAt,
    required this.forceUpdate,
  });

  /// Semver string from manifest — e.g. "0.3.0". Always > current version
  /// when this state is emitted.
  final String remoteVersion;

  /// Free-form release notes from the manifest. Rendered as plain text.
  final String notes;

  /// Direct asset URL on github.com — already platform-correct.
  final String downloadUrl;

  /// Lowercase hex SHA-256 of the asset bytes. Verified post-download
  /// before we ever hand the file to the OS.
  final String sha256;

  /// Byte size of the asset, used for download-progress fallback when the
  /// server doesn't send Content-Length.
  final int size;

  /// Bare filename for the local cache write target — e.g.
  /// "awatv-macos.zip" or "awatv-setup.exe".
  final String assetFileName;

  /// When the manifest claims the release was published. Surfaced under
  /// the version line in the settings card.
  final DateTime? releasedAt;

  /// When the manifest's `minimumVersion` is newer than the current
  /// build the app must take the update — the UI hides the dismiss CTA.
  final bool forceUpdate;
}

/// Streaming download in flight. `progress` is `[0.0, 1.0]`.
class UpdateDownloading extends UpdateState {
  const UpdateDownloading({
    required this.remoteVersion,
    required this.progress,
    required this.bytesReceived,
    required this.totalBytes,
  });
  final String remoteVersion;
  final double progress;
  final int bytesReceived;
  final int totalBytes;
}

/// Bytes verified, file at `installerPath` is ready to hand off to the
/// platform installer. `installUpdate` consumes this state.
class UpdateReadyToInstall extends UpdateState {
  const UpdateReadyToInstall({
    required this.remoteVersion,
    required this.installerPath,
  });
  final String remoteVersion;
  final String installerPath;
}

/// `installUpdate` is running. On macOS this means the in-place ditto
/// extract is happening; on Windows the Inno installer is launching.
/// Process is about to call `exit(0)` so this state is short-lived.
class UpdateInstalling extends UpdateState {
  const UpdateInstalling({required this.remoteVersion});
  final String remoteVersion;
}

/// Anything went sideways — manifest unreachable, sha mismatch, install
/// process non-zero exit, etc. The `message` is user-facing Turkish.
/// `previous` retains the state we were trying to leave so the UI can
/// keep rendering the right CTA after a one-shot error.
class UpdateError extends UpdateState {
  const UpdateError({required this.message, this.previous});
  final String message;
  final UpdateState? previous;
}
