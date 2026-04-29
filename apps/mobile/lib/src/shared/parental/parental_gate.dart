import 'package:awatv_core/awatv_core.dart';
import 'package:awatv_mobile/src/features/parental/widgets/parental_lock_overlay.dart' show ParentalLockOverlay;
import 'package:awatv_mobile/src/shared/parental/parental_controller.dart';
import 'package:awatv_mobile/src/shared/parental/parental_settings.dart';
import 'package:awatv_mobile/src/shared/profiles/profile.dart';

/// Outcome of [ParentalGate.evaluate].
enum ParentalGateOutcome {
  /// Gate is disabled or the active profile is allowed.
  allowed,

  /// Content rating exceeds the configured maxRating.
  blockedByRating,

  /// The category was added to the blocked list.
  blockedByCategory,

  /// Bedtime hour reached for a kids profile.
  blockedByBedtime,
}

/// Pure decision function — used by the player + detail screens to
/// decide whether to surface the [ParentalLockOverlay] before opening
/// playback.
///
/// All inputs are passed in explicitly so this stays cheap to call from
/// `ConsumerWidget.build` without re-reading provider state.
class ParentalGate {
  const ParentalGate({
    required this.settings,
    required this.profile,
    required this.controller,
  });

  final ParentalSettings settings;
  final UserProfile? profile;
  final ParentalController controller;

  ParentalGateOutcome evaluate({
    int? contentRating,
    String? category,
  }) {
    if (!settings.enabled) return ParentalGateOutcome.allowed;
    final p = profile;
    if (p == null) return ParentalGateOutcome.allowed;
    if (controller.isSessionUnlocked()) return ParentalGateOutcome.allowed;
    // Bedtime applies only to kids profiles.
    if (p.isKids && !controller.isWithinAllowedHours(p)) {
      return ParentalGateOutcome.blockedByBedtime;
    }
    // Category / rating gates also apply only to kids profiles. The
    // master switch + a non-kids profile means parents can keep the
    // PIN configured for the whole device but watch unrestricted.
    if (!p.isKids) return ParentalGateOutcome.allowed;
    if (category != null && category.trim().isNotEmpty) {
      final lower = category.toLowerCase();
      for (final blocked in settings.blockedCategories) {
        if (lower.contains(blocked.toLowerCase())) {
          return ParentalGateOutcome.blockedByCategory;
        }
      }
    }
    if (contentRating != null && contentRating > settings.maxRating) {
      return ParentalGateOutcome.blockedByRating;
    }
    return ParentalGateOutcome.allowed;
  }

  /// Convenience — checks a [VodItem] using the heuristic in
  /// [ParentalRating.inferFromTmdb].
  ParentalGateOutcome evaluateVod(VodItem item) {
    final inferred = ParentalRating.inferFromTmdb(
      voteRating: item.rating,
    );
    final genre = item.genres.isEmpty ? null : item.genres.first;
    return evaluate(contentRating: inferred, category: genre);
  }

  /// Convenience — checks a [Channel] by category groups.
  ParentalGateOutcome evaluateChannel(Channel channel) {
    final group = channel.groups.isEmpty ? null : channel.groups.first;
    return evaluate(category: group);
  }
}
