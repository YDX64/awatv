import 'dart:developer' as developer;

/// Log severity levels used by [AwatvLogger].
enum AwatvLogLevel { debug, info, warn, error }

/// Minimal zero-dependency logger.
///
/// Output format: `[awatv:LEVEL][tag?] message`
///
/// Hooks into `dart:developer` so it integrates with IDE consoles, but also
/// falls back to plain `print` for environments where the developer log is
/// muted (CI, certain tests).
class AwatvLogger {
  AwatvLogger({this.tag, AwatvLogLevel? minLevel})
      : _minLevel = minLevel ?? AwatvLogLevel.debug;

  final String? tag;
  final AwatvLogLevel _minLevel;

  static AwatvLogLevel _globalMinLevel = AwatvLogLevel.debug;

  /// Set the global floor below which logs are suppressed.
  static void setGlobalMinLevel(AwatvLogLevel level) {
    _globalMinLevel = level;
  }

  void debug(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AwatvLogLevel.debug, message, error: error, stackTrace: stackTrace);
  }

  void info(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AwatvLogLevel.info, message, error: error, stackTrace: stackTrace);
  }

  void warn(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AwatvLogLevel.warn, message, error: error, stackTrace: stackTrace);
  }

  void error(String message, {Object? error, StackTrace? stackTrace}) {
    _log(AwatvLogLevel.error, message, error: error, stackTrace: stackTrace);
  }

  void _log(
    AwatvLogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.index < _minLevel.index) return;
    if (level.index < _globalMinLevel.index) return;

    final levelName = level.name.toUpperCase();
    final prefix = tag != null ? '[awatv:$levelName][$tag]' : '[awatv:$levelName]';
    final line = '$prefix $message';

    developer.log(
      line,
      name: 'awatv',
      level: _developerLevel(level),
      error: error,
      stackTrace: stackTrace,
    );
  }

  int _developerLevel(AwatvLogLevel level) {
    switch (level) {
      case AwatvLogLevel.debug:
        return 500;
      case AwatvLogLevel.info:
        return 800;
      case AwatvLogLevel.warn:
        return 900;
      case AwatvLogLevel.error:
        return 1000;
    }
  }
}
