import 'dart:math';

/// Alphabet used for generated pair codes.
///
/// Hand-picked to dodge classic letter/digit confusables when a user types
/// the code from a phone screen onto a TV remote — `0/O`, `1/I/L`, plus the
/// noisy `S`. Six characters from this 30-symbol set give roughly 729 M
/// permutations which is plenty of entropy for a short-lived pairing code.
const String _pairAlphabet = 'ABCDEFGHJKMNPQRTUVWXYZ23456789';

/// Length of the pair code surfaced to users (`ABCD23` etc.).
const int kPairCodeLength = 6;

/// Generates a fresh upper-case pair code suitable for display next to a QR.
///
/// Codes are NOT collision-checked against active sessions — Supabase
/// Realtime's channel namespace handles that naturally: a duplicated code
/// would simply join two devices into one session, so the receiver-side
/// channel join enforces uniqueness by listening for an unexpected
/// presence event and rolling a new code if needed.
String generatePairCode({Random? random}) {
  final rng = random ?? Random.secure();
  final buf = StringBuffer();
  for (var i = 0; i < kPairCodeLength; i++) {
    buf.write(_pairAlphabet[rng.nextInt(_pairAlphabet.length)]);
  }
  return buf.toString();
}

/// Normalises user-typed input into the canonical form used by the
/// channel name. We upper-case, strip whitespace, and drop any character
/// outside the alphabet so users can paste `abc-123` and still pair.
String normalisePairCode(String raw) {
  final upper = raw.toUpperCase();
  final buf = StringBuffer();
  for (var i = 0; i < upper.length; i++) {
    final ch = upper[i];
    if (_pairAlphabet.contains(ch)) buf.write(ch);
  }
  return buf.toString();
}

/// True when [code] could plausibly be a pair code we generated. Used by
/// the sender screen to enable the "Connect" button only when there's a
/// chance of success.
bool isValidPairCode(String code) {
  if (code.length != kPairCodeLength) return false;
  for (var i = 0; i < code.length; i++) {
    if (!_pairAlphabet.contains(code[i])) return false;
  }
  return true;
}
