import 'package:awatv_mobile/src/features/watch_party/watch_party_state.dart';
import 'package:awatv_mobile/src/shared/remote/watch_party_protocol.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Strip of avatars + names for everyone currently in the party.
class WatchPartyMemberBar extends StatelessWidget {
  const WatchPartyMemberBar({required this.state, super.key});

  final WatchPartyState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      height: 72,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
        vertical: DesignTokens.spaceS,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: scheme.outline.withValues(alpha: 0.18),
          ),
        ),
      ),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: <Widget>[
          for (final m in state.members)
            Padding(
              padding: const EdgeInsets.only(right: DesignTokens.spaceM),
              child: _MemberChip(
                member: m,
                isLocal: m.userId == state.localUserId,
                showDrift: m.userId == state.localUserId &&
                    state.lastDriftMs.abs() > 500,
                driftMs: state.lastDriftMs,
              ),
            ),
        ],
      ),
    );
  }
}

class _MemberChip extends StatelessWidget {
  const _MemberChip({
    required this.member,
    required this.isLocal,
    required this.showDrift,
    required this.driftMs,
  });

  final PartyMember member;
  final bool isLocal;
  final bool showDrift;
  final int driftMs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = member.userName.trim().isEmpty
        ? '?'
        : member.userName.trim()[0].toUpperCase();
    final color = member.online ? scheme.primary : scheme.outline;
    final driftLabel =
        '${driftMs >= 0 ? '+' : ''}${(driftMs / 1000).toStringAsFixed(1)}s';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Stack(
          children: <Widget>[
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.2),
              foregroundColor: color,
              child: Text(
                initial,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: member.online
                      ? Colors.greenAccent
                      : scheme.outline,
                  border:
                      Border.all(color: scheme.surfaceContainerHighest, width: 2),
                ),
              ),
            ),
            if (member.isHost)
              Positioned(
                left: -2,
                top: -2,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: scheme.tertiary,
                    border: Border.all(
                      color: scheme.surfaceContainerHighest,
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.star_rounded,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(width: DesignTokens.spaceS),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              isLocal ? '${member.userName} (sen)' : member.userName,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              member.isHost
                  ? 'Host'
                  : (member.online ? 'Cevrimici' : 'Cevrimdisi'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            if (showDrift)
              Text(
                'Drift: $driftLabel',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
