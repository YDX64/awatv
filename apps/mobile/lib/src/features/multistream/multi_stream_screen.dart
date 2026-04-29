import 'package:awatv_mobile/src/features/multistream/multi_stream_session.dart';
import 'package:awatv_mobile/src/features/multistream/multi_stream_state.dart';
import 'package:awatv_mobile/src/features/multistream/widgets/multi_stream_picker.dart';
import 'package:awatv_mobile/src/features/multistream/widgets/multi_stream_tile.dart';
import 'package:awatv_mobile/src/features/premium/premium_lock_sheet.dart';
import 'package:awatv_mobile/src/shared/premium/feature_gate_provider.dart';
import 'package:awatv_mobile/src/shared/premium/premium_features.dart';
import 'package:awatv_ui/awatv_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Multi-stream view — up to 4 channels rendered side-by-side in a 2x2
/// grid (landscape) or vertical stack (portrait phone).
///
/// Premium-gated under [PremiumFeature.multiScreen]. Free users get the
/// paywall sheet on entry — there is no "1-stream multi-view" because
/// that's just the regular player.
///
/// Audio routing: only the active tile (purple border) plays sound.
/// Tap a different tile to swap audio focus; the previously-active
/// tile mutes within a frame.
///
/// State: lives in [multiStreamSessionProvider] (kept alive). Slots
/// added from the channels long-press menu, the tile picker, or the
/// "+ Kanal ekle" affordance survive route-pops.
class MultiStreamScreen extends ConsumerStatefulWidget {
  const MultiStreamScreen({super.key});

  @override
  ConsumerState<MultiStreamScreen> createState() =>
      _MultiStreamScreenState();
}

class _MultiStreamScreenState extends ConsumerState<MultiStreamScreen> {
  bool _gateChecked = false;

  @override
  void initState() {
    super.initState();
    // Allow rotation to landscape so the 2x2 grid actually has room
    // to breathe on phones. We restore the default in dispose().
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkGate());
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(<DeviceOrientation>[
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    super.dispose();
  }

  /// Premium gate. Free users see the paywall and bounce back; premium
  /// users continue silently. We check post-frame so the route mounts
  /// before the modal slides in.
  void _checkGate() {
    if (_gateChecked) return;
    _gateChecked = true;
    final allowed = ref.read(canUseFeatureProvider(PremiumFeature.multiScreen));
    if (!allowed) {
      PremiumLockSheet.show(context, PremiumFeature.multiScreen).then(
        (_) {
          if (!mounted) return;
          if (context.canPop()) context.pop();
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowed =
        ref.watch(canUseFeatureProvider(PremiumFeature.multiScreen));
    final session = ref.watch(multiStreamSessionProvider);
    final notifier = ref.read(multiStreamSessionProvider.notifier);
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Coklu izle'),
        actions: <Widget>[
          if (session.slots.isNotEmpty)
            IconButton(
              tooltip: 'Tek pencereye don',
              icon: const Icon(Icons.fullscreen_exit_rounded),
              onPressed: () {
                notifier.clear();
                if (context.canPop()) context.pop();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: !allowed
            ? const _LockedState()
            : session.slots.isEmpty
                ? _EmptyMultiState(
                    onAdd: () => MultiStreamPicker.show(context),
                  )
                : _MultiStreamGrid(
                    session: session,
                    onAddSlot: () => MultiStreamPicker.show(context),
                  ),
      ),
      bottomNavigationBar: session.slots.isEmpty
          ? null
          : _BottomBar(
              session: session,
              onMute: notifier.toggleMasterMute,
              onAdd: session.isFull
                  ? null
                  : () => MultiStreamPicker.show(context),
              onClear: () {
                notifier.clear();
                if (context.canPop()) context.pop();
              },
              theme: theme,
            ),
    );
  }
}

/// Free-tier screen body — the paywall handles the upsell, but if the
/// user dismisses it without subscribing we still need something to
/// render after `pop()` lands and before the route unmounts.
class _LockedState extends StatelessWidget {
  const _LockedState();

  @override
  Widget build(BuildContext context) {
    return const EmptyState(
      icon: Icons.lock_rounded,
      title: 'Premium ozellik',
      message: 'Coklu izleme yalnizca Premium kullanicilar icindir.',
    );
  }
}

class _EmptyMultiState extends StatelessWidget {
  const _EmptyMultiState({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.dashboard_customize_rounded,
      title: 'Coklu izlemeye basla',
      message: 'Ayni anda 4 kanala kadar izleyebilirsin. Spor maclarinda '
          'birini sustur, digerini ac — saniyesi bile kacmasin.',
      actionLabel: 'Kanal sec',
      onAction: onAdd,
    );
  }
}

/// 2x2 (landscape / wide) or vertical-stack (portrait phone) grid.
///
/// Layout strategy: ask the LayoutBuilder for the box; if width >=
/// height we go 2-column, otherwise 1-column. The "+" slot appears
/// when the session has fewer than 4 tiles, occupying the next free
/// cell so the user can always add another.
class _MultiStreamGrid extends StatelessWidget {
  const _MultiStreamGrid({required this.session, required this.onAddSlot});

  final MultiStreamState session;
  final VoidCallback onAddSlot;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext _, BoxConstraints c) {
        final isWide = c.maxWidth >= c.maxHeight;
        final cellCount = (session.slots.length + (session.isFull ? 0 : 1))
            .clamp(1, MultiStreamState.kMaxSlots);
        final crossAxis = !isWide
            ? 1
            : cellCount <= 1
                ? 1
                : 2;
        // Aspect: tiles are 16:9 always. The grid auto-sizes the row
        // height to keep that ratio so 4 tiles never get squashed.
        return GridView.builder(
          padding: const EdgeInsets.all(DesignTokens.spaceS),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxis,
            crossAxisSpacing: DesignTokens.spaceS,
            mainAxisSpacing: DesignTokens.spaceS,
            childAspectRatio: 16 / 9,
          ),
          itemCount: cellCount,
          itemBuilder: (BuildContext ctx, int i) {
            if (i >= session.slots.length) {
              // The "+" placeholder.
              return _AddSlotTile(onTap: onAddSlot);
            }
            final slot = session.slots[i];
            return MultiStreamTile(
              key: ValueKey<String>('multi-${slot.channel.id}'),
              slot: slot,
              index: i,
              isActive: i == session.safeActiveIndex,
              masterMuted: session.masterMuted,
            );
          },
        );
      },
    );
  }
}

class _AddSlotTile extends StatelessWidget {
  const _AddSlotTile({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(DesignTokens.radiusM),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusM),
        onTap: onTap,
        child: DottedBorderContainer(
          color: scheme.outline.withValues(alpha: 0.45),
          borderRadius: DesignTokens.radiusM,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.add_circle_outline_rounded,
                  size: 36,
                  color: scheme.primary,
                ),
                const SizedBox(height: DesignTokens.spaceXs),
                Text(
                  'Kanal ekle',
                  style: TextStyle(
                    color: scheme.onSurface.withValues(alpha: 0.85),
                    fontWeight: FontWeight.w700,
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

/// Lightweight dashed-border decoration for the "+" tile. Saves us
/// from depending on an external `dotted_border` package — the few
/// pixels of effort it adds aren't worth a new dep.
class DottedBorderContainer extends StatelessWidget {
  const DottedBorderContainer({
    required this.child,
    required this.color,
    required this.borderRadius,
    super.key,
  });

  final Widget child;
  final Color color;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DashedBorderPainter(color: color, radius: borderRadius),
      child: child,
    );
  }
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rrect);
    // Manual dash: walk the metric in (dash, gap) pairs. PathMetric is
    // cheap to allocate and we redraw rarely (the placeholder is only
    // visible while the user is between channel additions).
    const double dash = 6;
    const double gap = 5;
    final metrics = path.computeMetrics();
    for (final metric in metrics) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = (distance + dash).clamp(0.0, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.session,
    required this.onMute,
    required this.onAdd,
    required this.onClear,
    required this.theme,
  });

  final MultiStreamState session;
  final VoidCallback onMute;
  final VoidCallback? onAdd;
  final VoidCallback onClear;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final scheme = theme.colorScheme;
    return BottomAppBar(
      color: scheme.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.spaceM,
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              session.masterMuted
                  ? '${session.slots.length} kanal • tumu sessiz'
                  : '${session.slots.length} kanal • '
                      '${session.activeSlot?.channel.name ?? ''} aktif',
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            tooltip: session.masterMuted ? 'Sesi ac' : 'Tumunu sustur',
            onPressed: onMute,
            icon: Icon(
              session.masterMuted
                  ? Icons.volume_off_rounded
                  : Icons.volume_up_rounded,
            ),
          ),
          IconButton(
            tooltip: session.isFull
                ? 'Daha fazla ekleyemezsiniz'
                : 'Kanal ekle',
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
          ),
          IconButton(
            tooltip: 'Tek pencereye don',
            onPressed: onClear,
            icon: const Icon(Icons.fullscreen_exit_rounded),
          ),
        ],
      ),
    );
  }
}
