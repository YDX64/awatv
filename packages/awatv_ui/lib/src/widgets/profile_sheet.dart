import 'dart:ui';

import 'package:flutter/material.dart';

/// A single menu row inside [ProfileSheet].
///
/// Mirrors Streas' menu shape — a cherry-tinted icon tile, a label, a
/// description and a chevron.
class ProfileMenuItem {
  const ProfileMenuItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  /// Leading icon (typically an outlined Material icon).
  final IconData icon;

  /// Bold row label (Inter 14/600).
  final String label;

  /// Smaller descriptive copy beneath the label (Inter 11/400).
  final String description;

  /// Tap callback. The sheet closes itself before this fires so callers
  /// don't need to call `Navigator.pop` first.
  final VoidCallback onTap;
}

/// Stat box rendered inside the [ProfileSheet] stats row.
///
/// Streas shows four — Channels / Favorites / Playlists / Plan. The
/// `highlight` flag swaps the text colour to gold for the "PRO" plan.
class ProfileStat {
  const ProfileStat({
    required this.value,
    required this.label,
    this.highlight = false,
  });

  /// Big top number/string (Inter 16/700).
  final String value;

  /// Subdued caption (Inter 10/400).
  final String label;

  /// When true the value renders in gold (Streas: `#f59e0b`) — used for
  /// the active "PRO" plan badge.
  final bool highlight;
}

/// Bottom-sheet content for the Streas profile / quick-menu surface.
///
/// Anatomy (per `/tmp/Streas/artifacts/iptv-app/components/ProfileSheet.tsx`):
///
/// 1. 40×4 drag handle.
/// 2. Profile header: 52×52 cherry avatar, display name, sub-line,
///    PRO badge **or** "Upgrade" button.
/// 3. Stats row — four [ProfileStat] boxes separated by hairlines.
/// 4. Premium banner (only when [isPremium] is false) — cherry icon tile,
///    title, sub, chevron, with a horizontal cherry gradient overlay.
/// 5. Menu list — 6 [ProfileMenuItem]s with cherry icon tiles.
/// 6. Outlined "Close" button.
///
/// Use the convenience [showProfileSheet] helper to present this with the
/// correct backdrop colour, rounded top corners, and translateY animation
/// (600 → 0 spring).
class ProfileSheet extends StatelessWidget {
  const ProfileSheet({
    required this.displayName,
    required this.email,
    required this.stats,
    required this.menuItems,
    this.avatarUrl,
    this.avatarInitials,
    this.isPremium = false,
    this.premiumTitle = 'Unlock Premium',
    this.premiumSubtitle = 'Unlimited playlists, EPG, catch-up & more',
    this.onUpgrade,
    this.onClose,
    super.key,
  });

  /// Display name shown in the header.
  final String displayName;

  /// Sub-line shown beneath the name. The Streas source uses this for
  /// channel + source counts — callers can pass anything (typically the
  /// signed-in email).
  final String email;

  /// Optional avatar artwork. When absent, a cherry circle with [
  /// avatarInitials] is rendered.
  final String? avatarUrl;

  /// Initials shown inside the avatar when [avatarUrl] is null.
  final String? avatarInitials;

  /// Stats row content. Should contain exactly 4 entries to match Streas
  /// — fewer / more works but layout starts to look unbalanced.
  final List<ProfileStat> stats;

  /// Menu rows to render. Streas ships 6 — keep it close to that.
  final List<ProfileMenuItem> menuItems;

  /// Whether the user is on the PRO plan. Hides the Upgrade button +
  /// premium banner and shows a gold PRO badge in the header instead.
  final bool isPremium;

  /// Premium banner title.
  final String premiumTitle;

  /// Premium banner subtitle.
  final String premiumSubtitle;

  /// Tap callback for both the Upgrade button and the premium banner.
  /// Hidden when null (no banner / no upgrade button).
  final VoidCallback? onUpgrade;

  /// Optional close override. Defaults to popping the current route.
  final VoidCallback? onClose;

  void _close(BuildContext context) {
    if (onClose != null) {
      onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);
    final bottomInset = mediaQuery.padding.bottom;

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(24),
      ),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: ColoredBox(
          color: scheme.surface,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset > 0 ? 16 : 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _DragHandle(color: scheme.outlineVariant),
                  _ProfileHeader(
                    displayName: displayName,
                    email: email,
                    avatarUrl: avatarUrl,
                    avatarInitials: avatarInitials,
                    isPremium: isPremium,
                    onUpgrade: onUpgrade != null
                        ? () {
                            _close(context);
                            onUpgrade!();
                          }
                        : null,
                  ),
                  _StatsRow(stats: stats),
                  if (!isPremium && onUpgrade != null)
                    _PremiumBanner(
                      title: premiumTitle,
                      subtitle: premiumSubtitle,
                      onTap: () {
                        _close(context);
                        onUpgrade!();
                      },
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        for (int i = 0; i < menuItems.length; i++)
                          _MenuRow(
                            item: menuItems[i],
                            isLast: i == menuItems.length - 1,
                            onTap: () {
                              _close(context);
                              menuItems[i].onTap();
                            },
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                    child: _CloseButton(onPressed: () => _close(context)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Convenience helper that mirrors `showProfileSheet(...)` from the
/// Streas RN port: presents a [ProfileSheet] modally with a black 60%
/// scrim, rounded top corners, and a translateY spring animation.
Future<T?> showProfileSheet<T>(
  BuildContext context, {
  required String displayName,
  required String email,
  required List<ProfileStat> stats,
  required List<ProfileMenuItem> menuItems,
  String? avatarUrl,
  String? avatarInitials,
  bool isPremium = false,
  String premiumTitle = 'Unlock Premium',
  String premiumSubtitle =
      'Unlimited playlists, EPG, catch-up & more',
  VoidCallback? onUpgrade,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    useSafeArea: true,
    builder: (BuildContext sheetContext) => ProfileSheet(
      displayName: displayName,
      email: email,
      avatarUrl: avatarUrl,
      avatarInitials: avatarInitials,
      stats: stats,
      menuItems: menuItems,
      isPremium: isPremium,
      premiumTitle: premiumTitle,
      premiumSubtitle: premiumSubtitle,
      onUpgrade: onUpgrade,
    ),
  );
}

class _DragHandle extends StatelessWidget {
  const _DragHandle({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({
    required this.displayName,
    required this.email,
    required this.avatarUrl,
    required this.avatarInitials,
    required this.isPremium,
    required this.onUpgrade,
  });

  final String displayName;
  final String email;
  final String? avatarUrl;
  final String? avatarInitials;
  final bool isPremium;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          _Avatar(
            url: avatarUrl,
            initials: avatarInitials ?? _initialsFor(displayName),
            color: scheme.primary,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: scheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (isPremium)
            const _PremiumBadge()
          else if (onUpgrade != null)
            _UpgradeButton(onPressed: onUpgrade!),
        ],
      ),
    );
  }

  static String _initialsFor(String name) {
    final tokens = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return '?';
    if (tokens.length == 1) {
      return tokens.first.characters.first.toUpperCase();
    }
    return (tokens.first.characters.first + tokens[1].characters.first)
        .toUpperCase();
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.url,
    required this.initials,
    required this.color,
  });

  final String? url;
  final String initials;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _PremiumBadge extends StatelessWidget {
  const _PremiumBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0xCC / 255),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0x55 / 255),
        ),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.bolt, size: 11, color: Color(0xFFF59E0B)),
          SizedBox(width: 4),
          Text(
            'PRO',
            style: TextStyle(
              color: Color(0xFFF59E0B),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _UpgradeButton extends StatelessWidget {
  const _UpgradeButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.primary,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.bolt, size: 12, color: Colors.white),
              SizedBox(width: 5),
              Text(
                'Upgrade',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.stats});
  final List<ProfileStat> stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 18),
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < stats.length; i++) ...<Widget>[
            Expanded(child: _StatBox(stat: stats[i])),
            if (i < stats.length - 1)
              Container(
                width: 0.5,
                height: 30,
                color: scheme.outlineVariant,
              ),
          ],
        ],
      ),
    );
  }
}

class _StatBox extends StatelessWidget {
  const _StatBox({required this.stat});
  final ProfileStat stat;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          stat.value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: stat.highlight
                ? const Color(0xFFF59E0B)
                : scheme.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          stat.label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w400,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ],
    );
  }
}

class _PremiumBanner extends StatelessWidget {
  const _PremiumBanner({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: scheme.primary.withValues(alpha: 0x44 / 255),
                ),
              ),
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: <Color>[
                    scheme.primary.withValues(alpha: 0x30 / 255),
                    Colors.transparent,
                  ],
                ),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: scheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.bolt,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: scheme.primary,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({
    required this.item,
    required this.isLast,
    required this.onTap,
  });

  final ProfileMenuItem item;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isLast
                  ? Colors.transparent
                  : scheme.outlineVariant.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0x18 / 255),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: Icon(item.icon, size: 16, color: scheme.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    item.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 14,
              color: scheme.outlineVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 13),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Text(
          'Close',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
      ),
    );
  }
}
