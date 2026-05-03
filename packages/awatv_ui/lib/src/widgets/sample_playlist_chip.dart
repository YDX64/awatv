import 'package:awatv_ui/src/theme/brand_colors.dart';
import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:flutter/material.dart';

/// Hard-coded preset for the M3U "free sample playlists" rail in the
/// Add Source flow.
///
/// Five presets are exposed as the canonical [samplePlaylists] list,
/// matching the IPTV-Org / Free-TV catalogue Streas ships in the RN
/// reference. Each chip pre-fills the URL field on tap so a user can
/// kick the tyres without hunting for a public list.
@immutable
class SamplePlaylistPreset {
  const SamplePlaylistPreset({
    required this.id,
    required this.name,
    required this.provider,
    required this.url,
    required this.channelLabel,
    required this.flag,
    required this.tint,
  });

  /// Stable id used for keyed equality and chip selection state.
  final String id;

  /// Display name shown on the chip ("IPTV-Org News").
  final String name;

  /// Provider sub-line ("IPTV-Org · 800+ kanal").
  final String provider;

  /// Raw playlist URL pre-filled into the URL field.
  final String url;

  /// Approximate channel count + region label for the chip metadata
  /// row. Pre-formatted because Streas displays it as a rough estimate
  /// rather than an exact count.
  final String channelLabel;

  /// Single-character emoji flag glyph painted into the leading circle.
  final String flag;

  /// Brand tint used for the chip leading circle. Each preset uses a
  /// distinct hue so the rail visually fans out instead of melting into
  /// a single colour.
  final Color tint;
}

/// Five hard-coded presets matching `app/add-source.tsx` § "FREE SAMPLE
/// PLAYLISTS" in the Streas RN reference.
///
/// IPTV-Org URLs are public and stable; Free-TV mirror has been around
/// since 2017 and is the most-recommended fallback for testing playlist
/// support without needing a paid subscription.
const List<SamplePlaylistPreset> samplePlaylists = <SamplePlaylistPreset>[
  SamplePlaylistPreset(
    id: 'iptv_org_news',
    name: 'IPTV-Org News',
    provider: 'IPTV-Org',
    url: 'https://iptv-org.github.io/iptv/categories/news.m3u',
    channelLabel: '800+ haber',
    flag: '\u{1F4E1}',
    tint: Color(0xFFE11D48),
  ),
  SamplePlaylistPreset(
    id: 'iptv_org_entertainment',
    name: 'IPTV-Org Eglence',
    provider: 'IPTV-Org',
    url: 'https://iptv-org.github.io/iptv/categories/entertainment.m3u',
    channelLabel: '600+ kanal',
    flag: '\u{1F3AC}',
    tint: Color(0xFF8B5CF6),
  ),
  SamplePlaylistPreset(
    id: 'iptv_org_sports',
    name: 'IPTV-Org Spor',
    provider: 'IPTV-Org',
    url: 'https://iptv-org.github.io/iptv/categories/sports.m3u',
    channelLabel: '200+ spor',
    flag: '\u{26BD}',
    tint: Color(0xFFF59E0B),
  ),
  SamplePlaylistPreset(
    id: 'free_tv',
    name: 'Free-TV',
    provider: 'Free-TV mirror',
    url: 'https://raw.githubusercontent.com/Free-TV/IPTV/master/playlist.m3u8',
    channelLabel: '1200+ kanal',
    flag: '\u{1F4FA}',
    tint: Color(0xFF22C55E),
  ),
  SamplePlaylistPreset(
    id: 'iptv_org_full',
    name: 'IPTV-Org Tum Liste',
    provider: 'IPTV-Org',
    url: 'https://iptv-org.github.io/iptv/index.m3u',
    channelLabel: '9000+ kanal',
    flag: '\u{1F30D}',
    tint: Color(0xFF06B6D4),
  ),
];

/// Filter-chip-style row presenting a single [SamplePlaylistPreset].
///
/// Tapping fires [onTap] with the chosen preset so the parent form can
/// pre-fill its URL field. When [selected] is `true` the chip surfaces
/// a cherry tint + check icon to confirm the selection.
class SamplePlaylistChip extends StatelessWidget {
  const SamplePlaylistChip({
    required this.preset,
    required this.onTap,
    this.selected = false,
    super.key,
  });

  final SamplePlaylistPreset preset;
  final ValueChanged<SamplePlaylistPreset> onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final borderColor = selected
        ? BrandColors.primary
        : cs.outlineVariant.withValues(alpha: 0.6);
    final fill = selected
        ? BrandColors.primary.withValues(alpha: 0.10)
        : cs.surfaceContainerHighest.withValues(alpha: 0.55);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(preset),
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        child: AnimatedContainer(
          duration: DesignTokens.motionFast,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceM,
            vertical: DesignTokens.spaceS,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(DesignTokens.radiusM),
            border: Border.all(
              color: borderColor,
              width: selected ? 1.4 : 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: preset.tint.withValues(alpha: 0.18),
                  border: Border.all(
                    color: preset.tint.withValues(alpha: 0.55),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  preset.flag,
                  style: const TextStyle(fontSize: 18),
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    preset.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${preset.provider} · ${preset.channelLabel}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (selected) ...<Widget>[
                const SizedBox(width: DesignTokens.spaceS),
                const Icon(
                  Icons.check_circle_rounded,
                  size: 18,
                  color: BrandColors.primary,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
