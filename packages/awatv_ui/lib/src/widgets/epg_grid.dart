import 'package:awatv_ui/src/tokens/design_tokens.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Minimal channel descriptor consumed by [EpgGrid].
///
/// The widget is intentionally decoupled from `awatv_core` so it can stay
/// in the design-system package. The hosting screen maps its `Channel`
/// objects to [EpgGridChannel] before passing them in, and tap callbacks
/// hand the raw [id] back.
class EpgGridChannel {
  const EpgGridChannel({
    required this.id,
    required this.tvgId,
    required this.name,
    this.logoUrl,
    this.subtitle,
  });

  /// Stable identifier — surfaced in [EpgGrid] tap callbacks.
  final String id;

  /// EPG matching key (XMLTV `channel` attribute). Empty when the channel
  /// has no programme data — [EpgGrid] will still render the row, just
  /// without programme tiles.
  final String tvgId;

  final String name;
  final String? logoUrl;
  final String? subtitle;
}

/// One programme block in the grid body.
class EpgGridProgramme {
  const EpgGridProgramme({
    required this.id,
    required this.tvgId,
    required this.start,
    required this.stop,
    required this.title,
    this.description,
    this.category,
  });

  final String id;
  final String tvgId;
  final DateTime start;
  final DateTime stop;
  final String title;
  final String? description;
  final String? category;
}

/// Payload delivered to [EpgGrid.onProgrammeTap] / `onProgrammeLongPress`.
class EpgGridProgrammeEvent {
  const EpgGridProgrammeEvent({
    required this.channel,
    required this.programme,
  });

  final EpgGridChannel channel;
  final EpgGridProgramme programme;
}

/// The iconic TV-guide grid: channel rows along the Y axis, time columns
/// along the X axis, programme tiles laid out absolutely in the body.
///
/// Layout:
///
/// ```text
///   ┌─────────────┬─────────────────────────────────────────┐
///   │ corner cell │ time ticks ►                            │  ← top sticky
///   ├─────────────┼─────────────────────────────────────────┤
///   │ channel     │ ░░░░░ programme ░░ ░░░ programme ░░░░░  │
///   │ logos +     │                                         │  ← body
///   │ names ▼     │                                         │
///   │             │                                         │
///   └─────────────┴─────────────────────────────────────────┘
///         ^ left sticky, vertical sync with body
/// ```
///
/// Two pairs of `ScrollController`s keep the axes in lock-step:
///   - vertical : the channel list and the body column scroll together
///   - horizontal: the time row and the body column scroll together
///
/// Scroll propagation uses a re-entry guard (`_isSyncingV` / `_isSyncingH`)
/// so the listener that mirrors A→B doesn't trigger B→A.
///
/// Body cells are absolutely positioned inside a `SizedBox` whose width is
/// `totalWindowMinutes * pixelsPerMinute`. This keeps each frame's work
/// proportional to *visible* tiles only — Flutter culls off-screen
/// `Positioned` widgets inside a clipped scroll viewport.
class EpgGrid extends StatefulWidget {
  const EpgGrid({
    required this.channels,
    required this.programmes,
    required this.now,
    this.timeBlock = const Duration(minutes: 30),
    this.pixelsPerMinute = 6,
    this.rowHeight = 72,
    this.channelColumnWidth = 168,
    this.timeRowHeight = 44,
    this.windowStart,
    this.windowEnd,
    this.onProgrammeTap,
    this.onProgrammeLongPress,
    this.onChannelTap,
    this.focusedProgrammeId,
    this.scrollController,
    super.key,
  });

  /// Rows of the grid, top-to-bottom.
  final List<EpgGridChannel> channels;

  /// Programmes keyed by `tvgId`. Lists must be sorted by `start` ascending.
  /// Channels with no entry render an "EPG yok" placeholder spanning the
  /// full window.
  final Map<String, List<EpgGridProgramme>> programmes;

  /// Wall clock reference. The vertical "now" line is rendered at this time.
  final DateTime now;

  /// Time-tick stride. Defaults to 30 minutes (the IPTV-app convention).
  final Duration timeBlock;

  /// Horizontal scale. 6px/min ⇒ 30 min == 180px (a comfortable tile).
  final double pixelsPerMinute;

  /// Height of each channel row.
  final double rowHeight;

  /// Width of the sticky channel column.
  final double channelColumnWidth;

  /// Height of the sticky top time-tick row.
  final double timeRowHeight;

  /// Override the rendered window. Defaults to `now ± 12h`, snapped down to
  /// the nearest [timeBlock] boundary on the start.
  final DateTime? windowStart;
  final DateTime? windowEnd;

  /// Tap on a programme tile.
  final ValueChanged<EpgGridProgrammeEvent>? onProgrammeTap;

  /// Long-press on a programme tile.
  final ValueChanged<EpgGridProgrammeEvent>? onProgrammeLongPress;

  /// Tap on the channel row's logo / name area.
  final ValueChanged<EpgGridChannel>? onChannelTap;

  /// Optional id of the programme that should render as "focused" — used
  /// by the TV variant for D-pad highlight. UI-only; tap callbacks still
  /// fire normally.
  final String? focusedProgrammeId;

  /// Optional external controller for the body's horizontal scroll. Lets
  /// the host screen jump to the now-line ("Şimdi" button).
  final EpgGridScrollController? scrollController;

  @override
  State<EpgGrid> createState() => _EpgGridState();
}

/// Imperative handle to the grid's horizontal scroll position.
///
/// The hosting screen instantiates one and passes it in via
/// `EpgGrid.scrollController`. After the grid mounts, calling
/// [scrollToNow] animates the body to centre the current-time line.
class EpgGridScrollController {
  _EpgGridState? _state;

  // The `_state` field is private to this controller and only ever reset
  // to a single value during attach — a setter would not improve clarity.
  // ignore: use_setters_to_change_properties
  void _attach(_EpgGridState s) => _state = s;
  void _detach(_EpgGridState s) {
    if (_state == s) _state = null;
  }

  /// Scroll the body horizontally so the now-line is roughly in the middle
  /// of the visible area. No-op when the grid isn't mounted yet.
  Future<void> scrollToNow({
    Duration duration = const Duration(milliseconds: 320),
    Curve curve = Curves.easeOutCubic,
  }) async {
    final s = _state;
    if (s == null || !s.mounted) return;
    return s._scrollToNow(duration: duration, curve: curve);
  }
}

class _EpgGridState extends State<EpgGrid> {
  // Vertical pair: channel column + body.
  final ScrollController _vChannels = ScrollController();
  final ScrollController _vBody = ScrollController();
  bool _isSyncingV = false;

  // Horizontal pair: time row + body.
  final ScrollController _hTime = ScrollController();
  final ScrollController _hBody = ScrollController();
  bool _isSyncingH = false;

  late DateTime _windowStart;
  late DateTime _windowEnd;
  late double _bodyWidth;
  late int _totalMinutes;

  bool _scrolledToNowOnce = false;

  @override
  void initState() {
    super.initState();
    _vChannels.addListener(_onVChannels);
    _vBody.addListener(_onVBody);
    _hTime.addListener(_onHTime);
    _hBody.addListener(_onHBody);
    widget.scrollController?._attach(this);
    _recomputeWindow();
  }

  @override
  void didUpdateWidget(covariant EpgGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?._detach(this);
      widget.scrollController?._attach(this);
    }
    if (oldWidget.windowStart != widget.windowStart ||
        oldWidget.windowEnd != widget.windowEnd ||
        oldWidget.now != widget.now ||
        oldWidget.timeBlock != widget.timeBlock ||
        oldWidget.pixelsPerMinute != widget.pixelsPerMinute) {
      _recomputeWindow();
    }
  }

  void _recomputeWindow() {
    final start = widget.windowStart ??
        widget.now.subtract(const Duration(hours: 12));
    final end = widget.windowEnd ?? widget.now.add(const Duration(hours: 12));

    // Snap start down to the nearest timeBlock boundary so tick labels
    // fall on round minutes (00, 30, 00, ...).
    final blockMinutes = widget.timeBlock.inMinutes <= 0
        ? 30
        : widget.timeBlock.inMinutes;
    final snappedMinute = start.minute - (start.minute % blockMinutes);
    _windowStart = DateTime(
      start.year,
      start.month,
      start.day,
      start.hour,
      snappedMinute,
    );
    _windowEnd = end.isAfter(_windowStart)
        ? end
        : _windowStart.add(const Duration(hours: 1));
    _totalMinutes = _windowEnd.difference(_windowStart).inMinutes;
    _bodyWidth = (_totalMinutes * widget.pixelsPerMinute).clamp(
      widget.pixelsPerMinute * 60,
      double.infinity,
    );
  }

  @override
  void dispose() {
    widget.scrollController?._detach(this);
    _vChannels
      ..removeListener(_onVChannels)
      ..dispose();
    _vBody
      ..removeListener(_onVBody)
      ..dispose();
    _hTime
      ..removeListener(_onHTime)
      ..dispose();
    _hBody
      ..removeListener(_onHBody)
      ..dispose();
    super.dispose();
  }

  // --- Sync listeners ------------------------------------------------------
  void _onVChannels() {
    if (_isSyncingV) return;
    if (!_vBody.hasClients) return;
    _isSyncingV = true;
    final target = _vChannels.offset;
    if ((target - _vBody.offset).abs() > 0.5) {
      _vBody.jumpTo(target.clamp(
        _vBody.position.minScrollExtent,
        _vBody.position.maxScrollExtent,
      ));
    }
    _isSyncingV = false;
  }

  void _onVBody() {
    if (_isSyncingV) return;
    if (!_vChannels.hasClients) return;
    _isSyncingV = true;
    final target = _vBody.offset;
    if ((target - _vChannels.offset).abs() > 0.5) {
      _vChannels.jumpTo(target.clamp(
        _vChannels.position.minScrollExtent,
        _vChannels.position.maxScrollExtent,
      ));
    }
    _isSyncingV = false;
  }

  void _onHTime() {
    if (_isSyncingH) return;
    if (!_hBody.hasClients) return;
    _isSyncingH = true;
    final target = _hTime.offset;
    if ((target - _hBody.offset).abs() > 0.5) {
      _hBody.jumpTo(target.clamp(
        _hBody.position.minScrollExtent,
        _hBody.position.maxScrollExtent,
      ));
    }
    _isSyncingH = false;
  }

  void _onHBody() {
    if (_isSyncingH) return;
    if (!_hTime.hasClients) return;
    _isSyncingH = true;
    final target = _hBody.offset;
    if ((target - _hTime.offset).abs() > 0.5) {
      _hTime.jumpTo(target.clamp(
        _hTime.position.minScrollExtent,
        _hTime.position.maxScrollExtent,
      ));
    }
    _isSyncingH = false;
  }

  Future<void> _scrollToNow({
    Duration duration = const Duration(milliseconds: 320),
    Curve curve = Curves.easeOutCubic,
  }) async {
    if (!_hBody.hasClients) return;
    final viewport = _hBody.position.viewportDimension;
    final nowOffset =
        widget.now.difference(_windowStart).inSeconds /
            60.0 *
            widget.pixelsPerMinute;
    final target = (nowOffset - viewport / 2).clamp(
      _hBody.position.minScrollExtent,
      _hBody.position.maxScrollExtent,
    );
    await _hBody.animateTo(target, duration: duration, curve: curve);
  }

  void _maybeAutoScrollToNow() {
    if (_scrolledToNowOnce) return;
    if (!_hBody.hasClients) return;
    _scrolledToNowOnce = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToNow(duration: Duration.zero);
    });
  }

  // --- Build ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (widget.channels.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(DesignTokens.spaceL),
          child: Text(
            'Kanal yok',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints constraints) {
        // Defer the auto-scroll until the body has dimensions.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _maybeAutoScrollToNow();
        });

        return DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(DesignTokens.radiusL),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusL),
            child: Column(
              children: <Widget>[
                _buildHeaderRow(scheme, theme),
                Expanded(child: _buildBodyRow(scheme, theme)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(ColorScheme scheme, ThemeData theme) {
    return SizedBox(
      height: widget.timeRowHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Corner cell — same width as the channel column, holds the
          // running clock label.
          Container(
            width: widget.channelColumnWidth,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.85),
              border: Border(
                right: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.25),
                ),
                bottom: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.25),
                ),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _formatHm(widget.now),
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: scheme.secondary,
                letterSpacing: 0.4,
              ),
            ),
          ),
          // Sticky time-tick strip.
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                border: Border(
                  bottom: BorderSide(
                    color: scheme.outline.withValues(alpha: 0.25),
                  ),
                ),
              ),
              child: ScrollConfiguration(
                behavior: const _NoOverscroll(),
                child: SingleChildScrollView(
                  controller: _hTime,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: _bodyWidth,
                    height: widget.timeRowHeight,
                    child: _TimeTicks(
                      windowStart: _windowStart,
                      totalMinutes: _totalMinutes,
                      pixelsPerMinute: widget.pixelsPerMinute,
                      timeBlock: widget.timeBlock,
                      scheme: scheme,
                      theme: theme,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBodyRow(ColorScheme scheme, ThemeData theme) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Sticky channel column — vertical scroll mirrored from the body.
        SizedBox(
          width: widget.channelColumnWidth,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
              border: Border(
                right: BorderSide(
                  color: scheme.outline.withValues(alpha: 0.25),
                ),
              ),
            ),
            child: ScrollConfiguration(
              behavior: const _NoOverscroll(),
              child: ListView.builder(
                controller: _vChannels,
                physics: const ClampingScrollPhysics(),
                itemExtent: widget.rowHeight,
                itemCount: widget.channels.length,
                itemBuilder: (BuildContext _, int i) {
                  final ch = widget.channels[i];
                  return _ChannelHeaderCell(
                    channel: ch,
                    rowHeight: widget.rowHeight,
                    onTap: widget.onChannelTap,
                    scheme: scheme,
                    theme: theme,
                  );
                },
              ),
            ),
          ),
        ),
        // Body — both axes scroll, with the now-line painted on top.
        Expanded(
          child: ClipRect(
            child: ScrollConfiguration(
              behavior: const _NoOverscroll(),
              child: Scrollbar(
                controller: _hBody,
                thumbVisibility: false,
                child: SingleChildScrollView(
                  controller: _hBody,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(
                    width: _bodyWidth,
                    child: Stack(
                      children: <Widget>[
                        // Vertical body — programme tiles per channel.
                        ListView.builder(
                          controller: _vBody,
                          physics: const ClampingScrollPhysics(),
                          itemExtent: widget.rowHeight,
                          itemCount: widget.channels.length,
                          itemBuilder: (BuildContext _, int i) {
                            final ch = widget.channels[i];
                            final list = widget.programmes[ch.tvgId] ??
                                const <EpgGridProgramme>[];
                            return _ProgrammeRow(
                              channel: ch,
                              programmes: list,
                              windowStart: _windowStart,
                              windowEnd: _windowEnd,
                              now: widget.now,
                              pixelsPerMinute: widget.pixelsPerMinute,
                              rowHeight: widget.rowHeight,
                              focusedProgrammeId: widget.focusedProgrammeId,
                              onTap: widget.onProgrammeTap,
                              onLongPress: widget.onProgrammeLongPress,
                              scheme: scheme,
                              theme: theme,
                            );
                          },
                        ),
                        IgnorePointer(
                          child: _NowLine(
                            now: widget.now,
                            windowStart: _windowStart,
                            windowEnd: _windowEnd,
                            pixelsPerMinute: widget.pixelsPerMinute,
                            color: scheme.secondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// --- Header bits -----------------------------------------------------------

class _TimeTicks extends StatelessWidget {
  const _TimeTicks({
    required this.windowStart,
    required this.totalMinutes,
    required this.pixelsPerMinute,
    required this.timeBlock,
    required this.scheme,
    required this.theme,
  });

  final DateTime windowStart;
  final int totalMinutes;
  final double pixelsPerMinute;
  final Duration timeBlock;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final blockMinutes = timeBlock.inMinutes <= 0 ? 30 : timeBlock.inMinutes;
    final tickCount = (totalMinutes / blockMinutes).ceil() + 1;
    final ticks = <Widget>[];
    for (var i = 0; i < tickCount; i++) {
      final offsetMin = i * blockMinutes;
      if (offsetMin > totalMinutes) break;
      final time = windowStart.add(Duration(minutes: offsetMin));
      final isFullHour = time.minute == 0;
      ticks.add(
        Positioned(
          left: offsetMin * pixelsPerMinute,
          top: 0,
          bottom: 0,
          child: _TickLabel(
            time: time,
            isFullHour: isFullHour,
            scheme: scheme,
            theme: theme,
          ),
        ),
      );
    }
    return Stack(children: ticks);
  }
}

class _TickLabel extends StatelessWidget {
  const _TickLabel({
    required this.time,
    required this.isFullHour,
    required this.scheme,
    required this.theme,
  });

  final DateTime time;
  final bool isFullHour;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return SizedBox(
      width: 64,
      child: Padding(
        padding: const EdgeInsets.only(left: DesignTokens.spaceXs + 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 1.2,
              height: isFullHour ? 10 : 6,
              color: scheme.outline.withValues(
                alpha: isFullHour ? 0.55 : 0.35,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$hh:$mm',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface.withValues(
                  alpha: isFullHour ? 0.95 : 0.65,
                ),
                fontWeight:
                    isFullHour ? FontWeight.w700 : FontWeight.w500,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Channel column --------------------------------------------------------

class _ChannelHeaderCell extends StatelessWidget {
  const _ChannelHeaderCell({
    required this.channel,
    required this.rowHeight,
    required this.onTap,
    required this.scheme,
    required this.theme,
  });

  final EpgGridChannel channel;
  final double rowHeight;
  final ValueChanged<EpgGridChannel>? onTap;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null ? null : () => onTap!(channel),
        child: Container(
          height: rowHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceS,
            vertical: DesignTokens.spaceXs,
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: scheme.outline.withValues(alpha: 0.18),
              ),
            ),
          ),
          child: Row(
            children: <Widget>[
              _ChannelLogo(channel: channel, scheme: scheme),
              const SizedBox(width: DesignTokens.spaceS),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      channel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (channel.subtitle != null &&
                        channel.subtitle!.isNotEmpty)
                      Text(
                        channel.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.55),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChannelLogo extends StatelessWidget {
  const _ChannelLogo({required this.channel, required this.scheme});

  final EpgGridChannel channel;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final url = channel.logoUrl;
    if (url == null || url.isEmpty) {
      return Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
        ),
        alignment: Alignment.center,
        child: Text(
          channel.name.isEmpty
              ? '?'
              : channel.name.characters.first.toUpperCase(),
          style: TextStyle(
            color: scheme.onSurface.withValues(alpha: 0.85),
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    return Container(
      width: 32,
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(DesignTokens.radiusS),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(DesignTokens.radiusS - 2),
        child: CachedNetworkImage(
          imageUrl: url,
          fit: BoxFit.contain,
          fadeInDuration: DesignTokens.motionFast,
          errorWidget: (_, __, ___) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}

// --- Body row --------------------------------------------------------------

class _ProgrammeRow extends StatelessWidget {
  const _ProgrammeRow({
    required this.channel,
    required this.programmes,
    required this.windowStart,
    required this.windowEnd,
    required this.now,
    required this.pixelsPerMinute,
    required this.rowHeight,
    required this.focusedProgrammeId,
    required this.onTap,
    required this.onLongPress,
    required this.scheme,
    required this.theme,
  });

  final EpgGridChannel channel;
  final List<EpgGridProgramme> programmes;
  final DateTime windowStart;
  final DateTime windowEnd;
  final DateTime now;
  final double pixelsPerMinute;
  final double rowHeight;
  final String? focusedProgrammeId;
  final ValueChanged<EpgGridProgrammeEvent>? onTap;
  final ValueChanged<EpgGridProgrammeEvent>? onLongPress;
  final ColorScheme scheme;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      // Bottom hairline — keeps rows visually separated even when there
      // are gaps between programmes.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 1,
        child: ColoredBox(
          color: scheme.outline.withValues(alpha: 0.12),
        ),
      ),
    ];

    if (programmes.isEmpty) {
      // No EPG for this channel — show a single muted placeholder spanning
      // the whole window.
      tiles.add(
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(DesignTokens.spaceXs),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(DesignTokens.radiusS),
                border: Border.all(
                  color: scheme.outline.withValues(alpha: 0.18),
                ),
              ),
              child: Center(
                child: Text(
                  'EPG yok',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      return SizedBox(
        height: rowHeight,
        child: Stack(children: tiles),
      );
    }

    for (final p in programmes) {
      // Clip programme to the visible window.
      final clipStart = p.start.isBefore(windowStart) ? windowStart : p.start;
      final clipStop = p.stop.isAfter(windowEnd) ? windowEnd : p.stop;
      if (!clipStop.isAfter(clipStart)) continue;

      final leftMin =
          clipStart.difference(windowStart).inSeconds / 60.0;
      final widthMin = clipStop.difference(clipStart).inSeconds / 60.0;
      final left = leftMin * pixelsPerMinute;
      final width = (widthMin * pixelsPerMinute).clamp(
        60.0,
        double.infinity,
      );

      tiles.add(
        Positioned(
          left: left,
          top: 0,
          bottom: 0,
          width: width,
          child: _ProgrammeTile(
            channel: channel,
            programme: p,
            now: now,
            focused: focusedProgrammeId == p.id,
            onTap: onTap,
            onLongPress: onLongPress,
            scheme: scheme,
            theme: theme,
          ),
        ),
      );
    }

    return SizedBox(
      height: rowHeight,
      child: Stack(children: tiles),
    );
  }
}

class _ProgrammeTile extends StatelessWidget {
  const _ProgrammeTile({
    required this.channel,
    required this.programme,
    required this.now,
    required this.focused,
    required this.onTap,
    required this.onLongPress,
    required this.scheme,
    required this.theme,
  });

  final EpgGridChannel channel;
  final EpgGridProgramme programme;
  final DateTime now;
  final bool focused;
  final ValueChanged<EpgGridProgrammeEvent>? onTap;
  final ValueChanged<EpgGridProgrammeEvent>? onLongPress;
  final ColorScheme scheme;
  final ThemeData theme;

  bool get _isLive =>
      !now.isBefore(programme.start) && now.isBefore(programme.stop);

  bool get _isPast => now.isAfter(programme.stop);

  @override
  Widget build(BuildContext context) {
    final live = _isLive;
    final past = _isPast;

    final fill = live
        ? scheme.primary.withValues(alpha: 0.55)
        : past
            ? scheme.surfaceContainerHighest.withValues(alpha: 0.35)
            : scheme.surfaceContainerHighest.withValues(alpha: 0.85);
    final borderColor = focused
        ? scheme.secondary
        : live
            ? scheme.primary
            : scheme.outline.withValues(alpha: past ? 0.15 : 0.30);
    final titleColor = live
        ? Colors.white
        : scheme.onSurface
            .withValues(alpha: past ? 0.55 : 0.95);
    final timeColor = live
        ? Colors.white.withValues(alpha: 0.85)
        : scheme.onSurface
            .withValues(alpha: past ? 0.45 : 0.7);

    final hh = programme.start.hour.toString().padLeft(2, '0');
    final mm = programme.start.minute.toString().padLeft(2, '0');

    final event = EpgGridProgrammeEvent(
      channel: channel,
      programme: programme,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: 1,
        vertical: DesignTokens.spaceXs,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(DesignTokens.radiusS),
          onTap: onTap == null ? null : () => onTap!(event),
          onLongPress:
              onLongPress == null ? null : () => onLongPress!(event),
          child: Container(
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(DesignTokens.radiusS),
              border: Border.all(
                color: borderColor,
                width: focused ? 2.0 : (live ? 1.2 : 0.6),
              ),
              boxShadow: live
                  ? <BoxShadow>[
                      BoxShadow(
                        color: scheme.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.spaceS,
              vertical: DesignTokens.spaceXs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      '$hh:$mm',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: timeColor,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    if (live) ...<Widget>[
                      const SizedBox(width: DesignTokens.spaceXs),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.white.withValues(alpha: 0.9),
                              blurRadius: 5,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Flexible(
                  child: Text(
                    programme.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: titleColor,
                      fontWeight:
                          live ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Now line --------------------------------------------------------------

class _NowLine extends StatelessWidget {
  const _NowLine({
    required this.now,
    required this.windowStart,
    required this.windowEnd,
    required this.pixelsPerMinute,
    required this.color,
  });

  final DateTime now;
  final DateTime windowStart;
  final DateTime windowEnd;
  final double pixelsPerMinute;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (now.isBefore(windowStart) || now.isAfter(windowEnd)) {
      return const SizedBox.shrink();
    }
    final offsetMin = now.difference(windowStart).inSeconds / 60.0;
    final left = offsetMin * pixelsPerMinute;
    return Positioned(
      left: left - 1,
      top: 0,
      bottom: 0,
      width: 2,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: color.withValues(alpha: 0.55),
              blurRadius: 8,
            ),
          ],
        ),
      ),
    );
  }
}

// --- Helpers ---------------------------------------------------------------

String _formatHm(DateTime t) {
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

/// Strips the bouncing overscroll glow on every platform — the glow draws
/// outside the parent's clip rect on Android and looks broken when the
/// scroll views are nested in two axes.
class _NoOverscroll extends ScrollBehavior {
  const _NoOverscroll();

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
