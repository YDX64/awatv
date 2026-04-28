/// Typed failure produced by the cloud sync engine.
///
/// Two flavours:
///   * `retryable` — transient (network, 5xx, rate-limit). The queue
///     re-attempts these with exponential backoff.
///   * non-retryable — permanent (4xx auth, schema mismatch). The
///     engine surfaces these to the UI and drops the offending event.
class SyncError implements Exception {
  const SyncError(
    this.message, {
    this.retryable = true,
    this.cause,
    this.statusCode,
  });

  final String message;
  final bool retryable;
  final Object? cause;
  final int? statusCode;

  @override
  String toString() {
    final code = statusCode == null ? '' : ' [$statusCode]';
    return 'SyncError$code: $message';
  }
}
