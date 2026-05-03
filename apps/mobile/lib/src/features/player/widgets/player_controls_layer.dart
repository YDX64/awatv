import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';

/// Netflix-tier control overlay.
///
/// Composed of a top bar (back / title / cast / settings), a centre
/// transport cluster (skip-back, play/pause, skip-forward) shown only
/// when paused, a bottom seek bar with audio/subtitle chips for VOD, and
/// a live strip for live streams. Each region animates in independently
/// so the surface feels responsive without ever flashing chrome.
///
/// The widget is purely presentational — all state, gestures, and stream
/// subscriptions live in the parent screen, which feeds in props each
/// build. Keeps the screen testable and the controls trivial to skin.
class PlayerControlsLayer extends StatelessWidget {
  const PlayerControlsLayer({
    required this.title,
    required this.isLive,
    required this.isPaused,
    required this.position,
    required this.total,
    required this.buffered,
    required this.onTogglePlay,
    required this.onSeekTo,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.onClose,
    required this.onCastRequested,
    required this.onSettingsRequested,
    required this.onScrubStartChanged,
    this.subtitle,
    this.epgNow,
    this.epgNext,
    this.statusBadge,
    this.castVisible = false,
    this.castActive = false,
    this.castDeviceName,
    this.alwaysOnTopVisible = false,
    this.alwaysOnTopActive = false,
    this.onAlwaysOnTopRequested,
    this.onSubtitlePickerRequested,
    this.onExternalPlayerRequested,
    this.onChannelListRequested,
    this.onEpgRequested,
    this.subtitlesActive = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final bool isLive;
  final bool isPaused;
  final Duration position;
  final Duration? total;
  final Duration buffered;

  final VoidCallback onTogglePlay;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final VoidCallback onClose;
  final VoidCallback onCastRequested;
  final VoidCallback onSettingsRequested;

  /// Fired when the user starts/stops dragging the scrubber. Used by the
  /// host screen to suspend the auto-hide timer during a drag.
  final ValueChanged<bool> onScrubStartChanged;

  final String? epgNow;
  final String? epgNext;
  final Widget? statusBadge;

  /// Whether the cast button should be rendered at all. False on web /
  /// desktop where casting is unsupported.
  final bool castVisible;

  /// Whether a cast session is currently active — flips the icon to
  /// brand-tinted and shows a "Casting" badge underneath the title.
  final bool castActive;

  /// Optional name of the receiver (e.g. "Living Room TV") used by the
  /// "Casting to ..." sub-label when [castActive] is true.
  final String? castDeviceName;

  /// Whether the always-on-top toggle should render in the top bar.
  /// True only on desktop runtimes (macOS, Windows, Linux); the feature
  /// has no meaning on mobile / TV / web.
  final bool alwaysOnTopVisible;

  /// Whether always-on-top is currently engaged. Drives the icon
  /// variant (filled push-pin vs outlined) and the brand tint.
  final bool alwaysOnTopActive;

  /// Tapped from the top bar. Premium-gating, persistence, and the
  /// native call all live in the host screen — this widget only fires
  /// the intent.
  final VoidCallback? onAlwaysOnTopRequested;

  /// Tapped from the bottom bar's CC chip — pushes `/subtitle-picker`.
  /// When null, the chip is hidden; the unified track picker remains
  /// available via [onSettingsRequested].
  final VoidCallback? onSubtitlePickerRequested;

  /// Tapped from the top bar's "Open with" icon — opens the external
  /// player picker (VLC / MX / nPlayer deep-link). When null, the icon
  /// is hidden so non-mobile builds don't show it.
  final VoidCallback? onExternalPlayerRequested;

  /// Tapped from the live bottom bar's list icon — slides in the
  /// channel-side drawer. When null, the icon is hidden.
  final VoidCallback? onChannelListRequested;

  /// Tapped from the live bottom bar's calendar icon — opens the EPG
  /// bottom sheet (now + next programme). When null, the icon is hidden.
  final VoidCallback? onEpgRequested;

  /// True when an SRT is currently loaded — the CC chip turns
  /// cherry-tinted to mirror the Streas RN active state.
  final bool subtitlesActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Stack(
      children: <Widget>[
        // Top + bottom gradient scrims for legibility.
        const Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Color(0xCC000000),
                    Color(0x33000000),
                    Color(0x33000000),
                    Color(0xCC000000),
                  ],
                  stops: <double>[0, 0.25, 0.7, 1],
                ),
              ),
            ),
          ),
        ),
        SafeArea(
          child: Column(
            children: <Widget>[
              _TopBar(
                title: title,
                subtitle: subtitle,
                onClose: onClose,
                onCast: onCastRequested,
                onSettings: onSettingsRequested,
                statusBadge: statusBadge,
                castVisible: castVisible,
                castActive: castActive,
                castDeviceName: castDeviceName,
                alwaysOnTopVisible: alwaysOnTopVisible,
                alwaysOnTopActive: alwaysOnTopActive,
                onAlwaysOnTop: onAlwaysOnTopRequested,
                onExternalPlayer: onExternalPlayerRequested,
                onSubtitlePicker: onSubtitlePickerRequested,
                subtitlesActive: subtitlesActive,
              ),
              Expanded(
                child: Center(
                  child: _CentreCluster(
                    isPaused: isPaused,
                    isLive: isLive,
                    onTogglePlay: onTogglePlay,
                    onSkipBack: onSkipBack,
                    onSkipForward: onSkipForward,
                    primary: scheme.primary,
                  ),
                ),
              ),
              if (isLive)
                _LiveStrip(
                  now: epgNow,
                  next: epgNext,
                  onChannelList: onChannelListRequested,
                  onEpg: onEpgRequested,
                  onSubtitlePicker: onSubtitlePickerRequested,
                  subtitlesActive: subtitlesActive,
                )
              else
                _BottomBar(
                  position: position,
                  total: total,
                  buffered: buffered,
                  onSeekTo: onSeekTo,
                  onSettings: onSettingsRequested,
                  onScrubStartChanged: onScrubStartChanged,
                  onSubtitlePicker: onSubtitlePickerRequested,
                  subtitlesActive: subtitlesActive,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.title,
    required this.subtitle,
    required this.onClose,
    required this.onCast,
    required this.onSettings,
    required this.statusBadge,
    required this.castVisible,
    required this.castActive,
    required this.castDeviceName,
    required this.alwaysOnTopVisible,
    required this.alwaysOnTopActive,
    required this.onAlwaysOnTop,
    required this.onExternalPlayer,
    required this.onSubtitlePicker,
    required this.subtitlesActive,
  });

  final String title;
  final String? subtitle;
  final VoidCallback onClose;
  final VoidCallback onCast;
  final VoidCallback onSettings;
  final Widget? statusBadge;
  final bool castVisible;
  final bool castActive;
  final String? castDeviceName;
  final bool alwaysOnTopVisible;
  final bool alwaysOnTopActive;
  final VoidCallback? onAlwaysOnTop;
  final VoidCallback? onExternalPlayer;
  final VoidCallback? onSubtitlePicker;
  final bool subtitlesActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceS,
        vertical: DesignTokens.spaceXs,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            icon: const Icon(
              Icons.chevron_left_rounded,
              color: Colors.white,
              size: 28,
            ),
            tooltip: 'Geri',
            onPressed: onClose,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (castActive)
                  _CastingBadge(
                    deviceName: castDeviceName,
                    tint: scheme.primary,
                  )
                else if (subtitle != null && subtitle!.isNotEmpty)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                  ),
              ],
            ),
          ),
          if (statusBadge != null) ...<Widget>[
            statusBadge!,
            const SizedBox(width: DesignTokens.spaceXs),
          ],
          if (onExternalPlayer != null)
            IconButton(
              tooltip: 'Harici oynatici (VLC / MX / nPlayer)',
              onPressed: onExternalPlayer,
              icon: const Icon(
                Icons.open_in_new_rounded,
                color: Colors.white,
              ),
            ),
          if (onSubtitlePicker != null)
            // Cherry-tinted pill when subtitles are active — matches
            // the Streas RN rgba(225,29,72,0.2) chip background.
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              decoration: subtitlesActive
                  ? BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    )
                  : null,
              child: IconButton(
                tooltip: subtitlesActive
                    ? 'Altyazi acik'
                    : 'Altyazi sec',
                onPressed: onSubtitlePicker,
                icon: Icon(
                  Icons.subtitles_rounded,
                  color: subtitlesActive ? scheme.primary : Colors.white,
                ),
              ),
            ),
          if (alwaysOnTopVisible && onAlwaysOnTop != null)
            IconButton(
              tooltip: alwaysOnTopActive
                  ? 'Sabitlemeyi kaldır'
                  : 'Pencereyi üstte sabitle',
              onPressed: onAlwaysOnTop,
              icon: Icon(
                alwaysOnTopActive
                    ? Icons.push_pin
                    : Icons.push_pin_outlined,
                color: alwaysOnTopActive ? scheme.primary : Colors.white,
              ),
            ),
          if (castVisible)
            IconButton(
              tooltip:
                  castActive ? 'Yayın aktif — kontroller' : 'Yayın gönder',
              onPressed: onCast,
              icon: Icon(
                castActive
                    ? Icons.cast_connected_rounded
                    : Icons.cast_rounded,
                color: castActive ? scheme.primary : Colors.white,
              ),
            ),
          IconButton(
            tooltip: 'Ayarlar',
            onPressed: onSettings,
            icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _CastingBadge extends StatelessWidget {
  const _CastingBadge({required this.deviceName, required this.tint});
  final String? deviceName;
  final Color tint;

  @override
  Widget build(BuildContext context) {
    final label = deviceName == null
        ? "TV'ye yayınlanıyor"
        : '$deviceName cihazına yayınlanıyor';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: tint,
              shape: BoxShape.circle,
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: tint.withValues(alpha: 0.7),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tint,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CentreCluster extends StatelessWidget {
  const _CentreCluster({
    required this.isPaused,
    required this.isLive,
    required this.onTogglePlay,
    required this.onSkipBack,
    required this.onSkipForward,
    required this.primary,
  });

  final bool isPaused;
  final bool isLive;
  final VoidCallback onTogglePlay;
  final VoidCallback onSkipBack;
  final VoidCallback onSkipForward;
  final Color primary;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (!isLive)
          _RoundButton(
            icon: Icons.replay_10_rounded,
            size: 56,
            onTap: onSkipBack,
          ),
        if (!isLive) const SizedBox(width: DesignTokens.spaceXl),
        _PrimaryButton(
          isPaused: isPaused,
          onTap: onTogglePlay,
          tint: primary,
        ),
        if (!isLive) const SizedBox(width: DesignTokens.spaceXl),
        if (!isLive)
          _RoundButton(
            icon: Icons.forward_10_rounded,
            size: 56,
            onTap: onSkipForward,
          ),
      ],
    );
  }
}

class _RoundButton extends StatefulWidget {
  const _RoundButton({
    required this.icon,
    required this.size,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final VoidCallback onTap;

  @override
  State<_RoundButton> createState() => _RoundButtonState();
}

class _RoundButtonState extends State<_RoundButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: DesignTokens.motionFast,
        curve: DesignTokens.motionStandard,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          child: Icon(
            widget.icon,
            color: Colors.white,
            size: widget.size * 0.55,
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  const _PrimaryButton({
    required this.isPaused,
    required this.onTap,
    required this.tint,
  });

  final bool isPaused;
  final VoidCallback onTap;
  final Color tint;

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _down = true),
      onTapUp: (_) => setState(() => _down = false),
      onTapCancel: () => setState(() => _down = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.92 : 1,
        duration: DesignTokens.motionFast,
        curve: DesignTokens.motionStandard,
        child: Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Colors.white.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0.08),
              ],
            ),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.22),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: widget.tint.withValues(alpha: 0.32),
                blurRadius: 24,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: DesignTokens.motionFast,
            switchInCurve: DesignTokens.motionStandard,
            transitionBuilder: (Widget child, Animation<double> a) =>
                ScaleTransition(
              scale: a,
              child: FadeTransition(opacity: a, child: child),
            ),
            child: Icon(
              widget.isPaused
                  ? Icons.play_arrow_rounded
                  : Icons.pause_rounded,
              key: ValueKey<bool>(widget.isPaused),
              size: 44,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatefulWidget {
  const _BottomBar({
    required this.position,
    required this.total,
    required this.buffered,
    required this.onSeekTo,
    required this.onSettings,
    required this.onScrubStartChanged,
    required this.onSubtitlePicker,
    required this.subtitlesActive,
  });

  final Duration position;
  final Duration? total;
  final Duration buffered;
  final ValueChanged<Duration> onSeekTo;
  final VoidCallback onSettings;
  final ValueChanged<bool> onScrubStartChanged;
  final VoidCallback? onSubtitlePicker;
  final bool subtitlesActive;

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.total;
    final hasTotal = total != null && total.inMilliseconds > 0;
    final progress = hasTotal
        ? (widget.position.inMilliseconds / total.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final buffered = hasTotal
        ? (widget.buffered.inMilliseconds / total.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    final shown = _dragValue ?? progress;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        DesignTokens.spaceS,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          // Custom track with buffered overlay.
          SizedBox(
            height: 36,
            child: Stack(
              alignment: Alignment.center,
              children: <Widget>[
                // Track + buffered ribbon.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: <Widget>[
                      Container(
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: buffered,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: scheme.primary,
                    inactiveTrackColor: Colors.transparent,
                    trackHeight: 4,
                    thumbColor: Colors.white,
                    overlayColor:
                        scheme.primary.withValues(alpha: 0.18),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 18,
                    ),
                  ),
                  child: Slider(
                    value: shown,
                    onChangeStart: (double v) {
                      widget.onScrubStartChanged(true);
                      setState(() => _dragValue = v);
                    },
                    onChanged: hasTotal
                        ? (double v) => setState(() => _dragValue = v)
                        : null,
                    onChangeEnd: hasTotal
                        ? (double v) {
                            widget.onScrubStartChanged(false);
                            final ms =
                                (total.inMilliseconds * v).round();
                            widget.onSeekTo(Duration(milliseconds: ms));
                            setState(() => _dragValue = null);
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: <Widget>[
              Text(
                _format(_displayPosition(progress, shown, total)),
                style: const TextStyle(
                  color: Colors.white,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              if (widget.onSubtitlePicker != null)
                IconButton(
                  tooltip: 'Altyazi sec',
                  onPressed: widget.onSubtitlePicker,
                  icon: Icon(
                    Icons.closed_caption_rounded,
                    color: widget.subtitlesActive
                        ? scheme.primary
                        : Colors.white,
                  ),
                ),
              IconButton(
                tooltip: 'Altyazı / ses / kalite',
                onPressed: widget.onSettings,
                icon: const Icon(
                  Icons.tune_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: DesignTokens.spaceS),
              Text(
                hasTotal ? _format(total) : '--:--',
                style: const TextStyle(
                  color: Colors.white70,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Duration _displayPosition(
    double progress,
    double shown,
    Duration? total,
  ) {
    if (total == null || total.inMilliseconds == 0) return Duration.zero;
    return Duration(milliseconds: (total.inMilliseconds * shown).round());
  }

  static String _format(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    String two(int n) => n.toString().padLeft(2, '0');
    if (h > 0) return '${two(h)}:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }
}

class _LiveStrip extends StatelessWidget {
  const _LiveStrip({
    required this.now,
    required this.next,
    required this.onChannelList,
    required this.onEpg,
    required this.onSubtitlePicker,
    required this.subtitlesActive,
  });

  final String? now;
  final String? next;
  final VoidCallback? onChannelList;
  final VoidCallback? onEpg;
  final VoidCallback? onSubtitlePicker;
  final bool subtitlesActive;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.spaceM,
        0,
        DesignTokens.spaceM,
        DesignTokens.spaceM,
      ),
      child: Row(
        children: <Widget>[
          const NetworkStatusBadge(kind: NetworkStatusKind.live),
          const SizedBox(width: DesignTokens.spaceS),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (now != null && now!.isNotEmpty)
                  Text(
                    now!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                if (next != null && next!.isNotEmpty)
                  Text(
                    'Sıradaki: ${next!}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
              ],
            ),
          ),
          if (onSubtitlePicker != null)
            IconButton(
              tooltip: 'Altyazi sec',
              onPressed: onSubtitlePicker,
              icon: Icon(
                Icons.closed_caption_rounded,
                color: subtitlesActive ? scheme.primary : Colors.white,
              ),
            ),
          if (onEpg != null)
            IconButton(
              tooltip: 'Yayin akisi',
              onPressed: onEpg,
              icon: const Icon(
                Icons.event_note_rounded,
                color: Colors.white,
              ),
            ),
          if (onChannelList != null)
            IconButton(
              tooltip: 'Kanal listesi',
              onPressed: onChannelList,
              icon: const Icon(
                Icons.format_list_bulleted_rounded,
                color: Colors.white,
              ),
            ),
        ],
      ),
    );
  }
}
