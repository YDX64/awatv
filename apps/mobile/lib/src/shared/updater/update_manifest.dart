import 'dart:convert';

/// Parsed view of `latest.json` published alongside every GitHub release.
///
/// Schema (v1):
/// ```json
/// {
///   "version": "0.3.0",
///   "releasedAt": "2026-04-28T20:00:00Z",
///   "notes": "Cloud sync, provider intelligence, VLC backend.",
///   "minimumVersion": "0.2.0",
///   "channels": {
///     "stable": {
///       "macos":             { "url": "...", "sha256": "...", "size": 44106772 },
///       "macos-zip":         { "url": "...", "sha256": "...", "size": 33106772 },
///       "windows-installer": { "url": "...", "sha256": "...", "size": 28100000 },
///       "windows-zip":       { "url": "...", "sha256": "...", "size": 31100000 }
///     }
///   }
/// }
/// ```
///
/// Only the `stable` channel is read by the current build; richer
/// per-channel routing is reserved for a future "beta opt-in" toggle.
class UpdateManifest {
  const UpdateManifest({
    required this.version,
    required this.notes,
    required this.minimumVersion,
    required this.assets,
    this.releasedAt,
  });

  factory UpdateManifest.fromJson(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Manifest is not a JSON object');
    }
    final version = (decoded['version'] as String?)?.trim();
    if (version == null || version.isEmpty) {
      throw const FormatException('Manifest is missing "version"');
    }
    final notes = (decoded['notes'] as String?) ?? '';
    final minimumVersion =
        (decoded['minimumVersion'] as String?)?.trim() ?? version;
    final releasedAtStr = decoded['releasedAt'] as String?;
    DateTime? releasedAt;
    if (releasedAtStr != null && releasedAtStr.isNotEmpty) {
      releasedAt = DateTime.tryParse(releasedAtStr);
    }

    final channels = decoded['channels'];
    if (channels is! Map<String, dynamic>) {
      throw const FormatException('Manifest is missing "channels"');
    }
    final stable = channels['stable'];
    if (stable is! Map<String, dynamic>) {
      throw const FormatException('Manifest is missing channels.stable');
    }
    final assets = <String, UpdateAsset>{};
    stable.forEach((key, raw) {
      if (raw is Map<String, dynamic>) {
        try {
          assets[key] = UpdateAsset.fromJson(raw);
        } on FormatException {
          // Skip the broken row but keep the rest — a partial manifest is
          // better than a hard 5xx for the user. Diagnostics happen via
          // the UpdateError surface if no usable asset remains.
        }
      }
    });
    if (assets.isEmpty) {
      throw const FormatException('Manifest has no usable assets');
    }
    return UpdateManifest(
      version: version,
      notes: notes,
      minimumVersion: minimumVersion,
      releasedAt: releasedAt,
      assets: assets,
    );
  }

  final String version;
  final String notes;
  final String minimumVersion;
  final DateTime? releasedAt;

  /// Keyed by canonical asset slug — see [UpdateAssetKey].
  final Map<String, UpdateAsset> assets;
}

/// A single downloadable asset row. The triple url/sha/size is the
/// minimum we need to do an integrity-checked download.
class UpdateAsset {
  const UpdateAsset({
    required this.url,
    required this.sha256,
    required this.size,
  });

  factory UpdateAsset.fromJson(Map<String, dynamic> json) {
    final url = (json['url'] as String?)?.trim();
    final sha = (json['sha256'] as String?)?.trim();
    final size = (json['size'] as num?)?.toInt() ?? 0;
    if (url == null || url.isEmpty) {
      throw const FormatException('Asset is missing "url"');
    }
    if (sha == null || sha.isEmpty) {
      throw const FormatException('Asset is missing "sha256"');
    }
    return UpdateAsset(url: url, sha256: sha.toLowerCase(), size: size);
  }

  final String url;

  /// Lowercase hex string. Compared byte-by-byte against the on-disk
  /// digest after the download finishes.
  final String sha256;

  /// Asset size in bytes per GitHub. Used as the divisor when the server
  /// doesn't send Content-Length on the streamed response.
  final int size;
}

/// Canonical asset keys read from the manifest. Keep in sync with the
/// CI generator in `scripts/build-update-manifest.sh`.
class UpdateAssetKey {
  /// macOS .dmg disk image — interactive install (drag-to-Applications).
  static const String macosDmg = 'macos';

  /// macOS .zip of the .app bundle — preferred for in-place auto-update
  /// because we can `ditto -x -k` straight into /Applications.
  static const String macosZip = 'macos-zip';

  /// Windows Inno Setup installer .exe — supports `/SILENT`.
  static const String windowsInstaller = 'windows-installer';

  /// Windows portable zip — fallback when the installer is missing.
  static const String windowsZip = 'windows-zip';
}

/// Strict semver compare for the very narrow "X.Y.Z" surface our app
/// emits. Build metadata after a `+` is stripped before compare so
/// `0.3.0+1` and `0.3.0+5` are treated as equal — same release, two
/// builds. Pre-release suffixes (`-alpha.1`) are also stripped to match
/// `package_info_plus.version` which never carries them.
///
/// Returns:
///   * negative when `a < b`
///   * zero when `a == b`
///   * positive when `a > b`
int compareVersions(String a, String b) {
  final aPart = _trim(a);
  final bPart = _trim(b);
  for (var i = 0; i < 3; i++) {
    final delta = aPart[i] - bPart[i];
    if (delta != 0) return delta;
  }
  return 0;
}

List<int> _trim(String version) {
  final stripped = version
      .split('+')
      .first
      .split('-')
      .first
      .replaceAll(RegExp('^v'), '')
      .trim();
  final parts = stripped.split('.');
  final out = List<int>.filled(3, 0);
  for (var i = 0; i < 3 && i < parts.length; i++) {
    out[i] = int.tryParse(parts[i]) ?? 0;
  }
  return out;
}
