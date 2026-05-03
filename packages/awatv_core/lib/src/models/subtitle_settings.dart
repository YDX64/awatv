import 'package:meta/meta.dart';

/// Discrete subtitle text size buckets — matches the Streas RN spec
/// (`small | medium | large | xlarge` → 13/16/20/26 px).
enum SubtitleSize {
  small,
  medium,
  large,
  xlarge,
}

extension SubtitleSizeX on SubtitleSize {
  /// Pixel size used by the overlay renderer.
  double get px {
    switch (this) {
      case SubtitleSize.small:
        return 13;
      case SubtitleSize.medium:
        return 16;
      case SubtitleSize.large:
        return 20;
      case SubtitleSize.xlarge:
        return 26;
    }
  }

  /// Stable wire id (matches Streas RN AsyncStorage key).
  String get wire {
    switch (this) {
      case SubtitleSize.small:
        return 'small';
      case SubtitleSize.medium:
        return 'medium';
      case SubtitleSize.large:
        return 'large';
      case SubtitleSize.xlarge:
        return 'xlarge';
    }
  }

  static SubtitleSize fromWire(String? raw) {
    switch (raw) {
      case 'small':
        return SubtitleSize.small;
      case 'large':
        return SubtitleSize.large;
      case 'xlarge':
        return SubtitleSize.xlarge;
      case 'medium':
      default:
        return SubtitleSize.medium;
    }
  }
}

/// Subtitle text colour preset. Hex values mirror Streas RN
/// (`white | yellow | green | cyan` → #fff/#fde047/#4ade80/#22d3ee).
enum SubtitleColor {
  white,
  yellow,
  green,
  cyan,
}

extension SubtitleColorX on SubtitleColor {
  /// 0xAARRGGBB representation usable directly via Flutter `Color`.
  int get argb {
    switch (this) {
      case SubtitleColor.white:
        return 0xFFFFFFFF;
      case SubtitleColor.yellow:
        return 0xFFFDE047;
      case SubtitleColor.green:
        return 0xFF4ADE80;
      case SubtitleColor.cyan:
        return 0xFF22D3EE;
    }
  }

  String get wire {
    switch (this) {
      case SubtitleColor.white:
        return 'white';
      case SubtitleColor.yellow:
        return 'yellow';
      case SubtitleColor.green:
        return 'green';
      case SubtitleColor.cyan:
        return 'cyan';
    }
  }

  static SubtitleColor fromWire(String? raw) {
    switch (raw) {
      case 'yellow':
        return SubtitleColor.yellow;
      case 'green':
        return SubtitleColor.green;
      case 'cyan':
        return SubtitleColor.cyan;
      case 'white':
      default:
        return SubtitleColor.white;
    }
  }
}

/// Background-strip behind subtitle lines. Streas RN values:
/// none → transparent, semi → rgba(0,0,0,0.6), solid → rgba(0,0,0,0.92).
enum SubtitleBackground {
  none,
  semi,
  solid,
}

extension SubtitleBackgroundX on SubtitleBackground {
  /// 0xAARRGGBB representation usable directly via Flutter `Color`.
  int get argb {
    switch (this) {
      case SubtitleBackground.none:
        return 0x00000000;
      case SubtitleBackground.semi:
        return 0x99000000; // ~60% alpha
      case SubtitleBackground.solid:
        return 0xEB000000; // ~92% alpha
    }
  }

  String get wire {
    switch (this) {
      case SubtitleBackground.none:
        return 'none';
      case SubtitleBackground.semi:
        return 'semi';
      case SubtitleBackground.solid:
        return 'solid';
    }
  }

  static SubtitleBackground fromWire(String? raw) {
    switch (raw) {
      case 'none':
        return SubtitleBackground.none;
      case 'solid':
        return SubtitleBackground.solid;
      case 'semi':
      default:
        return SubtitleBackground.semi;
    }
  }
}

/// Where the subtitle strip floats relative to the video frame.
enum SubtitlePosition {
  top,
  bottom,
}

extension SubtitlePositionX on SubtitlePosition {
  String get wire => this == SubtitlePosition.top ? 'top' : 'bottom';

  static SubtitlePosition fromWire(String? raw) =>
      raw == 'top' ? SubtitlePosition.top : SubtitlePosition.bottom;
}

/// User-configurable subtitle rendering settings persisted across
/// launches. JSON-shape matches Streas RN's AsyncStorage key
/// `awatv_subtitle_settings` so a future cross-platform sync migration
/// is a no-op.
@immutable
class SubtitleSettings {
  const SubtitleSettings({
    this.enabled = true,
    this.preferredLanguage = 'en',
    this.size = SubtitleSize.medium,
    this.color = SubtitleColor.white,
    this.background = SubtitleBackground.semi,
    this.position = SubtitlePosition.bottom,
    this.bold = false,
    this.apiKey,
    this.loadedFileName,
    this.loadedLabel,
  });

  factory SubtitleSettings.fromJson(Map<String, dynamic> json) {
    return SubtitleSettings(
      enabled: json['enabled'] as bool? ?? true,
      preferredLanguage: (json['preferredLanguage'] as String?) ?? 'en',
      size: SubtitleSizeX.fromWire(json['size'] as String?),
      color: SubtitleColorX.fromWire(json['color'] as String?),
      background: SubtitleBackgroundX.fromWire(json['background'] as String?),
      position: SubtitlePositionX.fromWire(json['position'] as String?),
      bold: json['bold'] as bool? ?? false,
      apiKey: json['apiKey'] as String?,
      loadedFileName: json['loadedFileName'] as String?,
      loadedLabel: json['loadedLabel'] as String?,
    );
  }

  /// Master toggle. When false, the overlay is hidden regardless of
  /// loaded cues.
  final bool enabled;

  /// ISO-639-1 code (e.g. `tr`, `en`).
  final String preferredLanguage;

  final SubtitleSize size;
  final SubtitleColor color;
  final SubtitleBackground background;
  final SubtitlePosition position;

  /// When true, lines render with FontWeight.w700 instead of w600.
  final bool bold;

  /// Optional user-provided OpenSubtitles API key — when present, the
  /// search/download flow uses it to lift the free quota cap.
  final String? apiKey;

  /// Currently-loaded SRT file name (e.g. `Movie.2024.tr.srt`). Surfaced
  /// in the picker as "Yuklenen altyazi: filename" so the user knows
  /// which SRT is active. Null when no SRT is loaded.
  final String? loadedFileName;

  /// Human label shown beside the active subtitle (e.g. `Movie [TR]`).
  final String? loadedLabel;

  SubtitleSettings copyWith({
    bool? enabled,
    String? preferredLanguage,
    SubtitleSize? size,
    SubtitleColor? color,
    SubtitleBackground? background,
    SubtitlePosition? position,
    bool? bold,
    String? apiKey,
    String? loadedFileName,
    String? loadedLabel,
    bool clearLoadedFileName = false,
    bool clearLoadedLabel = false,
  }) {
    return SubtitleSettings(
      enabled: enabled ?? this.enabled,
      preferredLanguage: preferredLanguage ?? this.preferredLanguage,
      size: size ?? this.size,
      color: color ?? this.color,
      background: background ?? this.background,
      position: position ?? this.position,
      bold: bold ?? this.bold,
      apiKey: apiKey ?? this.apiKey,
      loadedFileName: clearLoadedFileName
          ? null
          : (loadedFileName ?? this.loadedFileName),
      loadedLabel:
          clearLoadedLabel ? null : (loadedLabel ?? this.loadedLabel),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'enabled': enabled,
        'preferredLanguage': preferredLanguage,
        'size': size.wire,
        'color': color.wire,
        'background': background.wire,
        'position': position.wire,
        'bold': bold,
        if (apiKey != null) 'apiKey': apiKey,
        if (loadedFileName != null) 'loadedFileName': loadedFileName,
        if (loadedLabel != null) 'loadedLabel': loadedLabel,
      };

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SubtitleSettings &&
        other.enabled == enabled &&
        other.preferredLanguage == preferredLanguage &&
        other.size == size &&
        other.color == color &&
        other.background == background &&
        other.position == position &&
        other.bold == bold &&
        other.apiKey == apiKey &&
        other.loadedFileName == loadedFileName &&
        other.loadedLabel == loadedLabel;
  }

  @override
  int get hashCode => Object.hash(
        enabled,
        preferredLanguage,
        size,
        color,
        background,
        position,
        bold,
        apiKey,
        loadedFileName,
        loadedLabel,
      );
}

/// One of the 27 languages supported by the OpenSubtitles search flow.
@immutable
class SubtitleLanguage {
  const SubtitleLanguage({
    required this.code,
    required this.name,
    required this.nativeName,
  });

  /// ISO-639-1 code (e.g. `en`, `tr`, `zh-CN`). Sent verbatim to
  /// OpenSubtitles' `languages` query parameter.
  final String code;

  /// English display name (e.g. "Turkish").
  final String name;

  /// Display name in the language itself (e.g. "Türkçe").
  final String nativeName;
}

/// 27-language list ported 1:1 from Streas RN's `SUBTITLE_LANGUAGES`
/// constant (`utils/subtitles.ts`). Order matches the source so the
/// language picker dropdown reads identically across platforms.
const List<SubtitleLanguage> kSubtitleLanguages = <SubtitleLanguage>[
  SubtitleLanguage(code: 'en', name: 'English', nativeName: 'English'),
  SubtitleLanguage(code: 'tr', name: 'Turkish', nativeName: 'Türkçe'),
  SubtitleLanguage(code: 'ar', name: 'Arabic', nativeName: 'العربية'),
  SubtitleLanguage(code: 'de', name: 'German', nativeName: 'Deutsch'),
  SubtitleLanguage(code: 'es', name: 'Spanish', nativeName: 'Español'),
  SubtitleLanguage(code: 'fr', name: 'French', nativeName: 'Français'),
  SubtitleLanguage(code: 'it', name: 'Italian', nativeName: 'Italiano'),
  SubtitleLanguage(code: 'pt', name: 'Portuguese', nativeName: 'Português'),
  SubtitleLanguage(code: 'ru', name: 'Russian', nativeName: 'Русский'),
  SubtitleLanguage(code: 'nl', name: 'Dutch', nativeName: 'Nederlands'),
  SubtitleLanguage(code: 'pl', name: 'Polish', nativeName: 'Polski'),
  SubtitleLanguage(code: 'ja', name: 'Japanese', nativeName: '日本語'),
  SubtitleLanguage(code: 'ko', name: 'Korean', nativeName: '한국어'),
  SubtitleLanguage(
      code: 'zh-CN', name: 'Chinese (Simplified)', nativeName: '简体中文'),
  SubtitleLanguage(
      code: 'zh-TW', name: 'Chinese (Traditional)', nativeName: '繁體中文'),
  SubtitleLanguage(code: 'hi', name: 'Hindi', nativeName: 'हिन्दी'),
  SubtitleLanguage(code: 'fa', name: 'Persian', nativeName: 'فارسی'),
  SubtitleLanguage(code: 'sv', name: 'Swedish', nativeName: 'Svenska'),
  SubtitleLanguage(code: 'da', name: 'Danish', nativeName: 'Dansk'),
  SubtitleLanguage(code: 'no', name: 'Norwegian', nativeName: 'Norsk'),
  SubtitleLanguage(code: 'fi', name: 'Finnish', nativeName: 'Suomi'),
  SubtitleLanguage(code: 'ro', name: 'Romanian', nativeName: 'Română'),
  SubtitleLanguage(code: 'uk', name: 'Ukrainian', nativeName: 'Українська'),
  SubtitleLanguage(code: 'el', name: 'Greek', nativeName: 'Ελληνικά'),
  SubtitleLanguage(code: 'he', name: 'Hebrew', nativeName: 'עברית'),
  SubtitleLanguage(code: 'cs', name: 'Czech', nativeName: 'Čeština'),
  SubtitleLanguage(code: 'hu', name: 'Hungarian', nativeName: 'Magyar'),
];
