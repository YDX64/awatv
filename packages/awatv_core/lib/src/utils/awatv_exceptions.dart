/// Base type for all errors raised inside `awatv_core`.
///
/// Use the concrete subclasses; never throw `AwatvException` directly.
abstract class AwatvException implements Exception {
  const AwatvException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when an M3U body is so malformed we cannot recover any channels.
class PlaylistParseException extends AwatvException {
  const PlaylistParseException(super.message, {this.line});

  final int? line;

  @override
  String toString() {
    if (line != null) return 'PlaylistParseException(line $line): $message';
    return 'PlaylistParseException: $message';
  }
}

/// Xtream Codes credentials rejected by upstream.
class XtreamAuthException extends AwatvException {
  const XtreamAuthException(super.message);
}

/// Stalker / Ministra portal rejected our MAC address (or the handshake
/// failed in a way the server couldn't recover from). Carries the same
/// shape as [XtreamAuthException] so callers can lump them together as
/// "credentials rejected" for UI copy purposes.
class StalkerAuthException extends AwatvException {
  const StalkerAuthException(super.message);
}

/// Generic network problem (DNS, timeout, non-2xx, ...).
class NetworkException extends AwatvException {
  const NetworkException(
    super.message, {
    this.statusCode,
    this.retryable = false,
  });

  final int? statusCode;
  final bool retryable;

  @override
  String toString() {
    final code = statusCode != null ? ' [$statusCode]' : '';
    return 'NetworkException$code: $message';
  }
}

/// TMDB (or future TVDB/IMDB) returned no match for a query.
class MetadataNotFoundException extends AwatvException {
  const MetadataNotFoundException(this.query)
      : super('No metadata match for query');

  final String query;

  @override
  String toString() => 'MetadataNotFoundException: $message ($query)';
}

/// Hive/box-level failure (corrupted box, init error, etc.).
class StorageException extends AwatvException {
  const StorageException(super.message);
}
